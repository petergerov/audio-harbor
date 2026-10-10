#if os(macOS)
import Foundation
import OSLog

/// Plays to a UPnP MediaRenderer: registers the file with `MediaHTTPServer`, drives AVTransport,
/// polls position, and reports volume from RenderingControl.
@MainActor
final class UPnPPlaybackEngine: PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var activeFormatLabel: String?
    private(set) var pathLabel: String = "Network"
    private(set) var meterLeft: Double = 0
    private(set) var meterRight: Double = 0

    private let mediaServer: MediaHTTPServer
    private let browser: SSDPBrowser
    private let control = UPnPControlPoint()
    private let logger = Logger(subsystem: "com.gerov.audioharbor.player", category: "UPnP")

    private var preferredUID: String?
    /// Last resolved renderer for the pick — kept across brief SSDP drops so Play/load
    /// do not fail with "not available" while the Bose is still on the LAN.
    private var pinnedRenderer: UPnPRenderer?
    private var loadedTrack: Track?
    private var stream: MediaStreamHandle?
    private var streamURL: URL?
    private var artwork: MediaStreamHandle?
    private var onTrackEnded: ((Track) -> Void)?
    private var outputStatusHandler: ((OutputStatus) -> Void)?
    private var outputVolumeHandler: ((Double?) -> Void)?
    private var pollTask: Task<Void, Never>?
    private var transportTask: Task<Void, Never>?
    private var transportGeneration: UInt64 = 0
    private var wantsPlayback = false
    private var sawPlaying = false
    private var lastVolume: Double?
    /// Cached GetProtocolInfo sink list per renderer UDN.
    private var sinkByUDN: [String: String] = [:]
    /// `nil` = not tried yet; caches whether SetNextAVTransportURI is accepted.
    private var supportsSetNextByUDN: [String: Bool] = [:]

    private var nextTrack: Track?
    private var nextStream: MediaStreamHandle?
    private var nextStreamURL: URL?
    private var nextArtwork: MediaStreamHandle?
    private var preparedNextReady = false
    /// Set when gapless already promoted the next track; `adoptPreparedNext()` returns it once.
    private var pendingAdoption: Track?
    private var watchTask: Task<Void, Never>?
    /// Keeps the Mac from idle sleep while the renderer is playing — network audio does not
    /// hold the Core Audio device awake the way a local DAC path does.
    private var awake: NSObjectProtocol?
    private var streamQuality: NetworkStreamQuality = .full
    private var dsdMode: NetworkDsdMode = .pcm

    init(mediaServer: MediaHTTPServer, browser: SSDPBrowser) {
        self.mediaServer = mediaServer
        self.browser = browser
        watchTask = Task { [weak self] in
            // Re-check when the live renderer list changes (power cycle / Wi-Fi drop).
            var previous: [String] = []
            while let self, !Task.isCancelled {
                let ids = self.browser.renderers.map(\.udn)
                if ids != previous {
                    previous = ids
                    self.handleRendererListChanged()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var renderer: UPnPRenderer? {
        guard let preferredUID, preferredUID.hasPrefix("upnp:") else { return nil }
        if let live = liveRenderer(for: preferredUID) {
            pinnedRenderer = live
            return live
        }
        if let pinned = pinnedRenderer, Self.matches(pinned, preferredUID) {
            return pinned
        }
        return nil
    }

    private func liveRenderer(for uid: String) -> UPnPRenderer? {
        browser.renderers.first { Self.matches($0, uid) }
    }

    private static func matches(_ renderer: UPnPRenderer, _ uid: String) -> Bool {
        if renderer.outputUID.caseInsensitiveCompare(uid) == .orderedSame { return true }
        let bare = uid.hasPrefix("upnp:") ? String(uid.dropFirst("upnp:".count)) : uid
        if renderer.udn.caseInsensitiveCompare(bare) == .orderedSame { return true }
        return renderer.udn.ssdpUDN.caseInsensitiveCompare(bare.ssdpUDN) == .orderedSame
    }

    /// Brief wait after M-SEARCH — launch / Wi‑Fi blip can leave the pick unresolved for a moment.
    private func waitForRenderer(seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if renderer != nil { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: - PlaybackEngine

    func load(_ track: Track) async throws {
        transportTask?.cancel()
        transportTask = nil
        transportGeneration &+= 1
        wantsPlayback = false
        stopPolling()
        clearNext()
        pendingAdoption = nil
        clearCurrentMedia()
        if renderer == nil {
            browser.searchNow()
            await waitForRenderer(seconds: 4)
        }
        guard let renderer else {
            setPlaybackState(.failed(
                "Network player is not available — pick it again in Settings when it appears."
            ))
            throw PlaybackEngineError.deviceUnavailable
        }
        if !mediaServer.isRunning {
            mediaServer.start()
        }
        setPlaybackState(.loading)
        loadedTrack = track
        sawPlaying = false
        preparedNextReady = false
        currentTime = 0
        duration = track.duration

        let prepared = try await prepareMedia(track: track, renderer: renderer)
        stream = prepared.stream
        streamURL = prepared.url
        artwork = prepared.artwork
        activeFormatLabel = prepared.formatLabel
        pathLabel = prepared.pathLabel
        if let dur = prepared.duration { duration = dur }

        do {
            try await control.setAVTransportURI(
                renderer,
                uri: prepared.url.absoluteString,
                metadata: prepared.metadata
            )
            setPlaybackState(.paused)
            await refreshVolume(renderer)
            logger.info(
                "Loaded \(track.title, privacy: .public) on \(renderer.name, privacy: .public) as \(prepared.via, privacy: .public)"
            )
        } catch {
            clearCurrentMedia()
            setPlaybackState(.failed(error.localizedDescription))
            logger.error("SetAVTransportURI failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func prepareNext(_ track: Track?) async {
        clearNext()
        guard let track, let renderer, loadedTrack != nil else { return }
        if supportsSetNextByUDN[renderer.udn] == false { return }

        let prepared: PreparedMedia
        do {
            prepared = try await prepareMedia(track: track, renderer: renderer)
        } catch {
            logger.debug("prepareNext media failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        do {
            try await control.setNextAVTransportURI(
                renderer,
                uri: prepared.url.absoluteString,
                metadata: prepared.metadata
            )
            supportsSetNextByUDN[renderer.udn] = true
            nextTrack = track
            nextStream = prepared.stream
            nextStreamURL = prepared.url
            nextArtwork = prepared.artwork
            preparedNextReady = true
            logger.info("SetNext \(track.title, privacy: .public)")
        } catch {
            mediaServer.unregister(prepared.stream)
            if let art = prepared.artwork { mediaServer.unregister(art) }
            supportsSetNextByUDN[renderer.udn] = false
            logger.info(
                "\(renderer.name, privacy: .public) has no SetNext — track changes without gapless"
            )
        }
    }

    func adoptPreparedNext() -> Track? {
        if let pending = pendingAdoption {
            pendingAdoption = nil
            return pending
        }
        guard preparedNextReady, let next = nextTrack else { return nil }
        promotePreparedNext(next)
        return next
    }

    private func promotePreparedNext(_ next: Track) {
        if let stream { mediaServer.unregister(stream) }
        if let artwork { mediaServer.unregister(artwork) }
        loadedTrack = next
        stream = nextStream
        streamURL = nextStreamURL
        artwork = nextArtwork
        duration = next.duration
        currentTime = 0
        sawPlaying = true
        setPlaybackState(.playing)
        nextTrack = nil
        nextStream = nil
        nextStreamURL = nil
        nextArtwork = nil
        preparedNextReady = false
        pendingAdoption = next
        startPolling()
    }

    func play() {
        guard let renderer, loadedTrack != nil else { return }
        transportTask?.cancel()
        transportGeneration &+= 1
        let generation = transportGeneration
        wantsPlayback = true
        // PlaybackEngine.play() is synchronous. Publish the requested state now so its caller
        // can immediately turn a second tap into Pause while the SOAP request is still pending.
        setPlaybackState(.playing)
        transportTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == self.transportGeneration {
                    self.transportTask = nil
                }
            }
            do {
                try await self.control.play(renderer)
                guard !Task.isCancelled,
                      generation == self.transportGeneration,
                      self.wantsPlayback
                else { return }
                self.sawPlaying = true
                self.setPlaybackState(.playing)
                self.startPolling()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      generation == self.transportGeneration,
                      self.wantsPlayback
                else { return }
                // Bose / some DLNA boxes hold the Play SOAP until HTTP has buffered —
                // the reply times out even though transport is already PLAYING.
                if Self.isTimeout(error), await self.waitUntilPlaying(renderer, seconds: 20) {
                    guard !Task.isCancelled,
                          generation == self.transportGeneration,
                          self.wantsPlayback
                    else { return }
                    self.sawPlaying = true
                    self.setPlaybackState(.playing)
                    self.startPolling()
                    self.logger.info(
                        "Play reply timed out; \(renderer.name, privacy: .public) is playing"
                    )
                    return
                }
                guard !Task.isCancelled,
                      generation == self.transportGeneration,
                      self.wantsPlayback
                else { return }
                self.wantsPlayback = false
                self.logger.error("Play failed: \(error.localizedDescription, privacy: .public)")
                self.setPlaybackState(.failed(error.localizedDescription))
            }
        }
    }

    /// True when the error is a client/server request timeout (not a UPnP fault).
    private static func isTimeout(_ error: Error) -> Bool {
        if let url = error as? URLError, url.code == .timedOut { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorTimedOut { return true }
        return error.localizedDescription.localizedCaseInsensitiveContains("timed out")
    }

    /// Polls transport until PLAYING / TRANSITIONING or `seconds` elapse.
    private func waitUntilPlaying(_ renderer: UPnPRenderer, seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let info = try? await control.getTransportInfo(renderer) {
                switch info.state.uppercased() {
                case "PLAYING", "TRANSITIONING":
                    return true
                default:
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return false
    }

    func pause() {
        guard let renderer else { return }
        transportTask?.cancel()
        transportGeneration &+= 1
        let generation = transportGeneration
        wantsPlayback = false
        stopPolling()
        // Tell the UI / remote immediately — the SOAP round-trip can take hundreds of ms.
        setPlaybackState(.paused)
        transportTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == self.transportGeneration {
                    self.transportTask = nil
                }
            }
            do {
                try await self.control.pause(renderer)
                guard !Task.isCancelled,
                      generation == self.transportGeneration,
                      !self.wantsPlayback
                else { return }
                self.setPlaybackState(.paused)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == self.transportGeneration else { return }
                self.logger.error("Pause failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        transportTask?.cancel()
        transportTask = nil
        transportGeneration &+= 1
        wantsPlayback = false
        stopPolling()
        let renderer = self.renderer
        loadedTrack = nil
        currentTime = 0
        duration = 0
        activeFormatLabel = nil
        setPlaybackState(.idle)
        pendingAdoption = nil
        clearNext()
        clearCurrentMedia()
        guard let renderer else { return }
        Task {
            try? await control.stop(renderer)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let renderer else { return }
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = clamped
        Task {
            do {
                try await control.seek(renderer, to: clamped)
            } catch {
                logger.error("Seek failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func setOutputMode(_ mode: OutputMode) {}

    func setOutputDevice(uid: String?) {
        preferredUID = uid
        if let uid, uid.hasPrefix("upnp:") {
            if let live = liveRenderer(for: uid) {
                pinnedRenderer = live
            } else if let pinned = pinnedRenderer, !Self.matches(pinned, uid) {
                pinnedRenderer = nil
            }
        } else {
            pinnedRenderer = nil
            stop()
        }
        publishVolumeAvailability()
    }

    func setOutputStatusHandler(_ handler: @escaping (OutputStatus) -> Void) {
        outputStatusHandler = handler
        handler(OutputStatus())
    }

    func setOutputVolume(_ level: Double) {
        guard let renderer else { return }
        let percent = Int((min(1, max(0, level)) * 100).rounded())
        lastVolume = Double(percent) / 100
        outputVolumeHandler?(lastVolume)
        Task {
            do {
                try await control.setVolume(renderer, level: percent)
            } catch {
                logger.debug("SetVolume failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func setOutputVolumeHandler(_ handler: @escaping (Double?) -> Void) {
        outputVolumeHandler = handler
        publishVolumeAvailability()
    }

    func setTrackEndedHandler(_ handler: @escaping (Track) -> Void) {
        onTrackEnded = handler
    }

    // MARK: - Prepare media

    private struct PreparedMedia {
        var stream: MediaStreamHandle
        var url: URL
        var artwork: MediaStreamHandle?
        var metadata: String
        /// Nil = Deck keeps the catalogue format · rate; path carries stream mode.
        var formatLabel: String?
        var pathLabel: String
        var duration: TimeInterval?
        var via: String
    }

    func setNetworkStreamQuality(_ quality: NetworkStreamQuality) {
        streamQuality = quality
    }

    func setNetworkDsdMode(_ mode: NetworkDsdMode) {
        dsdMode = mode
    }

    func networkPlayerFormats(uid: String) async -> NetworkPlayerFormats? {
        guard uid.hasPrefix("upnp:") else { return nil }
        guard let renderer = liveRenderer(for: uid)
            ?? (pinnedRenderer.flatMap { Self.matches($0, uid) ? $0 : nil })
        else {
            return NetworkPlayerFormats(online: false, nativeDsd: [], volume: nil)
        }
        let sink = await protocolSink(for: renderer)
        var volume: Double?
        if let percent = try? await control.getVolume(renderer) {
            volume = Double(min(100, max(0, percent))) / 100
        }
        return NetworkPlayerFormats(
            online: true,
            nativeDsd: NetworkMediaPlanner.nativeDsdContainers(sink: sink),
            volume: volume
        )
    }

    private func prepareMedia(track: Track, renderer: UPnPRenderer) async throws -> PreparedMedia {
        let sink = await protocolSink(for: renderer)
        let quality = streamQuality
        let plan = try NetworkMediaPlanner.plan(
            track: track,
            sinkProtocolInfo: sink,
            quality: quality,
            dsdMode: dsdMode
        )

        let handle: MediaStreamHandle
        let mime: String
        // Leave nil so FormatBadge shows DSF/SACD/FLAC · rate from the track;
        // conversion / Wi‑Fi mode lives in pathLabel only.
        let formatLabel: String? = nil
        let path = NetworkMediaPlanner.pathLabel(for: plan, quality: quality, track: track)
        var durationOverride: TimeInterval?
        var via: String

        switch plan {
        case .passthrough(let fileURL, let fileMime, let dsd):
            mime = fileMime
            handle = mediaServer.register(file: fileURL, mime: fileMime)
            via = dsd ? "DSD \(fileMime)" : fileMime
        case .wav(let source):
            mime = source.mime
            handle = mediaServer.register(wav: source)
            // Warm the first chunk so Play’s HTTP GET is not stuck on a cold DSD decode.
            _ = try? source.read(offset: 0, maxLength: 256 * 1024)
            if source.label.hasPrefix("dop·") {
                via = "DoP"
            } else if quality == .wifi {
                via = "Wi‑Fi PCM"
            } else if NetworkMediaPlanner.needsTranscode(track) {
                via = "DSD→WAV"
            } else {
                via = "WAV"
            }
            if source.frameCount > 0, source.sampleRate > 0 {
                durationOverride = Double(source.frameCount) / Double(source.sampleRate)
            }
        }

        guard let url = mediaServer.url(for: handle, toward: renderer.host) else {
            mediaServer.unregister(handle)
            throw PlaybackEngineError.deviceUnavailable
        }

        var artHandle: MediaStreamHandle?
        var artURL: String?
        if let data = ArtworkCache.data(for: track),
           let registered = mediaServer.registerArtwork(data),
           let absolute = mediaServer.url(for: registered, toward: renderer.host) {
            artHandle = registered
            artURL = absolute.absoluteString
        }

        let metadata = DIDLLite.musicTrack(
            track: track,
            uri: url.absoluteString,
            mime: mime,
            artworkURL: artURL
        )
        return PreparedMedia(
            stream: handle,
            url: url,
            artwork: artHandle,
            metadata: metadata,
            formatLabel: formatLabel,
            pathLabel: path,
            duration: durationOverride,
            via: via
        )
    }

    private func protocolSink(for renderer: UPnPRenderer) async -> String {
        if let cached = sinkByUDN[renderer.udn] { return cached }
        do {
            let info = try await control.getProtocolInfo(renderer)
            sinkByUDN[renderer.udn] = info.sink
            return info.sink
        } catch {
            logger.debug("GetProtocolInfo failed: \(error.localizedDescription, privacy: .public)")
            sinkByUDN[renderer.udn] = ""
            return ""
        }
    }

    // MARK: - Internals

    private func clearCurrentMedia() {
        if let stream { mediaServer.unregister(stream) }
        if let artwork { mediaServer.unregister(artwork) }
        stream = nil
        streamURL = nil
        artwork = nil
    }

    private func clearNext() {
        if let nextStream { mediaServer.unregister(nextStream) }
        if let nextArtwork { mediaServer.unregister(nextArtwork) }
        nextTrack = nil
        nextStream = nil
        nextStreamURL = nil
        nextArtwork = nil
        preparedNextReady = false
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce() async {
        guard !Task.isCancelled,
              wantsPlayback,
              let renderer,
              let track = loadedTrack,
              state == .playing || state == .paused
        else { return }
        do {
            let transport = try await control.getTransportInfo(renderer)
            guard !Task.isCancelled, wantsPlayback else { return }
            let position = try await control.getPositionInfo(renderer)
            guard !Task.isCancelled, wantsPlayback else { return }
            if let rel = position.relTime {
                currentTime = rel
            }
            if let dur = position.duration, dur > 0 {
                duration = dur
            }

            // Gapless: renderer already moved to the prepared next URI.
            if preparedNextReady,
               let next = nextTrack,
               let nextURL = nextStreamURL?.absoluteString,
               !position.uri.isEmpty,
               position.uri == nextURL {
                let ended = track
                promotePreparedNext(next)
                onTrackEnded?(ended)
                return
            }

            let transportState = transport.state.uppercased()
            if transportState == "PLAYING" {
                sawPlaying = true
                if state != .playing { setPlaybackState(.playing) }
            } else if transportState == "PAUSED_PLAYBACK" {
                if state == .playing { setPlaybackState(.paused) }
            } else if transportState == "STOPPED" || transportState == "NO_MEDIA_PRESENT" {
                if sawPlaying, state == .playing {
                    stopPolling()
                    setPlaybackState(.paused)
                    currentTime = duration
                    if preparedNextReady, let next = nextTrack {
                        let ended = track
                        promotePreparedNext(next)
                        onTrackEnded?(ended)
                    } else {
                        onTrackEnded?(track)
                    }
                }
            }
        } catch {
            logger.debug("Poll failed: \(error.localizedDescription, privacy: .public)")
            // Repeated failure while a pick is online usually means the renderer went away mid-play.
            if rendererGoneWhilePlaying() {
                failRendererLost()
            }
        }
    }

    private func handleRendererListChanged() {
        guard let preferredUID, preferredUID.hasPrefix("upnp:") else { return }
        // Refresh the pin from SSDP; only fail when the pick vanished and we never had one.
        if let live = liveRenderer(for: preferredUID) {
            pinnedRenderer = live
            return
        }
        // Soft drop from the discovery list is common (short max-age). Keep the pin and
        // ask SSDP again — fail only when poll SOAP also cannot reach the device.
        if pinnedRenderer != nil {
            browser.searchNow()
            return
        }
        if loadedTrack != nil, state == .playing || state == .paused || state == .loading {
            failRendererLost()
        }
    }

    private func rendererGoneWhilePlaying() -> Bool {
        preferredUID?.hasPrefix("upnp:") == true
            && liveRenderer(for: preferredUID ?? "") == nil
            && pinnedRenderer == nil
            && loadedTrack != nil
    }

    private func failRendererLost() {
        stopPolling()
        let name = loadedTrack.map { _ in "Network player" } ?? "Network player"
        clearNext()
        // Keep stream registered briefly in case it comes back; drop transport state.
        setPlaybackState(.failed("\(name) left the network — pick it again when it is back."))
        logger.warning("Renderer lost while playing")
    }

    /// Updates `state` and holds / releases the idle-sleep assertion for network play.
    private func setPlaybackState(_ new: PlaybackState) {
        state = new
        updateSleepAssertion()
    }

    private func updateSleepAssertion() {
        let wantsAwake: Bool = {
            switch state {
            case .playing: true
            case .loading, .paused, .idle, .failed: false
            }
        }()
        if wantsAwake {
            guard awake == nil else { return }
            awake = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Playing to a network player"
            )
            logger.debug("Sleep assertion on")
        } else if let token = awake {
            ProcessInfo.processInfo.endActivity(token)
            awake = nil
            logger.debug("Sleep assertion off")
        }
    }

    private func refreshVolume(_ renderer: UPnPRenderer) async {
        do {
            let percent = try await control.getVolume(renderer)
            lastVolume = Double(percent) / 100
            outputVolumeHandler?(lastVolume)
        } catch {
            lastVolume = nil
            outputVolumeHandler?(nil)
        }
    }

    private func publishVolumeAvailability() {
        if renderer != nil {
            outputVolumeHandler?(lastVolume)
            if let renderer, lastVolume == nil {
                Task { await refreshVolume(renderer) }
            }
        } else {
            outputVolumeHandler?(nil)
        }
    }
}
#endif

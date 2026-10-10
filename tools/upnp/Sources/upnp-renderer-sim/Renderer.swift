import AVFoundation
import Foundation
import UPnPCommon

enum TransportState: String {
    case noMedia = "NO_MEDIA_PRESENT"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
}

struct Loaded: Sendable {
    let file: URL
    let duration: Double
    let label: String
}

struct Media {
    let uri: String
    let metadata: String
    /// From the DIDL-Lite `duration` until the file is fetched.
    let announcedDuration: Double?
    var loaded: Loaded?

    var duration: Double? { loaded?.duration ?? announcedDuration }
    var name: String { URL(string: uri)?.lastPathComponent ?? uri }

    init(uri: String, metadata: String) {
        self.uri = uri
        self.metadata = metadata
        announcedDuration = resAttribute("duration", in: metadata).flatMap(parseTime)
    }
}

/// A single-instance UPnP AV MediaRenderer: AVTransport, RenderingControl, ConnectionManager,
/// GENA eventing. It fetches the whole file over HTTP, then plays it with AVAudioPlayer (or a
/// clock with --silent). The position always comes from the clock, so silent and audible agree.
@MainActor
final class Renderer {
    private struct Subscription {
        let service: String
        let callback: URL
        var seq: UInt32
        var expires: Date
    }

    private let profile: Profile
    private var http: HTTPServer?
    private var ssdp: SSDPResponder?
    private var ticker: Task<Void, Never>?
    private var signalSource: DispatchSourceSignal?

    private var state = TransportState.noMedia
    private var status = "OK"
    private var current: Media?
    private var next: Media?
    private var loads: [String: Task<Loaded, Error>] = [:]
    private var ready: [String: Loaded] = [:]
    private var player: AVAudioPlayer?
    private var clockBase: Double = 0
    private var clockStart: Date?
    private var playGeneration = 0
    private var volume: Int
    private var muted = false
    private var failNextLoad = false
    private var subscriptions: [String: Subscription] = [:]
    private var notifyChain: Task<Void, Never>?

    init(profile: Profile) {
        self.profile = profile
        volume = profile.initialVolume
    }

    func start() throws {
        let server = try HTTPServer(port: profile.httpPort, serverName: "macOS UPnP/1.0 AudioHarborRendererSim/0.1") { [unowned self] request in
            await self.handle(request)
        }
        server.start()
        http = server
        let responder = SSDPResponder(uuid: profile.uuid, httpPort: profile.httpPort, deviceType: RendererTypes.device,
                                      serviceTypes: RendererTypes.services,
                                      server: "macOS UPnP/1.0 AudioHarborRendererSim/0.1")
        try responder.start()
        ssdp = responder

        // A Task, not a Timer: under dispatchMain() the main run loop never runs.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.shutdown() }
            exit(0)
        }
        source.resume()
        signalSource = source

        say("""
        renderer: \(profile.name) — \(profile.uuid)
          description http://<this Mac>:\(profile.httpPort)/description.xml
          SetNext \(profile.supportsNext ? "on" : "off") · events \(profile.supportsEvents ? "on" : "off") · \
        max \(Int(profile.maxSampleRate)) Hz · volume \(volume) · \(profile.silent ? "silent" : "plays on this Mac")
          accepts: \(profile.acceptedMIMETypes.sorted().joined(separator: ", "))
        Console: status · vol <n> (the knob) · mute · fail (next load fails) · offline / online (power) · quit
        """)
    }

    func shutdown() {
        ssdp?.announce(alive: false)
        player?.stop()
        say("bye")
    }

    // MARK: - Console

    func console() async {
        let lines = AsyncStream<String> { continuation in
            Thread.detachNewThread {
                while let line = readLine() { continuation.yield(line) }
                continuation.finish()
            }
        }
        for await line in lines {
            let words = line.split(separator: " ").map(String.init)
            guard let command = words.first else { continue }
            switch command {
            case "status", "s":
                say("status: \(state.rawValue) \(hms(position))/\(current?.duration.map(hms) ?? "-") "
                    + "current=\(current?.name ?? "-") next=\(next?.name ?? "-") volume=\(volume)\(muted ? " muted" : "") "
                    + "subscriptions=\(subscriptions.count) status=\(status)")
            case "vol":
                guard let level = words.dropFirst().first.flatMap(Int.init), (0...100).contains(level) else {
                    say("vol 0…100")
                    continue
                }
                setVolume(level)
                say("knob: volume \(level)")
            case "mute":
                muted.toggle()
                applyGain()
                emitRenderingControl()
                say("knob: \(muted ? "muted" : "unmuted")")
            case "fail":
                failNextLoad = true
                say("the next file load will fail")
            case "offline":
                goOffline()
            case "online":
                http?.online = true
                ssdp?.online = true
                ssdp?.announce(alive: true)
                say("power on — fresh state, no subscriptions")
            case "quit", "q":
                return
            default:
                say("status · vol <n> · mute · fail · offline · online · quit")
            }
        }
    }

    private func goOffline() {
        ssdp?.announce(alive: false)
        ssdp?.online = false
        http?.online = false
        stopAudio()
        current = nil
        next = nil
        state = .noMedia
        status = "OK"
        clockBase = 0
        subscriptions.removeAll()
        say("power off — no SSDP answers, HTTP connections dropped")
    }

    // MARK: - HTTP routing

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let parts = path.split(separator: "/").map(String.init)
        switch (request.method, parts.first, parts.count) {
        case ("GET", "description.xml", 1), ("HEAD", "description.xml", 1):
            say("http ← \(request.peer) GET \(path)")
            return .xml(Documents.description(profile))
        case ("GET", "scpd", 2):
            say("http ← \(request.peer) GET \(path)")
            let service = parts[1].replacingOccurrences(of: ".xml", with: "")
            return Documents.scpd(service, profile).map { .xml($0) } ?? .notFound
        case ("POST", "ctl", 2):
            return await soap(parts[1], request)
        case ("SUBSCRIBE", "evt", 2):
            return subscribe(parts[1], request)
        case ("UNSUBSCRIBE", "evt", 2):
            let sid = request.headers["SID"] ?? ""
            let known = subscriptions.removeValue(forKey: sid) != nil
            say("gena ← UNSUBSCRIBE \(parts[1]) \(sid) → \(known ? "ok" : "unknown")")
            return HTTPResponse(status: known ? "200 OK" : "412 Precondition Failed")
        default:
            say("http ← \(request.peer) \(request.method) \(path) → 404")
            return .notFound
        }
    }

    // MARK: - SOAP

    private func soap(_ service: String, _ request: HTTPRequest) async -> HTTPResponse {
        let action = SOAPText.action(fromHeader: request.headers["SOAPACTION"])
        let args = XMLLeaves.parse(request.body).values
        let serviceType = RendererTypes.services.first { serviceShortName($0) == service } ?? ""
        let shown = args.filter { $0.key != "Envelope" && $0.key != "Body" && $0.key != action }
            .sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.short($0.value))" }.joined(separator: " ")
        let quiet = action == "GetPositionInfo" || action == "GetTransportInfo"
        if !quiet { say("soap ← \(service).\(action) \(shown)") }
        do {
            guard Documents.actions(service, profile).contains(where: { $0.0 == action }) else { throw UPnPError.invalidAction }
            if service != "ConnectionManager", args["InstanceID"] != "0" { throw UPnPError.invalidInstanceID }
            let output = try await perform(service, action, args)
            if !quiet, !output.isEmpty {
                say("soap → \(action) " + output.map { "\($0.0)=\(Self.short($0.1))" }.joined(separator: " "))
            }
            return .xml(SOAPText.response(action, serviceType: serviceType, output))
        } catch {
            let upnp = error as? UPnPError ?? .actionFailed
            say("soap ✗ \(service).\(action) → \(upnp.code) \(upnp.text)\(error is UPnPError ? "" : " (\(error))")")
            return .xml(SOAPText.fault(upnp), status: "500 Internal Server Error")
        }
    }

    private func perform(_ service: String, _ action: String, _ args: [String: String]) async throws -> [(String, String)] {
        switch (service, action) {
        case ("AVTransport", "SetAVTransportURI"):
            let uri = args["CurrentURI"] ?? ""
            guard uri.hasPrefix("http://") || uri.hasPrefix("https://") else { throw UPnPError.resourceNotFound }
            let wasPlaying = state == .playing || state == .transitioning
            stopAudio()
            current = Media(uri: uri, metadata: args["CurrentURIMetaData"] ?? "")
            next = nil
            clockBase = 0
            status = "OK"
            state = .stopped
            _ = load(uri)
            if wasPlaying { startPlayback() } else { emitTransport() }
            return []
        case ("AVTransport", "SetNextAVTransportURI"):
            guard current != nil else { throw UPnPError.transitionNotAvailable }
            let uri = args["NextURI"] ?? ""
            if uri.isEmpty {
                next = nil
            } else {
                next = Media(uri: uri, metadata: args["NextURIMetaData"] ?? "")
                _ = load(uri)
            }
            emitTransport()
            return []
        case ("AVTransport", "Play"):
            guard current != nil else { throw UPnPError.transitionNotAvailable }
            switch state {
            case .playing, .transitioning:
                break
            case .paused:
                player?.play()
                clockStart = Date()
                state = .playing
                emitTransport()
            case .stopped, .noMedia:
                startPlayback()
            }
            return []
        case ("AVTransport", "Pause"):
            guard state == .playing else { throw UPnPError.transitionNotAvailable }
            clockBase = position
            clockStart = nil
            player?.pause()
            state = .paused
            emitTransport()
            return []
        case ("AVTransport", "Stop"):
            guard current != nil else { throw UPnPError.transitionNotAvailable }
            stopAudio()
            clockBase = 0
            state = .stopped
            emitTransport()
            return []
        case ("AVTransport", "Seek"):
            guard current != nil else { throw UPnPError.transitionNotAvailable }
            let target: Double
            switch args["Unit"] ?? "" {
            case "REL_TIME", "ABS_TIME":
                guard let time = parseTime(args["Target"] ?? "") else { throw UPnPError.illegalSeekTarget }
                target = time
            case "TRACK_NR":
                guard args["Target"] == "1" else { throw UPnPError.illegalSeekTarget }
                target = 0
            default:
                throw UPnPError.seekModeNotSupported
            }
            if let duration = current?.duration, target > duration { throw UPnPError.illegalSeekTarget }
            try await seek(to: target)
            return []
        case ("AVTransport", "Next"), ("AVTransport", "Previous"):
            throw UPnPError.transitionNotAvailable
        case ("AVTransport", "GetTransportInfo"):
            return [("CurrentTransportState", state.rawValue), ("CurrentTransportStatus", status), ("CurrentSpeed", "1")]
        case ("AVTransport", "GetPositionInfo"):
            let time = hms(position)
            return [("Track", current == nil ? "0" : "1"), ("TrackDuration", current?.duration.map(hms) ?? "0:00:00"),
                    ("TrackMetaData", current?.metadata ?? ""), ("TrackURI", current?.uri ?? ""),
                    ("RelTime", time), ("AbsTime", time), ("RelCount", "2147483647"), ("AbsCount", "2147483647")]
        case ("AVTransport", "GetMediaInfo"):
            return [("NrTracks", current == nil ? "0" : "1"), ("MediaDuration", current?.duration.map(hms) ?? "0:00:00"),
                    ("CurrentURI", current?.uri ?? ""), ("CurrentURIMetaData", current?.metadata ?? ""),
                    ("NextURI", next?.uri ?? ""), ("NextURIMetaData", next?.metadata ?? ""),
                    ("PlayMedium", "NETWORK"), ("RecordMedium", "NOT_IMPLEMENTED"), ("WriteStatus", "NOT_IMPLEMENTED")]
        case ("AVTransport", "GetTransportSettings"):
            return [("PlayMode", "NORMAL"), ("RecQualityMode", "NOT_IMPLEMENTED")]
        case ("AVTransport", "GetDeviceCapabilities"):
            return [("PlayMedia", "NETWORK"), ("RecMedia", "NOT_IMPLEMENTED"), ("RecQualityModes", "NOT_IMPLEMENTED")]
        case ("AVTransport", "GetCurrentTransportActions"):
            return [("Actions", transportActions)]
        case ("RenderingControl", "GetVolume"):
            return [("CurrentVolume", String(volume))]
        case ("RenderingControl", "SetVolume"):
            guard let level = Int(args["DesiredVolume"] ?? ""), (0...100).contains(level) else { throw UPnPError.invalidArgs }
            setVolume(level)
            return []
        case ("RenderingControl", "GetMute"):
            return [("CurrentMute", muted ? "1" : "0")]
        case ("RenderingControl", "SetMute"):
            muted = ["1", "true", "yes"].contains((args["DesiredMute"] ?? "").lowercased())
            applyGain()
            emitRenderingControl()
            return []
        case ("RenderingControl", "GetVolumeDB"):
            return [("CurrentVolume", String(Int(volumeDB * 256)))]
        case ("RenderingControl", "GetVolumeDBRange"):
            return [("MinValue", String(-80 * 256)), ("MaxValue", "0")]
        case ("ConnectionManager", "GetProtocolInfo"):
            return [("Source", ""), ("Sink", profile.sink.joined(separator: ","))]
        case ("ConnectionManager", "GetCurrentConnectionIDs"):
            return [("ConnectionIDs", "0")]
        case ("ConnectionManager", "GetCurrentConnectionInfo"):
            return [("RcsID", "0"), ("AVTransportID", "0"), ("ProtocolInfo", ""), ("PeerConnectionManager", ""),
                    ("PeerConnectionID", "-1"), ("Direction", "Input"), ("Status", "OK")]
        default:
            throw UPnPError.invalidAction
        }
    }

    // MARK: - Playback

    private var position: Double {
        guard let start = clockStart else { return clockBase }
        let time = clockBase + Date().timeIntervalSince(start)
        return min(time, current?.duration ?? time)
    }

    private var gain: Float { muted ? 0 : Float(volume) / 100 }

    private var volumeDB: Double { volume == 0 ? -80 : max(-80, 40 * log10(Double(volume) / 100)) }

    private var transportActions: String {
        switch state {
        case .noMedia: ""
        case .stopped: "Play,Seek"
        case .transitioning: "Stop"
        case .playing: "Pause,Stop,Seek"
        case .paused: "Play,Stop,Seek"
        }
    }

    /// One fetch per URI; prefetching on SetNext is what makes the switch gapless.
    private func load(_ uri: String) -> Task<Loaded, Error> {
        if let task = loads[uri] { return task }
        let fail = failNextLoad
        failNextLoad = false
        let profile = profile
        let task = Task<Loaded, Error> {
            let loaded = try await Self.fetch(uri, profile: profile, fail: fail)
            self.ready[uri] = loaded
            return loaded
        }
        loads[uri] = task
        return task
    }

    nonisolated private static func fetch(_ uri: String, profile: Profile, fail: Bool) async throws -> Loaded {
        guard let url = URL(string: uri) else { throw UPnPError.resourceNotFound }
        if fail { throw ToolError("simulated load failure (fail command)") }
        let started = Date()
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("AudioHarborRendererSim/0.1 DLNADOC/1.50", forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "getcontentFeatures.dlna.org")
        say("fetch → GET \(uri)")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ToolError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) for \(uri)")
        }
        let mime = (http.mimeType ?? "").lowercased()
        guard profile.acceptedMIMETypes.contains(mime) else {
            throw ToolError("Content-Type \(mime.isEmpty ? "(none)" : mime) is not in the sink list")
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("renderer-sim-\(UUID().uuidString).\(fileExtension(mime: mime, url: url))")
        try FileManager.default.moveItem(at: temporary, to: file)
        let audio: AVAudioFile
        do {
            audio = try AVAudioFile(forReading: file)
        } catch {
            throw ToolError("cannot decode \(url.lastPathComponent) (\(mime)): \(error.localizedDescription)")
        }
        let rate = audio.fileFormat.sampleRate
        guard rate <= profile.maxSampleRate else {
            throw ToolError("\(Int(rate)) Hz is above the renderer's \(Int(profile.maxSampleRate)) Hz")
        }
        let duration = Double(audio.length) / rate
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.doubleValue ?? 0
        let label = String(format: "%g kHz, %d ch, %@, %@", rate / 1000, Int(audio.fileFormat.channelCount), hms(duration), mime)
        say(String(format: "fetch ✓ %@ %.1f MB in %.2f s — %@", url.lastPathComponent, size / 1_048_576,
                   Date().timeIntervalSince(started), label))
        return Loaded(file: file, duration: duration, label: label)
    }

    nonisolated private static func fileExtension(mime: String, url: URL) -> String {
        switch mime {
        case "audio/flac", "audio/x-flac": "flac"
        case "audio/wav", "audio/x-wav", "audio/wave": "wav"
        case "audio/aiff", "audio/x-aiff": "aiff"
        case "audio/mp4", "audio/x-m4a": "m4a"
        case "audio/mpeg": "mp3"
        default: url.pathExtension.isEmpty ? "bin" : url.pathExtension
        }
    }

    private func startPlayback() {
        guard let media = current else { return }
        playGeneration += 1
        let generation = playGeneration
        state = .transitioning
        status = "OK"
        emitTransport()
        let task = load(media.uri)
        Task {
            do {
                let loaded = try await task.value
                try? await Task.sleep(nanoseconds: UInt64(profile.startDelay * 1_000_000_000))
                guard generation == playGeneration, current?.uri == media.uri else { return }
                begin(loaded, at: clockBase)
            } catch {
                guard generation == playGeneration else { return }
                loads[media.uri] = nil
                say("play ✗ \(media.name): \(error)")
                state = .stopped
                status = "ERROR_OCCURRED"
                emitTransport()
            }
        }
    }

    private func begin(_ loaded: Loaded, at time: Double) {
        current?.loaded = loaded
        player?.stop()
        player = nil
        if !profile.silent {
            do {
                let audio = try AVAudioPlayer(contentsOf: loaded.file)
                audio.volume = gain
                audio.currentTime = time
                audio.prepareToPlay()
                audio.play()
                player = audio
            } catch {
                say("audio out failed (\(error.localizedDescription)) — the clock keeps running")
            }
        }
        clockBase = time
        clockStart = Date()
        state = .playing
        emitTransport()
        say("▶ \(current?.name ?? "?") from \(hms(time)) — \(loaded.label)")
    }

    private func seek(to time: Double) async throws {
        let resume = state == .playing || state == .transitioning
        clockBase = time
        clockStart = nil
        player?.pause()
        player?.currentTime = time
        say("seek to \(hms(time))")
        guard resume else {
            emitTransport()
            return
        }
        // Real renderers re-buffer briefly after a seek.
        playGeneration += 1
        let generation = playGeneration
        state = .transitioning
        emitTransport()
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard generation == playGeneration else { return }
        if let player {
            player.play()
        } else if let loaded = current?.loaded {
            begin(loaded, at: time)
            return
        }
        clockStart = Date()
        state = .playing
        emitTransport()
    }

    private func stopAudio() {
        playGeneration += 1
        player?.stop()
        player = nil
        clockStart = nil
    }

    private func tick() {
        guard state == .playing, let duration = current?.duration, position >= duration else { return }
        say("■ end of \(current?.name ?? "?")")
        guard let upcoming = next else {
            stopAudio()
            clockBase = 0
            state = .stopped
            emitTransport()
            return
        }
        next = nil
        current = upcoming
        clockBase = 0
        if let loaded = ready[upcoming.uri] {
            // Prefetched: straight on, no TRANSITIONING — the gapless path.
            begin(loaded, at: 0)
        } else {
            stopAudio()
            startPlayback()
        }
    }

    private func setVolume(_ level: Int) {
        volume = level
        applyGain()
        emitRenderingControl()
    }

    private func applyGain() {
        player?.volume = gain
    }

    // MARK: - GENA

    private func subscribe(_ service: String, _ request: HTTPRequest) -> HTTPResponse {
        guard profile.supportsEvents, RendererTypes.services.contains(where: { serviceShortName($0) == service }) else {
            say("gena ← SUBSCRIBE \(service) → refused (events off)")
            return HTTPResponse(status: "412 Precondition Failed")
        }
        let requested = request.headers["TIMEOUT"].flatMap { Int($0.replacingOccurrences(of: "Second-", with: "")) } ?? 1800
        let timeout = min(max(requested, 60), 1800)
        if let sid = request.headers["SID"] {
            guard subscriptions[sid] != nil else {
                say("gena ← renew \(service) \(sid) → unknown")
                return HTTPResponse(status: "412 Precondition Failed")
            }
            subscriptions[sid]?.expires = Date().addingTimeInterval(Double(timeout))
            say("gena ← renew \(service) \(sid) for \(timeout) s")
            return HTTPResponse(status: "200 OK", headers: [("SID", sid), ("TIMEOUT", "Second-\(timeout)")])
        }
        let callbackText = request.headers["CALLBACK"] ?? ""
        guard request.headers["NT"] == "upnp:event",
              let open = callbackText.firstIndex(of: "<"), let close = callbackText.firstIndex(of: ">"), open < close,
              let callback = URL(string: String(callbackText[callbackText.index(after: open)..<close])) else {
            say("gena ← SUBSCRIBE \(service) without NT/CALLBACK → 412")
            return HTTPResponse(status: "412 Precondition Failed")
        }
        let sid = "uuid:" + UUID().uuidString.lowercased()
        subscriptions[sid] = Subscription(service: service, callback: callback, seq: 0,
                                          expires: Date().addingTimeInterval(Double(timeout)))
        say("gena ← SUBSCRIBE \(service) → \(sid), events to \(callback)")
        // The initial event follows the SUBSCRIBE answer, as the spec asks.
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if service == "AVTransport" { emitTransport(only: sid) } else if service == "RenderingControl" { emitRenderingControl(only: sid) }
        }
        return HTTPResponse(status: "200 OK", headers: [("SID", sid), ("TIMEOUT", "Second-\(timeout)")])
    }

    private func emitTransport(only sid: String? = nil) {
        let values: [(String, String)] = [
            ("TransportState", state.rawValue), ("TransportStatus", status), ("TransportPlaySpeed", "1"),
            ("NumberOfTracks", current == nil ? "0" : "1"), ("CurrentTrack", current == nil ? "0" : "1"),
            ("AVTransportURI", current?.uri ?? ""), ("AVTransportURIMetaData", current?.metadata ?? ""),
            ("CurrentTrackURI", current?.uri ?? ""), ("CurrentTrackMetaData", current?.metadata ?? ""),
            ("CurrentTrackDuration", current?.duration.map(hms) ?? "0:00:00"),
            ("NextAVTransportURI", next?.uri ?? ""), ("CurrentTransportActions", transportActions),
        ]
        let event = "<Event xmlns=\"urn:schemas-upnp-org:metadata-1-0/AVT/\"><InstanceID val=\"0\">"
            + values.map { "<\($0.0) val=\"\(xmlEscape($0.1))\"/>" }.joined() + "</InstanceID></Event>"
        say("state: \(state.rawValue) \(hms(position)) \(current?.name ?? "-")\(next.map { " → next \($0.name)" } ?? "")")
        notify("AVTransport", event, only: sid)
    }

    private func emitRenderingControl(only sid: String? = nil) {
        let event = "<Event xmlns=\"urn:schemas-upnp-org:metadata-1-0/RCS/\"><InstanceID val=\"0\">"
            + "<Volume channel=\"Master\" val=\"\(volume)\"/><Mute channel=\"Master\" val=\"\(muted ? 1 : 0)\"/>"
            + "<VolumeDB channel=\"Master\" val=\"\(Int(volumeDB * 256))\"/></InstanceID></Event>"
        notify("RenderingControl", event, only: sid)
    }

    private func notify(_ service: String, _ event: String, only: String?) {
        let body = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<e:propertyset xmlns:e=\"urn:schemas-upnp-org:event-1-0\">"
            + "<e:property><LastChange>\(xmlEscape(event))</LastChange></e:property></e:propertyset>"
        for (sid, subscription) in subscriptions where subscription.service == service && (only == nil || only == sid) {
            guard subscription.expires > Date() else {
                subscriptions[sid] = nil
                say("gena: \(sid) expired")
                continue
            }
            let seq = subscription.seq
            subscriptions[sid]?.seq = seq == UInt32.max ? 1 : seq + 1
            // In order, one at a time — SEQ must arrive ascending.
            let previous = notifyChain
            notifyChain = Task.detached {
                await previous?.value
                var request = URLRequest(url: subscription.callback, timeoutInterval: 5)
                request.httpMethod = "NOTIFY"
                request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
                request.setValue("upnp:event", forHTTPHeaderField: "NT")
                request.setValue("upnp:propchange", forHTTPHeaderField: "NTS")
                request.setValue(sid, forHTTPHeaderField: "SID")
                request.setValue(String(seq), forHTTPHeaderField: "SEQ")
                request.httpBody = Data(body.utf8)
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if code != 200 { say("gena → NOTIFY \(service) SEQ=\(seq) → HTTP \(code)") }
                } catch {
                    say("gena → NOTIFY \(service) SEQ=\(seq) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func short(_ value: String) -> String {
        value.count > 120 ? String(value.prefix(120)) + "…(\(value.count))" : value
    }
}

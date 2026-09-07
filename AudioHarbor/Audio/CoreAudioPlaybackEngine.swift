import AVFoundation
import Foundation

#if os(macOS)
import CoreAudio
#endif

/// Facade: shared AVAudioEngine for compatibility, HAL exclusive/DoP on Mac.
///
/// `AVAudioEngine.connect` can raise ObjC NSExceptions (e.g. -10868) that Swift cannot catch.
/// Always connect with an explicit valid format and wrap connects via AHPerformWithExceptionHandling.
@MainActor
final class CoreAudioPlaybackEngine: PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var activeFormatLabel: String?
    private(set) var pathLabel: String = "Shared"

    private var sharedEngine = AVAudioEngine()
    private var sharedPlayer = AVAudioPlayerNode()
    private var sharedFile: AVAudioFile?

    private let halPlayer = HALAudioPlayer()
    private let deviceController = MacAudioDeviceController()
    private let effectHost: EffectHost

    private var outputMode: OutputMode = .shared
    private var dsdStrategy: DSDStrategy = .preferDoP
    private var usingHAL = false
    private var activeRender: RenderBuffer?
    private var seekOffset: TimeInterval = 0
    private var tickTimer: Timer?
    private var loadedTrack: Track?
    private var isSeeking = false
    /// Wall-clock progress for Shared mode — more reliable than playerTime alone.
    private var sharedAnchorDate: Date?
    private var sharedAnchorOffset: TimeInterval = 0
    #if os(macOS)
    private var exclusiveDeviceID: AudioDeviceID?
    #endif

    init(effectHost: EffectHost) {
        self.effectHost = effectHost
        wireSharedGraph()
        effectHost.onChainChanged = { [weak self] in
            self?.handleEffectChainChanged()
        }
        halPlayer.onReachedEnd = { [weak self] in
            Task { @MainActor in
                self?.handleEnded()
            }
        }
    }

    func setOutputMode(_ mode: OutputMode) {
        outputMode = mode
    }

    func setDSDStrategy(_ strategy: DSDStrategy) {
        dsdStrategy = strategy
    }

    func load(_ track: Track) async throws {
        stop()
        state = .loading
        loadedTrack = track

        do {
            if track.format.isDSD {
                try await loadDSD(track)
            } else if shouldUseHAL(for: track) {
                try await loadExclusivePCM(track)
            } else {
                try loadSharedPCM(track)
            }
            state = .paused
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func play() {
        if usingHAL {
            #if os(macOS)
            guard let render = activeRender else { return }
            do {
                try startExclusive(render: render)
                state = .playing
                pathLabel = render.isDoP ? "Exclusive · DoP" : "Exclusive · Bit-perfect"
                startTimer()
            } catch {
                // Never fall back into AVAudioEngine.connect with a custom format (crashes).
                releaseExclusiveSession()
                usingHAL = false
                if let track = loadedTrack, !track.format.isDSD {
                    do {
                        try loadSharedPCM(track)
                        try startSharedPlayback()
                        pathLabel = "Shared fallback"
                    } catch {
                        state = .failed(error.localizedDescription)
                    }
                } else {
                    state = .failed(
                        "Exclusive playback failed. Switch Output to Shared, or use Prefer DoP off / PCM for DSD."
                    )
                }
            }
            #else
            state = .failed("Exclusive/HAL is available on Mac only.")
            #endif
            return
        }

        do {
            try startSharedPlayback()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func pause() {
        if usingHAL {
            #if os(macOS)
            seekOffset = currentTime
            halPlayer.stopIO()
            #endif
            clearSharedAnchor()
            state = .paused
            stopTimer()
            return
        }
        captureSharedProgress()
        sharedPlayer.pause()
        seekOffset = currentTime
        clearSharedAnchor()
        state = .paused
        stopTimer()
    }

    func stop() {
        stopTimer()
        isSeeking = false
        clearSharedAnchor()
        halPlayer.stopIO()
        releaseExclusiveSession()
        stopSharedEngine()
        sharedFile = nil
        activeRender = nil
        usingHAL = false
        seekOffset = 0
        currentTime = 0
        duration = 0
        activeFormatLabel = nil
        state = .idle
    }

    func seek(to seconds: TimeInterval) {
        guard !isSeeking else { return }
        isSeeking = true
        defer { isSeeking = false }

        let clamped = max(0, min(seconds, max(duration, 0)))
        let resume = state == .playing

        seekOffset = clamped
        currentTime = clamped

        if usingHAL {
            let rate = activeRender?.sampleRate ?? 44100
            halPlayer.seek(frame: Int((clamped * rate).rounded(.down)))
            if !resume {
                state = .paused
            }
            return
        }

        sharedPlayer.stop()
        clearSharedAnchor()
        rescheduleShared()
        if resume {
            do {
                if !sharedEngine.isRunning { try sharedEngine.start() }
                sharedPlayer.play()
                armSharedAnchor(from: clamped)
                state = .playing
                startTimer()
            } catch {
                state = .failed(error.localizedDescription)
            }
        } else {
            state = .paused
        }
    }

    // MARK: - Exclusive helpers

    #if os(macOS)
    private func startExclusive(render: RenderBuffer) throws {
        halPlayer.seek(frame: Int((seekOffset * render.sampleRate).rounded(.down)))
        let device: AudioDeviceID
        if let exclusiveDeviceID {
            device = exclusiveDeviceID
        } else {
            device = try deviceController.prepareExclusive(sampleRate: render.sampleRate)
            exclusiveDeviceID = device
        }
        try halPlayer.startHAL(deviceID: device)
    }
    #endif

    private func releaseExclusiveSession() {
        #if os(macOS)
        deviceController.releaseExclusive()
        exclusiveDeviceID = nil
        #endif
    }

    // MARK: - Loaders

    private func shouldUseHAL(for track: Track) -> Bool {
        // Plugins need the Shared float graph — never hog Exclusive/DoP with inserts.
        if effectHost.hasActiveEffects || effectHost.hasChain {
            return false
        }
        #if os(macOS)
        switch outputMode {
        case .exclusive, .dop:
            return true
        case .shared:
            return false
        }
        #else
        _ = track
        return false
        #endif
    }

    private func loadSharedPCM(_ track: Track) throws {
        usingHAL = false
        activeRender = nil
        let file = try AVAudioFile(forReading: track.url)
        // Assign before rewiring so inserts negotiate against a real stream format.
        sharedFile = file
        resetSharedGraphIfNeeded()
        duration = Double(file.length) / file.processingFormat.sampleRate
        seekOffset = 0
        currentTime = 0
        activeFormatLabel = "\(track.format.rawValue) · \(Int(file.processingFormat.sampleRate)) Hz"
        pathLabel = "Shared"
    }

    private func loadExclusivePCM(_ track: Track) async throws {
        do {
            let render = try await Task.detached(priority: .userInitiated) {
                try PCMBufferLoader.loadPacked24(url: track.url)
            }.value
            usingHAL = true
            activeRender = render
            sharedFile = nil
            halPlayer.load(render)
            duration = Double(render.frameCount) / render.sampleRate
            seekOffset = 0
            currentTime = 0
            activeFormatLabel = "\(track.format.rawValue) · \(render.label)"
            pathLabel = "Exclusive"
        } catch {
            try loadSharedPCM(track)
            pathLabel = "Shared (exclusive decode fallback)"
        }
    }

    private func loadDSD(_ track: Track) async throws {
        let strategy: DSDStrategy = {
            if outputMode == .dop { return .preferDoP }
            return dsdStrategy
        }()

        #if os(macOS)
        if outputMode == .exclusive || outputMode == .dop || strategy == .preferDoP {
            let render = try await Task.detached(priority: .userInitiated) {
                try PCMBufferLoader.loadDSD(url: track.url, strategy: strategy)
            }.value
            usingHAL = true
            activeRender = render
            sharedFile = nil
            halPlayer.load(render)
            duration = Double(render.frameCount) / render.sampleRate
            seekOffset = 0
            currentTime = 0
            activeFormatLabel = "\(track.format.rawValue) · \(render.label)"
            pathLabel = render.isDoP ? "DoP" : "DSD→PCM"
            return
        }
        #endif

        // Shared / iOS: decode DSD→PCM into a temporary WAV, then use the safe AVAudioFile path.
        let render = try await Task.detached(priority: .userInitiated) {
            try PCMBufferLoader.loadDSD(url: track.url, strategy: .convertToPCM)
        }.value
        let tempURL = try Self.writeTempWAV(from: render)
        usingHAL = false
        activeRender = nil
        let file = try AVAudioFile(forReading: tempURL)
        sharedFile = file
        resetSharedGraphIfNeeded()
        duration = Double(file.length) / file.processingFormat.sampleRate
        seekOffset = 0
        currentTime = 0
        activeFormatLabel = "\(track.format.rawValue) · DSD→PCM · Shared"
        pathLabel = "Shared · DSD→PCM"
    }

    private func startSharedPlayback() throws {
        guard sharedFile != nil else {
            throw PlaybackEngineError.fileUnreadable
        }
        if !sharedEngine.isRunning {
            try sharedEngine.start()
        }
        if !sharedPlayer.isPlaying {
            rescheduleShared()
            sharedPlayer.play()
        }
        armSharedAnchor(from: seekOffset)
        state = .playing
        if effectHost.hasActiveEffects {
            pathLabel = "Shared · FX"
        } else if !pathLabel.contains("fallback") {
            pathLabel = "Shared"
        }
        startTimer()
    }

    private func wireSharedGraph() {
        sharedEngine.attach(sharedPlayer)

        let format = sharedConnectionFormat()
        let inserts = effectHost.engineNodes()
        var failedUnits: [AVAudioUnit] = []

        for unit in inserts {
            if unit.engine !== sharedEngine {
                sharedEngine.attach(unit)
            }
            if !prepareInsertFormat(unit, format: format) {
                failedUnits.append(unit)
                if unit.engine === sharedEngine {
                    sharedEngine.detach(unit)
                }
            }
        }

        // player → [compatible AU inserts…] → mainMixer
        var upstream: AVAudioNode = sharedPlayer
        for unit in inserts where !failedUnits.contains(where: { $0 === unit }) {
            var connectError: NSError?
            let ok = AHPerformWithExceptionHandling({
                self.sharedEngine.connect(upstream, to: unit, format: format)
            }, &connectError)
            if ok {
                upstream = unit
            } else {
                failedUnits.append(unit)
                if unit.engine === sharedEngine {
                    sharedEngine.detach(unit)
                }
                _ = connectError
            }
        }

        var mixerError: NSError?
        let mixerOK = AHPerformWithExceptionHandling({
            self.sharedEngine.connect(upstream, to: self.sharedEngine.mainMixerNode, format: format)
        }, &mixerError)

        if !mixerOK {
            // Last resort: bare player → mixer without inserts.
            for unit in inserts where unit.engine === sharedEngine {
                sharedEngine.detach(unit)
                if !failedUnits.contains(where: { $0 === unit }) {
                    failedUnits.append(unit)
                }
            }
            _ = AHPerformWithExceptionHandling({
                self.sharedEngine.connect(self.sharedPlayer, to: self.sharedEngine.mainMixerNode, format: format)
            }, nil)
        }

        sharedEngine.prepare()

        if !failedUnits.isEmpty {
            let names = failedUnits.map { effectHost.displayName(for: $0) }.joined(separator: ", ")
            effectHost.dropFailedUnits(
                failedUnits,
                message: "Dropped incompatible plugin(s): \(names). Many Waves AUs need a DAW host and reject Shared graph formats."
            )
        } else if effectHost.hasActiveEffects {
            pathLabel = "Shared · FX"
        }
    }

    private func sharedConnectionFormat() -> AVAudioFormat {
        if let format = sharedFile?.processingFormat,
           format.sampleRate > 0,
           format.channelCount > 0 {
            return format
        }
        let hardware = sharedEngine.outputNode.outputFormat(forBus: 0)
        if hardware.sampleRate > 0, hardware.channelCount > 0 {
            return hardware
        }
        return AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
            ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    }

    private func prepareInsertFormat(_ unit: AVAudioUnit, format: AVAudioFormat) -> Bool {
        let au = unit.auAudioUnit
        do {
            if au.inputBusses.count > 0 {
                try au.inputBusses[0].setFormat(format)
            }
            if au.outputBusses.count > 0 {
                try au.outputBusses[0].setFormat(format)
            }
            return true
        } catch {
            return false
        }
    }

    private func resetSharedGraphIfNeeded() {
        stopSharedEngine()
        detachEffectNodes()
        // Recreate engine/player after exclusive sessions — safer than reconnecting formats.
        sharedEngine = AVAudioEngine()
        sharedPlayer = AVAudioPlayerNode()
        wireSharedGraph()
    }

    private func detachEffectNodes() {
        for unit in effectHost.engineNodes() {
            unit.engine?.detach(unit)
        }
    }

    private func handleEffectChainChanged() {
        let resume = state == .playing
        let time = currentTime
        let track = loadedTrack

        // Adding FX while exclusive: tear down HAL and reload on Shared.
        if usingHAL, effectHost.hasChain {
            releaseExclusiveSession()
            usingHAL = false
            if let track {
                do {
                    try loadSharedPCM(track)
                    seek(to: time)
                    if resume { try startSharedPlayback() }
                    pathLabel = "Shared · FX"
                } catch {
                    state = .failed(error.localizedDescription)
                }
            }
            return
        }

        // Rebuild Shared graph with new insert order.
        if !usingHAL {
            stopSharedEngine()
            detachEffectNodes()
            sharedEngine = AVAudioEngine()
            sharedPlayer = AVAudioPlayerNode()
            wireSharedGraph()
            if sharedFile != nil {
                seekOffset = time
                currentTime = time
                if resume {
                    do {
                        try startSharedPlayback()
                    } catch {
                        state = .failed(error.localizedDescription)
                    }
                } else if effectHost.hasActiveEffects {
                    pathLabel = "Shared · FX"
                }
            }
        }
    }

    private func stopSharedEngine() {
        sharedPlayer.stop()
        if sharedEngine.isRunning {
            sharedEngine.stop()
        }
    }

    private func rescheduleShared() {
        guard let file = sharedFile else { return }
        let start = AVAudioFramePosition(seekOffset * file.processingFormat.sampleRate)
        let remaining = file.length - start
        guard remaining > 0 else { return }
        sharedPlayer.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(remaining), at: nil)
    }

    private func handleEnded() {
        currentTime = duration
        seekOffset = duration
        clearSharedAnchor()
        state = .paused
        stopTimer()
        halPlayer.stopIO()
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard state == .playing else { return }

        if usingHAL, let render = activeRender {
            currentTime = Double(halPlayer.currentFrame) / render.sampleRate
            if currentTime >= duration { handleEnded() }
            return
        }

        // Prefer wall-clock for Shared — playerTime is often nil early / after graph resets.
        if let anchor = sharedAnchorDate {
            currentTime = min(duration, sharedAnchorOffset + Date().timeIntervalSince(anchor))
            if currentTime >= duration {
                handleEnded()
            }
            return
        }

        if let nodeTime = sharedPlayer.lastRenderTime,
           let playerTime = sharedPlayer.playerTime(forNodeTime: nodeTime) {
            let rate = sharedFile?.processingFormat.sampleRate ?? 44100
            currentTime = seekOffset + Double(playerTime.sampleTime) / rate
            if currentTime >= duration { handleEnded() }
        }
    }

    private func armSharedAnchor(from offset: TimeInterval) {
        sharedAnchorOffset = offset
        sharedAnchorDate = Date()
    }

    private func clearSharedAnchor() {
        sharedAnchorDate = nil
    }

    private func captureSharedProgress() {
        if let anchor = sharedAnchorDate {
            currentTime = min(duration, sharedAnchorOffset + Date().timeIntervalSince(anchor))
            seekOffset = currentTime
        }
    }

    /// Minimal 16-bit WAV writer so DSD→PCM can reuse the safe AVAudioFile shared path.
    private static func writeTempWAV(from render: RenderBuffer) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audioharbor-dsd-\(UUID().uuidString).wav")

        let channels = render.channelCount
        let frames = render.frameCount
        let sampleRate = UInt32(render.sampleRate.rounded())

        var pcm16 = Data(capacity: frames * channels * 2)
        render.packed24.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let samples = frames * channels
            for i in 0..<samples {
                let o = i * 3
                guard o + 2 < bytes.count else { break }
                var v = Int32(bytes[o]) | (Int32(bytes[o + 1]) << 8) | (Int32(bytes[o + 2]) << 16)
                if v & 0x800000 != 0 { v |= ~0xFFFFFF }
                let s16 = Int16(clamping: v >> 8)
                var le = s16.littleEndian
                withUnsafeBytes(of: &le) { pcm16.append(contentsOf: $0) }
            }
        }

        let dataSize = UInt32(pcm16.count)
        var data = Data()
        func appendASCII(_ s: String) { data.append(contentsOf: s.utf8) }
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendU32(36 + dataSize)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendU32(16)
        appendU16(1)
        appendU16(UInt16(channels))
        appendU32(sampleRate)
        appendU32(sampleRate * UInt32(channels) * 2)
        appendU16(UInt16(channels * 2))
        appendU16(16)
        appendASCII("data")
        appendU32(dataSize)
        data.append(pcm16)

        try data.write(to: url, options: .atomic)
        return url
    }
}

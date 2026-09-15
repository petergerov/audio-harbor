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
    private(set) var meterLeft: Double = 0
    private(set) var meterRight: Double = 0
    /// Reports the track that reached its end, so a late signal can be matched against it.
    private var onTrackEnded: ((Track) -> Void)?

    private var sharedEngine = AVAudioEngine()
    private var sharedPlayer = AVAudioPlayerNode()
    private var sharedFile: AVAudioFile?

    private let halPlayer = HALAudioPlayer()
    private let meterProbe = StereoMeterProbe()
    private var meterTapInstalled = false
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
    private var dsdStream: DSDStreamSource?
    private var dsdPlayFrame: Int = 0
    private var dsdQueuedChunks: Int = 0
    private var dsdScheduleGeneration: UInt64 = 0
    private var sharedPCMFormat: AVAudioFormat?
    /// Wall-clock progress for Shared mode — more reliable than playerTime alone.
    private var sharedAnchorDate: Date?
    private var sharedAnchorOffset: TimeInterval = 0
    #if os(macOS)
    private var exclusiveDeviceID: AudioDeviceID?
    #endif

    init(effectHost: EffectHost) {
        self.effectHost = effectHost
        halPlayer.meterProbe = meterProbe
        wireSharedGraph()
        effectHost.onChainChanged = { [weak self] in
            self?.handleEffectChainChanged()
        }
        halPlayer.onReachedEnd = { [weak self] generation in
            Task { @MainActor in
                guard let self else { return }
                // The signal hops through the main queue — by now the next track may
                // already be loaded. Ignore anything from an earlier buffer.
                guard generation == self.halPlayer.currentGeneration else { return }
                self.handleEnded()
            }
        }
    }

    func setOutputMode(_ mode: OutputMode) {
        outputMode = mode
    }

    func setDSDStrategy(_ strategy: DSDStrategy) {
        dsdStrategy = strategy
    }

    func setTrackEndedHandler(_ handler: @escaping (Track) -> Void) {
        onTrackEnded = handler
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
                if let track = loadedTrack {
                    do {
                        if track.format.isDSD {
                            try loadDSDSharedPCM(track)
                            pathLabel = "Shared · DSD→PCM fallback"
                        } else {
                            try loadSharedPCM(track)
                            pathLabel = "Shared fallback"
                        }
                        try startSharedPlayback()
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
            zeroMeters()
            return
        }
        captureSharedProgress()
        sharedPlayer.pause()
        seekOffset = currentTime
        clearSharedAnchor()
        state = .paused
        stopTimer()
        zeroMeters()
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
        dsdStream = nil
        sharedPCMFormat = nil
        dsdPlayFrame = 0
        dsdQueuedChunks = 0
        usingHAL = false
        seekOffset = 0
        currentTime = 0
        duration = 0
        activeFormatLabel = nil
        state = .idle
        zeroMeters()
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

        dsdScheduleGeneration += 1
        dsdQueuedChunks = 0
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
        var nsError: NSError?
        var startError: Error?
        let ok = AHPerformWithExceptionHandling({
            do {
                try self.halPlayer.startHAL(deviceID: device)
            } catch {
                startError = error
            }
        }, &nsError)
        if let startError { throw startError }
        if !ok {
            throw PlaybackEngineError.notImplemented(
                nsError?.localizedDescription ?? "HAL rejected exclusive output for this device."
            )
        }
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
        dsdStream = nil
        sharedPCMFormat = nil
        dsdPlayFrame = 0
        dsdQueuedChunks = 0
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
            dsdStream = nil
            sharedPCMFormat = nil
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
        #if os(macOS)
        let wantHAL = (outputMode == .exclusive || outputMode == .dop)
            && !effectHost.hasChain
            && (outputMode == .dop || dsdStrategy == .preferDoP)
        if wantHAL {
            do {
                let source = try await Task.detached(priority: .userInitiated) {
                    try DSDPlayback.stream(for: track, strategy: .preferDoP)
                }.value
                let device = try deviceController.defaultOutputDeviceID()
                if deviceController.supportsNominalRate(source.sampleRate, device: device) {
                    usingHAL = true
                    activeRender = source.makeRenderBuffer()
                    sharedFile = nil
                    dsdStream = nil
                    sharedPCMFormat = nil
                    halPlayer.loadStream(source)
                    duration = Double(source.frameCount) / source.sampleRate
                    seekOffset = 0
                    currentTime = 0
                    activeFormatLabel = "\(track.format.rawValue) · \(source.label)"
                    pathLabel = "DoP"
                    return
                }
            } catch {
                // Fall through to Shared PCM — never crash the process on a DoP-incapable output.
            }
        }
        #endif

        let source = try await Task.detached(priority: .userInitiated) {
            try DSDPlayback.stream(for: track, strategy: .convertToPCM)
        }.value
        try installDSDShared(source, track: track)
    }

    private func loadDSDSharedPCM(_ track: Track) throws {
        let source = try DSDPlayback.stream(for: track, strategy: .convertToPCM)
        try installDSDShared(source, track: track)
    }

    private func installDSDShared(_ source: DSDStreamSource, track: Track) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: source.sampleRate,
            channels: AVAudioChannelCount(max(1, source.channelCount)),
            interleaved: false
        ) else {
            throw PlaybackEngineError.fileUnreadable
        }
        usingHAL = false
        activeRender = nil
        sharedFile = nil
        dsdStream = source
        sharedPCMFormat = format
        dsdPlayFrame = 0
        dsdQueuedChunks = 0
        resetSharedGraphIfNeeded()
        duration = Double(source.frameCount) / source.sampleRate
        seekOffset = 0
        currentTime = 0
        activeFormatLabel = "\(track.format.rawValue) · \(source.label) · Shared"
        pathLabel = "Shared · DSD→PCM"
    }

    private func startSharedPlayback() throws {
        guard sharedFile != nil || dsdStream != nil else {
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
        } else if pathLabel.contains("DSD") || pathLabel.contains("fallback") {
            // Keep the DSD / fallback caption.
        } else {
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
        installMeterTap()

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
        if let format = sharedPCMFormat,
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
                    if track.format.isDSD {
                        try loadDSDSharedPCM(track)
                    } else {
                        try loadSharedPCM(track)
                    }
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
            if sharedFile != nil || dsdStream != nil {
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
        dsdScheduleGeneration += 1
        dsdQueuedChunks = 0
        removeMeterTap()
        sharedPlayer.stop()
        if sharedEngine.isRunning {
            sharedEngine.stop()
        }
    }

    private func rescheduleShared() {
        if dsdStream != nil {
            primeDSDSchedule()
            return
        }
        guard let file = sharedFile else { return }
        let start = AVAudioFramePosition(seekOffset * file.processingFormat.sampleRate)
        let remaining = file.length - start
        guard remaining > 0 else { return }
        sharedPlayer.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(remaining), at: nil)
    }

    private func primeDSDSchedule() {
        dsdScheduleGeneration += 1
        let generation = dsdScheduleGeneration
        dsdQueuedChunks = 0
        let rate = dsdStream?.sampleRate ?? 1
        let total = dsdStream?.frameCount ?? 0
        dsdPlayFrame = min(total, max(0, Int((seekOffset * rate).rounded(.down))))
        while dsdQueuedChunks < 8 {
            guard scheduleOneDSDChunk(generation: generation) else { break }
        }
    }

    @discardableResult
    private func scheduleOneDSDChunk(generation: UInt64) -> Bool {
        guard generation == dsdScheduleGeneration,
              let source = dsdStream,
              let format = sharedPCMFormat else { return false }
        let remaining = source.frameCount - dsdPlayFrame
        guard remaining > 0 else { return false }

        let frames = min(8_192, remaining)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let planes = buffer.floatChannelData else {
            return false
        }

        let copied = source.copyFloatPlanar(
            at: dsdPlayFrame,
            count: frames,
            planes: planes,
            channelCount: Int(format.channelCount)
        )
        guard copied > 0 else { return false }
        buffer.frameLength = AVAudioFrameCount(copied)

        dsdPlayFrame += copied
        dsdQueuedChunks += 1
        sharedPlayer.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            Task { @MainActor in
                guard let self, generation == self.dsdScheduleGeneration else { return }
                self.dsdQueuedChunks = max(0, self.dsdQueuedChunks - 1)
                if self.state == .playing {
                    _ = self.scheduleOneDSDChunk(generation: generation)
                }
            }
        }
        return true
    }

    private func handleEnded() {
        guard state == .playing else { return }
        let endedTrack = loadedTrack
        currentTime = duration
        seekOffset = duration
        clearSharedAnchor()
        state = .paused
        stopTimer()
        halPlayer.stopIO()
        zeroMeters()
        // Notify last: the handler may load the next track straight away.
        if let endedTrack {
            onTrackEnded?(endedTrack)
        }
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
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
        updateMeters()

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
            let rate = sharedFile?.processingFormat.sampleRate
                ?? dsdStream?.sampleRate
                ?? 44100
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

    private func installMeterTap() {
        removeMeterTap()
        let mixer = sharedEngine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        let probe = meterProbe
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            probe.ingest(buffer)
        }
        meterTapInstalled = true
    }

    private func removeMeterTap() {
        guard meterTapInstalled else { return }
        sharedEngine.mainMixerNode.removeTap(onBus: 0)
        meterTapInstalled = false
    }

    private func updateMeters() {
        let envelope = meterProbe.takeEnvelope()
        meterLeft = Self.needleStep(meterLeft, toward: Self.vuPosition(envelope.left))
        meterRight = Self.needleStep(meterRight, toward: Self.vuPosition(envelope.right))
    }

    private func zeroMeters() {
        meterProbe.reset()
        meterLeft = 0
        meterRight = 0
    }

    /// 0 VU ≈ −18 dBFS. Scale −20…+3 dB onto 0…1.
    private static func vuPosition(_ rms: Float) -> Double {
        let db = 20.0 * log10(Double(max(rms, 1e-7)))
        return min(max((db + 20.0) / 23.0, 0), 1)
    }

    /// Extra mechanical inertia on the needle (~280 ms), same rise and fall.
    private static func needleStep(_ current: Double, toward target: Double, dt: Double = 0.05) -> Double {
        let alpha = 1 - exp(-dt / 0.28)
        return current + (target - current) * alpha
    }
}

/// Audio-thread-safe stereo RMS envelope. Analog VU: ~300 ms, not peak.
final class StereoMeterProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var vuLeft: Float = 0
    private var vuRight: Float = 0

    func ingest(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let channels = Int(buffer.format.channelCount)
        var sumL = 0.0
        var sumR = 0.0

        if let data = buffer.floatChannelData {
            for i in 0..<frames {
                let l = Double(data[0][i])
                sumL += l * l
                if channels > 1 {
                    let r = Double(data[1][i])
                    sumR += r * r
                }
            }
        } else if let data = buffer.int16ChannelData {
            for i in 0..<frames {
                let l = Double(data[0][i]) / 32768
                sumL += l * l
                if channels > 1 {
                    let r = Double(data[1][i]) / 32768
                    sumR += r * r
                }
            }
        } else {
            return
        }

        if channels < 2 { sumR = sumL }
        let n = Double(frames)
        let dt = n / max(buffer.format.sampleRate, 1)
        apply(rmsLeft: Float(sqrt(sumL / n)), rmsRight: Float(sqrt(sumR / n)), dt: dt)
    }

    func ingestPacked24(
        bytes: UnsafePointer<UInt8>,
        count: Int,
        frames: Int,
        channels: Int,
        byteOffset: Int,
        sampleRate: Double
    ) {
        guard frames > 0, channels > 0 else { return }
        var sumL = 0.0
        var sumR = 0.0
        for frame in 0..<frames {
            let base = byteOffset + frame * channels * 3
            let l = Double(Self.float24(bytes, base, count: count))
            sumL += l * l
            if channels > 1 {
                let r = Double(Self.float24(bytes, base + 3, count: count))
                sumR += r * r
            }
        }
        if channels < 2 { sumR = sumL }
        let n = Double(frames)
        apply(rmsLeft: Float(sqrt(sumL / n)), rmsRight: Float(sqrt(sumR / n)), dt: n / max(sampleRate, 1))
    }

    func takeEnvelope() -> (left: Float, right: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (vuLeft, vuRight)
    }

    func reset() {
        lock.lock()
        vuLeft = 0
        vuRight = 0
        lock.unlock()
    }

    private func apply(rmsLeft: Float, rmsRight: Float, dt: Double) {
        let alpha = Float(1 - exp(-dt / 0.300))
        lock.lock()
        vuLeft += alpha * (rmsLeft - vuLeft)
        vuRight += alpha * (rmsRight - vuRight)
        lock.unlock()
    }

    private static func float24(_ bytes: UnsafePointer<UInt8>, _ offset: Int, count: Int) -> Float {
        guard offset + 2 < count else { return 0 }
        var v = Int32(bytes[offset]) | (Int32(bytes[offset + 1]) << 8) | (Int32(bytes[offset + 2]) << 16)
        if v & 0x800000 != 0 { v |= ~0xFFFFFF }
        return Float(v) / 8_388_608
    }
}

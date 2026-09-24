import AudioToolbox
import AVFoundation
import Foundation
import os

#if os(macOS)
import CoreAudio
#endif

/// In-memory interleaved 24-bit little-endian PCM (or DoP-in-24) for HAL / engine playback.
struct RenderBuffer: Sendable {
    var sampleRate: Double
    var channelCount: Int
    var frameCount: Int
    var packed24: Data
    var label: String
    var isDoP: Bool
}

/// Plays packed 24-bit PCM through HAL Output in exclusive contexts (Mac).
/// Falls back to AVAudioEngine float path when HAL is unavailable (iOS / shared).
final class HALAudioPlayer {
    private var audioUnit: AudioUnit?
    private var buffer: RenderBuffer?
    private var framePosition: Int = 0
    private var isRunning = false
    private var didSignalEnd = false
    private var generation: UInt64 = 0
    private let lock = NSLock()

    /// Carries the load generation so the host can drop end signals from an earlier buffer.
    var onReachedEnd: ((UInt64) -> Void)?
    var meterProbe: StereoMeterProbe?
    private var dsdSource: DSDStreamSource?
    /// DSD→PCM output: decoded ahead on `prefetchQueue`; the IO thread only copies from here.
    private var pcmRing: PCMRing?
    private var prefetchTimer: DispatchSourceTimer?
    private let prefetchQueue = DispatchQueue(label: "AudioHarbor.dsd.prefetch", qos: .userInitiated)

    /// IO buffer target. The default 512 frames is ~3 ms at DoP 176.4 kHz — one late
    /// callback breaks the DoP marker run and the DAC mutes while it re-locks.
    private static let ioBufferSeconds = 0.05
    /// How far ahead of the playhead DSD pages are kept resident.
    private static let prefetchSeconds = 4.0
    /// How much decoded DSD→PCM is kept ready ahead of the playhead.
    private static let decodeAheadSeconds = 2.0
    private static let decodeChunkFrames = 4096

    deinit {
        stop()
        disposeUnit()
    }

    func load(_ buffer: RenderBuffer) {
        lock.lock()
        dsdSource = nil
        pcmRing = nil
        self.buffer = buffer
        framePosition = 0
        didSignalEnd = false
        generation &+= 1
        lock.unlock()
    }

    func loadStream(_ source: DSDStreamSource) {
        lock.lock()
        dsdSource = source
        // The lowpass decode is far too heavy for the IO thread (barely realtime in Debug).
        pcmRing = source.isDoP ? nil : PCMRing(
            capacityFrames: Int(source.sampleRate * Self.decodeAheadSeconds),
            bytesPerFrame: 3 * source.channelCount
        )
        buffer = source.makeRenderBuffer()
        framePosition = 0
        didSignalEnd = false
        generation &+= 1
        lock.unlock()
    }

    /// Generation of the buffer currently loaded.
    var currentGeneration: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    func seek(frame: Int) {
        lock.lock()
        framePosition = max(0, min(frame, buffer?.frameCount ?? 0))
        pcmRing?.reset(at: framePosition)
        didSignalEnd = false
        lock.unlock()
    }

    var currentFrame: Int {
        lock.lock(); defer { lock.unlock() }
        return framePosition
    }

    var totalFrames: Int {
        lock.lock(); defer { lock.unlock() }
        return buffer?.frameCount ?? 0
    }

    #if os(macOS)
    func startHAL(deviceID: AudioDeviceID) throws {
        // Always fully tear down previous unit first — avoids
        // "HALB_IOThread::_Start: there already is a thread".
        stop()
        disposeUnit()
        guard let buffer, buffer.frameCount > 0 else {
            throw PlaybackEngineError.fileUnreadable
        }

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw PlaybackEngineError.deviceUnavailable
        }

        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let unit else { throw PlaybackEngineError.deviceUnavailable }

        var enableIO: UInt32 = 1
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        enableIO = 0
        _ = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )

        var device = deviceID
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw PlaybackEngineError.deviceUnavailable
        }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: buffer.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
            mBytesPerPacket: UInt32(3 * buffer.channelCount),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(3 * buffer.channelCount),
            mChannelsPerFrame: UInt32(buffer.channelCount),
            mBitsPerChannel: 24,
            mReserved: 0
        )
        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw PlaybackEngineError.notImplemented(
                "HAL rejected 24-bit PCM @ \(Int(buffer.sampleRate)) Hz (OSStatus \(status))."
            )
        }

        let ref = Unmanaged.passUnretained(self).toOpaque()
        var callback = AURenderCallbackStruct(
            inputProc: { (inRefCon, _, _, _, inNumberFrames, ioData) -> OSStatus in
                let player = Unmanaged<HALAudioPlayer>.fromOpaque(inRefCon).takeUnretainedValue()
                return player.render(frames: Int(inNumberFrames), ioData: ioData)
            },
            inputProcRefCon: ref
        )
        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw PlaybackEngineError.deviceUnavailable
        }

        setIOBufferSize(unit: unit, device: deviceID, sampleRate: buffer.sampleRate)

        status = AudioUnitInitialize(unit)
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw PlaybackEngineError.deviceUnavailable
        }

        lock.lock()
        didSignalEnd = false
        lock.unlock()

        startPrefetch()

        status = AudioOutputUnitStart(unit)
        guard status == noErr else {
            stopPrefetch()
            AudioComponentInstanceDispose(unit)
            throw PlaybackEngineError.deviceUnavailable
        }

        audioUnit = unit
        isRunning = true
    }

    private func setIOBufferSize(unit: AudioUnit, device: AudioDeviceID, sampleRate: Double) {
        var frames = UInt32(sampleRate * Self.ioBufferSeconds)
        var range = AudioValueRange()
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(device, &address, 0, nil, &rangeSize, &range) == noErr, range.mMaximum > 0 {
            frames = min(max(frames, UInt32(range.mMinimum)), UInt32(range.mMaximum))
        }
        _ = AudioUnitSetProperty(
            unit,
            kAudioDevicePropertyBufferFrameSize,
            kAudioUnitScope_Global,
            0,
            &frames,
            UInt32(MemoryLayout<UInt32>.size)
        )
        var maxSlice = max(frames, 4096)
        _ = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maxSlice,
            UInt32(MemoryLayout<UInt32>.size)
        )
    }
    #endif

    func stop() {
        stopPrefetch()
        if let audioUnit {
            AudioOutputUnitStop(audioUnit)
        }
        isRunning = false
    }

    /// Keeps the mapped DSD file resident ahead of the playhead so the IO thread never waits on disk,
    /// and for DSD→PCM decodes ahead into `pcmRing`.
    private func startPrefetch() {
        stopPrefetch()
        lock.lock()
        let source = dsdSource
        let ring = pcmRing
        let position = framePosition
        lock.unlock()
        guard let source else { return }

        let ahead = Int(source.sampleRate * Self.prefetchSeconds)
        source.prefetch(from: position, count: ahead)
        if let ring {
            // Enough to start; the timer tops up the rest.
            prefetchQueue.sync {
                Self.fill(ring, from: source, limit: Int(source.sampleRate * 0.25))
            }
        }

        let timer = DispatchSource.makeTimerSource(queue: prefetchQueue)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05, leeway: .milliseconds(10))
        var lastPrefetch = DispatchTime.now()
        timer.setEventHandler { [weak self, weak source, weak ring] in
            guard let self, let source else { return }
            let playhead = self.currentFrame
            if let ring {
                Self.fill(ring, from: source, limit: nil)
            }
            if DispatchTime.now().uptimeNanoseconds - lastPrefetch.uptimeNanoseconds > 250_000_000 {
                lastPrefetch = .now()
                source.prefetch(from: playhead, count: ahead)
            }
        }
        prefetchTimer = timer
        timer.resume()
    }

    private func stopPrefetch() {
        prefetchTimer?.cancel()
        prefetchTimer = nil
    }

    /// Decode DSD→PCM into the ring until it is full (or `limit` frames were added).
    private static func fill(_ ring: PCMRing, from source: DSDStreamSource, limit: Int?) {
        var added = 0
        var scratch = [UInt8](repeating: 0, count: decodeChunkFrames * ring.bytesPerFrame)
        while true {
            let (frame, room) = ring.nextWrite()
            let count = min(decodeChunkFrames, room, source.frameCount - frame)
            guard count > 0 else { return }
            if let limit, added >= limit { return }
            scratch.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                let decoded = source.copyPacked24(at: frame, count: count, into: base)
                ring.append(at: frame, frames: decoded, from: base)
            }
            added += count
        }
    }

    /// Stop IO without disposing — used for pause / soft seek.
    func stopIO() {
        stop()
    }

    private func disposeUnit() {
        stopPrefetch()
        if let audioUnit {
            AudioOutputUnitStop(audioUnit)
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
            self.audioUnit = nil
        }
        isRunning = false
    }

    private func render(frames: Int, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let ioData else { return noErr }
        let abl = UnsafeMutableAudioBufferListPointer(ioData)
        guard let first = abl.first, let dst = first.mData else { return noErr }

        lock.lock()
        let source = dsdSource
        let ring = pcmRing
        let packed = buffer
        let position = framePosition
        lock.unlock()

        guard let packed else {
            memset(dst, 0, Int(first.mDataByteSize))
            return noErr
        }

        let bytesPerFrame = 3 * packed.channelCount
        let framesAvailable = max(0, packed.frameCount - position)
        var framesToCopy = min(frames, framesAvailable)
        let srcOffset = position * bytesPerFrame

        if let ring, framesToCopy > 0 {
            // Underrun plays silence and holds the playhead until the decoder catches up.
            framesToCopy = ring.read(at: position, count: framesToCopy, into: dst)
        } else if let source, framesToCopy > 0 {
            _ = source.copyPacked24(at: position, count: framesToCopy, into: dst)
        } else {
            let byteCount = framesToCopy * bytesPerFrame
            packed.packed24.withUnsafeBytes { raw in
                if let base = raw.baseAddress, byteCount > 0, srcOffset + byteCount <= raw.count {
                    memcpy(dst, base.advanced(by: srcOffset), byteCount)
                    if !packed.isDoP, let probe = meterProbe {
                        probe.ingestPacked24(
                            bytes: base.assumingMemoryBound(to: UInt8.self),
                            count: raw.count,
                            frames: framesToCopy,
                            channels: packed.channelCount,
                            byteOffset: srcOffset,
                            sampleRate: packed.sampleRate
                        )
                    }
                }
            }
        }

        let byteCount = framesToCopy * bytesPerFrame
        let totalBytes = Int(first.mDataByteSize)
        if byteCount < totalBytes {
            memset(dst.advanced(by: byteCount), 0, totalBytes - byteCount)
        }

        lock.lock()
        framePosition = position + framesToCopy
        let shouldSignal = framePosition >= packed.frameCount && !didSignalEnd
        if shouldSignal {
            didSignalEnd = true
        }
        let signalGeneration = generation
        lock.unlock()

        // Only notify once — otherwise this floods main at audio callback rate (~32Hz+).
        if shouldSignal {
            DispatchQueue.main.async { [weak self] in
                self?.onReachedEnd?(signalGeneration)
            }
        }
        return noErr
    }
}

/// Fixed-size ring of packed 24-bit frames addressed by absolute frame index.
/// Written by the decode queue, read by the IO thread; the lock only guards short memcpys.
final class PCMRing: @unchecked Sendable {
    let capacity: Int
    let bytesPerFrame: Int
    private let storage: UnsafeMutablePointer<UInt8>
    private let lock = OSAllocatedUnfairLock()
    /// Absolute frame index of the oldest buffered frame.
    private var start = 0
    private var count = 0

    init(capacityFrames: Int, bytesPerFrame: Int) {
        capacity = max(1, capacityFrames)
        self.bytesPerFrame = bytesPerFrame
        storage = .allocate(capacity: capacity * bytesPerFrame)
    }

    deinit {
        storage.deallocate()
    }

    /// Where the producer writes next and how much room is left.
    func nextWrite() -> (frame: Int, room: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (start + count, capacity - count)
    }

    /// Drop everything and continue from `frame` (seek). Only the seek path may call this:
    /// a playhead sampled by the producer is stale by the time it decodes.
    func reset(at frame: Int) {
        lock.lock()
        defer { lock.unlock() }
        start = frame
        count = 0
    }

    func append(at frame: Int, frames: Int, from src: UnsafeRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        // A seek reset the window while this chunk was decoding — drop it.
        guard frame == start + count else { return }
        let n = min(frames, capacity - count)
        copy(frames: n, ringFrame: frame, from: UnsafeMutablePointer(mutating: src.assumingMemoryBound(to: UInt8.self)), toRing: true)
        count += n
    }

    /// Copies up to `frames` starting at `frame`; returns how many were available.
    func read(at frame: Int, count frames: Int, into dst: UnsafeMutableRawPointer) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard frame >= start, frame < start + count else { return 0 }
        let skip = frame - start
        start = frame
        count -= skip
        let n = min(frames, count)
        copy(frames: n, ringFrame: frame, from: dst.assumingMemoryBound(to: UInt8.self), toRing: false)
        start += n
        count -= n
        return n
    }

    private func copy(frames: Int, ringFrame: Int, from external: UnsafeMutablePointer<UInt8>, toRing: Bool) {
        var done = 0
        while done < frames {
            let slot = (ringFrame + done) % capacity
            let run = min(frames - done, capacity - slot)
            let ring = storage + slot * bytesPerFrame
            let ext = external + done * bytesPerFrame
            if toRing {
                ring.update(from: ext, count: run * bytesPerFrame)
            } else {
                ext.update(from: ring, count: run * bytesPerFrame)
            }
            done += run
        }
    }
}

enum PCMBufferLoader {
    /// Decode PCM file into packed 24-bit LE interleaved samples at the file's native rate.
    /// Uses `processingFormat` (required by `AVAudioFile.read`) and reads in chunks.
    static func loadPacked24(url: URL) throws -> RenderBuffer {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channels = Int(format.channelCount)
        let totalFrames = Int(file.length)

        guard totalFrames > 0, channels > 0 else {
            throw PlaybackEngineError.fileUnreadable
        }

        var packed = Data()
        packed.reserveCapacity(totalFrames * channels * 3)

        let chunkFrames = 16_384
        var decodedFrames = 0

        while decodedFrames < totalFrames {
            let toRead = min(chunkFrames, totalFrames - decodedFrames)
            guard let chunk = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(toRead)
            ) else {
                throw PlaybackEngineError.fileUnreadable
            }

            do {
                try file.read(into: chunk, frameCount: AVAudioFrameCount(toRead))
            } catch {
                throw PlaybackEngineError.notImplemented(
                    "Audio decode failed (\(url.lastPathComponent)): \(error.localizedDescription)"
                )
            }

            let n = Int(chunk.frameLength)
            if n == 0 { break }

            appendPacked24(from: chunk, channels: channels, into: &packed)
            decodedFrames += n
        }

        guard decodedFrames > 0 else { throw PlaybackEngineError.fileUnreadable }

        let rateLabel = Int(sampleRate.rounded())
        return RenderBuffer(
            sampleRate: sampleRate,
            channelCount: channels,
            frameCount: decodedFrames,
            packed24: packed,
            label: "PCM \(rateLabel) Hz · 24-bit",
            isDoP: false
        )
    }

    static func loadDSD(url: URL, strategy: DSDStrategy) throws -> RenderBuffer {
        try DSDStreamSource(url: url, strategy: strategy).makeRenderBuffer()
    }

    private static func appendPacked24(
        from buffer: AVAudioPCMBuffer,
        channels: Int,
        into packed: inout Data
    ) {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        func appendSample(_ sample: Float) {
            let clipped = max(-1.0, min(1.0, Double(sample)))
            let intVal = Int32((clipped * Double((1 << 23) - 1)).rounded())
            packed.append(UInt8(intVal & 0xFF))
            packed.append(UInt8((intVal >> 8) & 0xFF))
            packed.append(UInt8((intVal >> 16) & 0xFF))
        }

        if let channelData = buffer.floatChannelData {
            // Typical AVAudioFile processingFormat: non-interleaved float32
            for f in 0..<frames {
                for ch in 0..<channels {
                    appendSample(channelData[ch][f])
                }
            }
            return
        }

        // Interleaved fallback via AudioBufferList
        let abl = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard let mData = abl.first?.mData else { return }
        let samples = mData.assumingMemoryBound(to: Float.self)
        for i in 0..<(frames * channels) {
            appendSample(samples[i])
        }
    }
}

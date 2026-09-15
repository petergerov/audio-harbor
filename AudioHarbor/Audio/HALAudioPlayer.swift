import AudioToolbox
import AVFoundation
import Foundation

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

    deinit {
        stop()
        disposeUnit()
    }

    func load(_ buffer: RenderBuffer) {
        lock.lock()
        dsdSource = nil
        self.buffer = buffer
        framePosition = 0
        didSignalEnd = false
        generation &+= 1
        lock.unlock()
    }

    func loadStream(_ source: DSDStreamSource) {
        lock.lock()
        dsdSource = source
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

        status = AudioUnitInitialize(unit)
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw PlaybackEngineError.deviceUnavailable
        }

        lock.lock()
        didSignalEnd = false
        lock.unlock()

        status = AudioOutputUnitStart(unit)
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw PlaybackEngineError.deviceUnavailable
        }

        audioUnit = unit
        isRunning = true
    }
    #endif

    func stop() {
        if let audioUnit {
            AudioOutputUnitStop(audioUnit)
        }
        isRunning = false
    }

    /// Stop IO without disposing — used for pause / soft seek.
    func stopIO() {
        stop()
    }

    private func disposeUnit() {
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
        let packed = buffer
        let position = framePosition
        lock.unlock()

        guard let packed else {
            memset(dst, 0, Int(first.mDataByteSize))
            return noErr
        }

        let bytesPerFrame = 3 * packed.channelCount
        let framesAvailable = max(0, packed.frameCount - position)
        let framesToCopy = min(frames, framesAvailable)
        let byteCount = framesToCopy * bytesPerFrame
        let srcOffset = position * bytesPerFrame

        if let source, framesToCopy > 0 {
            _ = source.copyPacked24(at: position, count: framesToCopy, into: dst)
        } else {
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

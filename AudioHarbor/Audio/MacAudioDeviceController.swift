import CoreAudio
import Foundation

#if os(macOS)

struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    var id: AudioDeviceID
    var name: String
    var nominalSampleRate: Double
}

/// Manages hog mode + nominal sample-rate switching for bit-perfect Mac output.
final class MacAudioDeviceController: @unchecked Sendable {
    private var hoggedDevice: AudioDeviceID?
    private var previousSampleRate: Float64?
    private let hogPID = pid_t(ProcessInfo.processInfo.processIdentifier)

    func defaultOutputDeviceID() throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw PlaybackEngineError.deviceUnavailable
        }
        return deviceID
    }

    func listOutputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs.compactMap { id in
            guard outputChannelCount(device: id) > 0 else { return nil }
            return AudioOutputDevice(
                id: id,
                name: deviceName(id) ?? "Device \(id)",
                nominalSampleRate: (try? currentSampleRate(device: id)) ?? 0
            )
        }
    }

    func prepareExclusive(sampleRate: Double, deviceID: AudioDeviceID? = nil) throws -> AudioDeviceID {
        let device = try deviceID ?? defaultOutputDeviceID()
        previousSampleRate = try? currentSampleRate(device: device)
        try setHogMode(device: device, enabled: true)
        hoggedDevice = device
        try setSampleRate(device: device, rate: sampleRate)
        return device
    }

    func releaseExclusive() {
        guard let device = hoggedDevice else { return }
        if let previousSampleRate {
            try? setSampleRate(device: device, rate: previousSampleRate)
        }
        try? setHogMode(device: device, enabled: false)
        hoggedDevice = nil
        previousSampleRate = nil
    }

    func currentSampleRate(device: AudioDeviceID) throws -> Float64 {
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate)
        guard status == noErr else { throw PlaybackEngineError.deviceUnavailable }
        return rate
    }

    private func setSampleRate(device: AudioDeviceID, rate: Float64) throws {
        var value = rate
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &value
        )
        // Some devices reject unsupported rates; surface soft failure to caller via throw.
        if status != noErr {
            throw PlaybackEngineError.notImplemented("Device rejected sample rate \(Int(rate)) Hz (OSStatus \(status)).")
        }
    }

    private func setHogMode(device: AudioDeviceID, enabled: Bool) throws {
        var pid: pid_t = enabled ? hogPID : pid_t(-1)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<pid_t>.size),
            &pid
        )
        if status != noErr && enabled {
            // Hog can fail if unsupported; still attempt rate switch without exclusive lock.
            return
        }
        _ = status
    }

    private func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.stride)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    private func outputChannelCount(device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }

        let bufferList = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

#else

final class MacAudioDeviceController: @unchecked Sendable {
    struct AudioOutputDevice: Identifiable, Hashable, Sendable {
        var id: UInt32
        var name: String
        var nominalSampleRate: Double
    }

    func defaultOutputDeviceID() throws -> UInt32 { 0 }
    func listOutputDevices() -> [AudioOutputDevice] { [] }
    func prepareExclusive(sampleRate: Double, deviceID: UInt32? = nil) throws -> UInt32 { 0 }
    func releaseExclusive() {}
    func currentSampleRate(device: UInt32) throws -> Float64 { 0 }
}

#endif

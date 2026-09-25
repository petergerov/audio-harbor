import CoreAudio
import Foundation

#if os(macOS)

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

    func listOutputDevices() -> [OutputDevice] {
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
            guard outputChannelCount(device: id) > 0, let uid = deviceUID(id) else { return nil }
            let external = isExternalInterface(device: id)
            return OutputDevice(
                uid: uid,
                name: deviceName(id) ?? "Device \(id)",
                supportsExclusive: external,
                supportsDoP: external && supportsDoP(device: id)
            )
        }
    }

    /// The live device for a stored UID, or nil while it is unplugged.
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        var cfUID = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &cfUID) { ptr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                ptr,
                &size,
                &device
            )
        }
        guard status == noErr, device != kAudioObjectUnknown, isAlive(device) else { return nil }
        return device
    }

    func deviceUID(_ id: AudioDeviceID) -> String? {
        stringProperty(kAudioDevicePropertyDeviceUID, of: id)
    }

    /// Where playback goes: the picked device while it is plugged in, otherwise the system output.
    func outputDevice(preferredUID: String?) throws -> AudioDeviceID {
        if let preferredUID, let device = deviceID(forUID: preferredUID) {
            return device
        }
        return try defaultOutputDeviceID()
    }

    func prepareExclusive(sampleRate: Double, deviceID: AudioDeviceID) throws -> AudioDeviceID {
        let device = deviceID
        previousSampleRate = try? currentSampleRate(device: device)
        try setHogMode(device: device, enabled: true)
        hoggedDevice = device
        try setSampleRate(device: device, rate: sampleRate)
        return device
    }

    /// The device exclusive playback targets: the one we hog while it is alive — macOS moves the
    /// system default elsewhere as soon as we hog it — otherwise the picked or default output.
    func exclusiveTargetDevice(preferredUID: String?) throws -> AudioDeviceID {
        if let hoggedDevice, isAlive(hoggedDevice) {
            return hoggedDevice
        }
        return try outputDevice(preferredUID: preferredUID)
    }

    /// False once the device was unplugged or reset (its ID is then stale).
    func isAlive(_ device: AudioDeviceID) -> Bool {
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive) == noErr, alive != 0 else {
            return false
        }
        return true
    }

    /// Change the rate of the hogged device, only if it differs.
    func switchExclusiveRate(to rate: Double) throws {
        guard let device = hoggedDevice else { return }
        if let current = try? currentSampleRate(device: device), abs(current - rate) < 1 {
            return
        }
        try setSampleRate(device: device, rate: rate)
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
        var status: OSStatus = noErr
        var nsError: NSError?
        let ok = AHPerformWithExceptionHandling({
            status = AudioObjectSetPropertyData(
                device,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float64>.size),
                &value
            )
        }, &nsError)
        if !ok {
            throw PlaybackEngineError.notImplemented(
                nsError?.localizedDescription ?? "Device rejected sample rate \(Int(rate)) Hz."
            )
        }
        if status != noErr {
            throw PlaybackEngineError.notImplemented("Device rejected sample rate \(Int(rate)) Hz (OSStatus \(status)).")
        }
    }

    /// Calls `handler` on the main queue when the default output or the device list changes
    /// (a DAC plugged in or out, another output picked in System Settings).
    func observeOutputChanges(_ handler: @escaping () -> Void) {
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                handler()
            }
        }
    }

    /// Exclusive and DoP are for a real external interface (USB, Thunderbolt, FireWire, PCI).
    /// Built-in speakers and headphones, virtual devices (VB-Cable, BlackHole), aggregates,
    /// Bluetooth, and AirPlay stay Shared: DoP would be noise there, and hogging them takes
    /// the volume keys away (macOS moves the default output to another device).
    func isExternalInterface(device: AudioDeviceID) -> Bool {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
            return false
        }
        switch transport {
        case kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypePCI:
            return true
        default:
            return false
        }
    }

    /// DoP carries DSD64 in 176.4 kHz PCM frames; a DAC that cannot run at that rate cannot take DoP.
    func supportsDoP(device: AudioDeviceID) -> Bool {
        supportsNominalRate(176_400, device: device)
    }

    func supportsNominalRate(_ rate: Double, device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        let raw = UnsafeMutablePointer<AudioValueRange>.allocate(capacity: count)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else {
            return false
        }
        for i in 0..<count {
            let range = raw[i]
            if rate >= range.mMinimum - 1, rate <= range.mMaximum + 1 {
                return true
            }
        }
        return false
    }

    private func setHogMode(device: AudioDeviceID, enabled: Bool) throws {
        var pid: pid_t = enabled ? hogPID : pid_t(-1)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status: OSStatus = noErr
        let ok = AHPerformWithExceptionHandling({
            status = AudioObjectSetPropertyData(
                device,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<pid_t>.size),
                &pid
            )
        }, nil)
        if status != noErr && enabled {
            // Hog can fail if unsupported; still attempt rate switch without exclusive lock.
            return
        }
        _ = (status, ok)
    }

    private func deviceName(_ id: AudioDeviceID) -> String? {
        stringProperty(kAudioObjectPropertyName, of: id)
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
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
    func defaultOutputDeviceID() throws -> UInt32 { 0 }
    func listOutputDevices() -> [OutputDevice] { [] }
    func deviceID(forUID uid: String) -> UInt32? { nil }
    func deviceUID(_ id: UInt32) -> String? { nil }
    func outputDevice(preferredUID: String?) throws -> UInt32 { 0 }
    func supportsDoP(device: UInt32) -> Bool { false }
    func prepareExclusive(sampleRate: Double, deviceID: UInt32) throws -> UInt32 { 0 }
    func releaseExclusive() {}
    func currentSampleRate(device: UInt32) throws -> Float64 { 0 }
    func supportsNominalRate(_ rate: Double, device: UInt32) -> Bool { false }
    func isExternalInterface(device: UInt32) -> Bool { false }
    func observeOutputChanges(_ handler: @escaping () -> Void) {}
    func exclusiveTargetDevice(preferredUID: String?) throws -> UInt32 { 0 }
    func isAlive(_ device: UInt32) -> Bool { false }
    func switchExclusiveRate(to rate: Double) throws {}
}

#endif

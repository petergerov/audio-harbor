import Foundation

/// Abstraction over the platform audio path.
/// Mac: Core Audio HAL exclusive / DoP.
/// iOS: AVAudioEngine with session category `.playback`.
@MainActor
protocol PlaybackEngine: AnyObject {
    var state: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var activeFormatLabel: String? { get }
    var pathLabel: String { get }
    /// VU-mapped 0…1 from the live stereo signal (0 VU ≈ −18 dBFS).
    var meterLeft: Double { get }
    var meterRight: Double { get }

    func load(_ track: Track) async throws
    func play()
    func pause()
    func stop()
    func seek(to seconds: TimeInterval)
    func setOutputMode(_ mode: OutputMode)
    /// The output to play to by UID; nil follows the system output. Stops playback on a change —
    /// the caller reloads the track so it opens the new device.
    func setOutputDevice(uid: String?)
    /// Called now and whenever outputs come and go or the active output changes.
    func setOutputStatusHandler(_ handler: @escaping (OutputStatus) -> Void)
    /// Sets the hardware volume (0…1) of the output playback goes to — the DAC when it has a
    /// volume control. The samples stay untouched.
    func setOutputVolume(_ level: Double)
    /// Called now and whenever that volume moves or the output changes; nil while the output
    /// has no volume control.
    func setOutputVolumeHandler(_ handler: @escaping (Double?) -> Void)
    /// Called once when the loaded track reaches its end (not on pause/stop/seek),
    /// with the track that ended so late signals can be matched against it.
    func setTrackEndedHandler(_ handler: @escaping (Track) -> Void)
    /// Arms the following track for gapless hand-off when the output supports it (UPnP
    /// `SetNextAVTransportURI`). No-op on Core Audio. Pass `nil` to clear.
    func prepareNext(_ track: Track?) async
    /// After track-end, takes over a previously prepared next track without reloading.
    /// Returns that track when the engine already holds it; otherwise `nil`.
    func adoptPreparedNext() -> Track?
    /// Full vs Wi‑Fi PCM for UPnP output. No-op on Core Audio.
    func setNetworkStreamQuality(_ quality: NetworkStreamQuality)
    /// Auto / PCM / DoP for DSD on a network player. No-op on Core Audio.
    func setNetworkDsdMode(_ mode: NetworkDsdMode)
    /// What a network player lists for DSD (`upnp:<UDN>`). Nil when offline or not a network UID.
    func networkPlayerFormats(uid: String) async -> NetworkPlayerFormats?
}

enum PlaybackEngineError: LocalizedError {
    case unsupportedFormat(AudioFormat)
    case fileUnreadable
    case deviceUnavailable
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "Unsupported format: \(format.rawValue)"
        case .fileUnreadable:
            "Could not read the audio file."
        case .deviceUnavailable:
            "Audio output device unavailable."
        case .notImplemented(let message):
            message
        }
    }
}

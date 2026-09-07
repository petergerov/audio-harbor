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

    func load(_ track: Track) async throws
    func play()
    func pause()
    func stop()
    func seek(to seconds: TimeInterval)
    func setOutputMode(_ mode: OutputMode)
    func setDSDStrategy(_ strategy: DSDStrategy)
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

#if os(iOS)
import AVFoundation
import MediaPlayer
import UIKit

/// Turns the iPhone's volume buttons into steps for the Mac's output volume.
///
/// iOS has no API for the buttons themselves. With an active audio session each press moves the
/// phone's own volume, which is observed here and put back to the middle right away, so the next
/// press registers in either direction and the phone's level never runs into a limit. A hidden
/// `MPVolumeView` keeps the system volume HUD away and is what puts the level back.
/// While another app plays audio on the phone, the buttons are left to that app.
@MainActor
final class VolumeButtonObserver {
    private static let anchor: Float = 0.5

    private let onStep: (Int) -> Void
    private let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
    private var observation: NSKeyValueObservation?
    /// The phone's volume before capture began, restored when it ends.
    private var levelBeforeCapture: Float?
    private var isResetting = false

    /// `onStep` gets +1 for volume up, −1 for volume down.
    init(onStep: @escaping (Int) -> Void) {
        self.onStep = onStep
        volumeView.alpha = 0.01
        volumeView.isUserInteractionEnabled = false
    }

    var isActive: Bool { observation != nil }

    func start() {
        guard observation == nil, let window = Self.keyWindow else { return }
        let session = AVAudioSession.sharedInstance()
        guard !session.isOtherAudioPlaying else { return }
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }
        window.addSubview(volumeView)
        levelBeforeCapture = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            guard let old = change.oldValue, let new = change.newValue else { return }
            Task { @MainActor in
                self?.volumeChanged(from: old, to: new)
            }
        }
        setPhoneVolume(Self.anchor)
    }

    func stop() {
        guard let observation else { return }
        observation.invalidate()
        self.observation = nil
        if let levelBeforeCapture {
            setPhoneVolume(levelBeforeCapture)
        }
        levelBeforeCapture = nil
        isResetting = false
        // Give the slider a moment to apply the restored level before the view goes.
        let view = volumeView
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            view.removeFromSuperview()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func volumeChanged(from old: Float, to new: Float) {
        guard observation != nil else { return }
        if isResetting, abs(new - Self.anchor) < 0.001 {
            isResetting = false
            return
        }
        let delta = new - old
        guard abs(delta) > 0.001 else { return }
        if AVAudioSession.sharedInstance().isOtherAudioPlaying { return }
        onStep(delta > 0 ? 1 : -1)
        setPhoneVolume(Self.anchor)
    }

    private func setPhoneVolume(_ level: Float) {
        isResetting = level == Self.anchor
        // The slider only takes a value once the view sits in a window; set it on the next turn.
        let view = volumeView
        Task { @MainActor in
            guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
            slider.value = level
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
#endif

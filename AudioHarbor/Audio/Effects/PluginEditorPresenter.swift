import Foundation

#if os(macOS)
import AppKit

/// Opens AU editor UIs in floating windows sized to the plugin's preferred content size.
///
/// AU view controllers from `requestViewController` are typically single-use / cached.
/// Closing therefore only hides the panel; Edit shows it again without requesting a new VC.
@MainActor
final class PluginEditorPresenter {
    private var controllers: [UUID: PluginEditorWindowController] = [:]
    var onEditorWillHide: (() -> Void)?

    func present(slotID: UUID, title: String, viewController: NSViewController) {
        if let existing = controllers[slotID] {
            existing.bringToFront()
            return
        }

        let controller = PluginEditorWindowController(
            slotID: slotID,
            title: title,
            pluginViewController: viewController,
            onWillHide: { [weak self] in self?.onEditorWillHide?() }
        )
        controllers[slotID] = controller
        controller.showWindow(nil)
        controller.bringToFront()
    }

    /// Whether an editor panel already exists for this slot (even if currently hidden).
    func hasEditor(for slotID: UUID) -> Bool {
        controllers[slotID] != nil
    }

    func showExisting(slotID: UUID) -> Bool {
        guard let existing = controllers[slotID] else { return false }
        existing.bringToFront()
        return true
    }

    func close(slotID: UUID) {
        controllers[slotID]?.tearDown()
        controllers.removeValue(forKey: slotID)
    }

    func closeAll() {
        controllers.values.forEach { $0.tearDown() }
        controllers.removeAll()
    }
}

private final class PluginEditorWindowController: NSWindowController, NSWindowDelegate {
    let slotID: UUID
    private var sizeObservation: NSKeyValueObservation?
    private let onWillHide: () -> Void

    init(
        slotID: UUID,
        title: String,
        pluginViewController: NSViewController,
        onWillHide: @escaping () -> Void
    ) {
        self.slotID = slotID
        self.onWillHide = onWillHide

        // Ensure the AU view is loaded before measuring.
        _ = pluginViewController.view
        let size = Self.resolvedSize(for: pluginViewController)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.contentViewController = pluginViewController
        panel.setContentSize(size)
        panel.contentMinSize = NSSize(
            width: min(320, max(200, size.width * 0.5)),
            height: min(240, max(160, size.height * 0.5))
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.center()

        super.init(window: panel)
        panel.delegate = self

        sizeObservation = pluginViewController.observe(\.preferredContentSize, options: [.new]) { [weak self] vc, _ in
            Task { @MainActor in
                self?.resizeToPluginIfNeeded(vc)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bringToFront() {
        guard let window else { return }
        window.level = .floating
        if !window.isVisible {
            window.orderFrontRegardless()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide on close-button — keep the AU view controller alive for re-open.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onWillHide()
        sender.orderOut(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.level = .floating
    }

    func tearDown() {
        sizeObservation?.invalidate()
        sizeObservation = nil
        if let window {
            window.delegate = nil
            window.contentViewController = nil
            window.orderOut(nil)
            window.close()
        }
    }

    private func resizeToPluginIfNeeded(_ vc: NSViewController) {
        guard let window else { return }
        let newSize = Self.resolvedSize(for: vc)
        let current = window.contentRect(forFrameRect: window.frame).size
        guard abs(current.width - newSize.width) > 2 || abs(current.height - newSize.height) > 2 else {
            return
        }
        window.setContentSize(newSize)
    }

    static func resolvedSize(for vc: NSViewController) -> NSSize {
        var size = vc.preferredContentSize
        if size.width < 80 || size.height < 80 {
            let fitting = vc.view.fittingSize
            if fitting.width >= 80, fitting.height >= 80 {
                size = fitting
            }
        }
        if size.width < 80 || size.height < 80 {
            let frame = vc.view.frame.size
            if frame.width >= 80, frame.height >= 80 {
                size = frame
            }
        }
        if size.width < 80 || size.height < 80 {
            size = NSSize(width: 700, height: 500)
        }
        if let screen = NSScreen.main?.visibleFrame {
            size.width = min(size.width, screen.width * 0.95)
            size.height = min(size.height, screen.height * 0.9)
        }
        return size
    }
}
#endif

import SwiftUI
#if os(iOS)
import UIKit

final class AudioHarborAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }
}
#elseif os(macOS)
import AppKit

final class AudioHarborAppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the main window so AppKit callbacks can reopen the SwiftUI `Window` scene.
    var openMainWindow: (() -> Void)?

    /// A single `Window` scene would otherwise quit the app (and stop playback) when it is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with no window open brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let openMainWindow else { return true }
        openMainWindow()
        return false
    }
}

/// Window menu item that reopens the main window after it has been closed.
private struct ShowMainWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Audio Harbor") {
            openWindow(id: "main")
        }
    }
}

/// Hands the scene's `openWindow` action to the app delegate for Dock reopen.
private struct MainWindowReopenRegistration: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AudioHarborAppDelegate

    func body(content: Content) -> some View {
        content.onAppear {
            appDelegate.openMainWindow = { openWindow(id: "main") }
        }
    }
}
#endif

@main
struct AudioHarborApp: App {
    @State private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AudioHarborAppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AudioHarborAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        // Single-window scene. SwiftUI does not list it in the Window menu, so the commands below
        // add an explicit item to reopen it after closing.
        Window("Audio Harbor", id: "main") {
            mainContent
                .modifier(MainWindowReopenRegistration(appDelegate: appDelegate))
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Music Folder…") {
                    appModel.library.addFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(before: .windowList) {
                ShowMainWindowButton()
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
            }
            CommandMenu("Catalogue") {
                Button("Rebuild Index") {
                    appModel.requestIndexRebuild()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appModel.library.isScanning || appModel.library.folders.isEmpty)
            }
            CommandMenu("Playback") {
                Button(appModel.playback.isPlaying ? "Pause" : "Play") {
                    appModel.playback.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                Button("Next") {
                    appModel.playback.playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Previous") {
                    appModel.playback.playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
            }
        }
        #else
        WindowGroup {
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #endif
    }

    private var mainContent: some View {
        RootView()
            .environment(appModel)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, phase in
                if phase == .inactive || phase == .background {
                    appModel.effects.saveSettings()
                }
            }
    }
}

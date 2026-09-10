import SwiftUI

@main
struct AudioHarborApp: App {
    @State private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .inactive || phase == .background {
                        appModel.effects.saveSettings()
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Music Folder…") {
                    appModel.library.addFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
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
        #endif
    }
}

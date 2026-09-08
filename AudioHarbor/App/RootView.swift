import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        Group {
            #if os(macOS)
            NavigationSplitView {
                HarborSidebar()
                    .navigationSplitViewColumnWidth(min: 212, ideal: 236, max: 280)
            } detail: {
                detail
            }
            #else
            TabView(selection: $appModel.selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    tabRoot(tab)
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }
            #endif
        }
        .tint(HarborColor.amber)
        .background(HarborColor.chassis.ignoresSafeArea())
        .environment(\.harborPlaying, appModel.playback.isPlaying)
    }

    @ViewBuilder
    private var detail: some View {
        switch appModel.selectedTab {
        case .library:
            LibraryView()
        case .playlists:
            PlaylistsView()
        case .nowPlaying:
            NowPlayingView()
        case .effects:
            EffectsRackView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .library:
            NavigationStack { LibraryView() }
        case .playlists:
            NavigationStack { PlaylistsView() }
        case .nowPlaying:
            NavigationStack { NowPlayingView() }
        case .effects:
            NavigationStack { EffectsRackView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }
}

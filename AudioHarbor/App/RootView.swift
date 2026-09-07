import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        Group {
            #if os(macOS)
            NavigationSplitView {
                List(AppTab.allCases, selection: $appModel.selectedTab) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(HarborColor.chassis)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        PowerLamp(isOn: appModel.playback.isPlaying)
                        BrandMark(compact: true)
                    }
                    .padding()
                }
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

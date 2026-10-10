#if os(macOS)
import AppKit
#endif
import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    let library: LibraryService
    let playback: PlaybackService
    let playlists: PlaylistService
    let effects: EffectHost
    let license: LicenseService
    /// LAN remote control (Mac engine). Created after `self` exists.
    private(set) var remote: RemoteControlService!
    #if os(macOS)
    /// The library as a UPnP / DLNA music server for players on the network; off until turned on.
    let sharing: MusicServerService
    /// Finds UPnP / DLNA renderers for the Settings output picker.
    let rendererBrowser = SSDPBrowser()
    /// Serves track files to a picked network renderer (Range / tokens).
    let mediaServer = MediaHTTPServer()
    #endif
    let remoteBrowser = RemoteBrowser()
    let remoteController = RemoteController()

    var selectedTab: AppTab = .library
    var isRebuildWarningPresented = false

    func requestIndexRebuild() {
        guard !library.isScanning, !library.folders.isEmpty else { return }
        isRebuildWarningPresented = true
    }

    /// Queue `tracks` and start at `track` (default: the first). Playing keeps the user where
    /// they are; the Deck opens when `showDeck` says so, or — left `nil` — on ⌘-click.
    func play(
        _ tracks: [Track],
        startingAt track: Track? = nil,
        from source: QueueSource,
        showDeck: Bool? = nil
    ) {
        guard let start = track ?? tracks.first else { return }
        playback.play(track: start, in: tracks, from: source)
        if showDeck ?? PlayGesture.wantsDeck {
            self.showDeck()
        }
    }

    func showDeck() {
        selectedTab = .nowPlaying
    }

    init() {
        let effects = EffectHost()
        #if os(macOS)
        let engine: any PlaybackEngine = RoutingPlaybackEngine(
            local: CoreAudioPlaybackEngine(effectHost: effects),
            network: UPnPPlaybackEngine(mediaServer: mediaServer, browser: rendererBrowser)
        )
        #else
        let engine: any PlaybackEngine = CoreAudioPlaybackEngine(effectHost: effects)
        #endif
        let license = LicenseService()
        let library = LibraryService()
        self.effects = effects
        self.library = library
        self.license = license
        let playback = PlaybackService(engine: engine, license: license)
        self.playback = playback
        let playlists = PlaylistService()
        self.playlists = playlists
        #if os(macOS)
        self.sharing = MusicServerService(library: library, playlists: playlists, license: license)
        self.rendererBrowser.onChange = { renderers in
            playback.setNetworkOutputs(renderers.map(\.asOutputDevice))
        }
        self.rendererBrowser.start()
        self.mediaServer.start()
        #endif
        self.remote = RemoteControlService(appModel: self)
        #if DEBUG && os(iOS)
        if let fixture = RemoteScreenshotFixture.fromLaunchArguments() {
            remoteBrowser.showFixture(fixture.nearbyServers)
            remoteController.showFixture(fixture)
        }
        #endif
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case library
    case playlists
    case nowPlaying
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Catalogue"
        case .playlists: "Playlists"
        case .nowPlaying: "Deck"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "rectangle.stack"
        case .playlists: "music.note.list"
        case .nowPlaying: "hifispeaker.fill"
        case .settings: "gearshape"
        }
    }
}

/// ⌘ held while clicking a play control also opens the Deck.
@MainActor
enum PlayGesture {
    static var wantsDeck: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.command)
        #else
        false
        #endif
    }
}

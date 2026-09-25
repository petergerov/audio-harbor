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

    var selectedTab: AppTab = .library
    var isRebuildWarningPresented = false

    func requestIndexRebuild() {
        guard !library.isScanning, !library.folders.isEmpty else { return }
        isRebuildWarningPresented = true
    }

    /// Queue `tracks`, start at `track` (default: the first) and switch to the Deck.
    func play(_ tracks: [Track], startingAt track: Track? = nil, from source: QueueSource) {
        guard let start = track ?? tracks.first else { return }
        playback.play(track: start, in: tracks, from: source)
        selectedTab = .nowPlaying
    }

    init() {
        let effects = EffectHost()
        let engine = CoreAudioPlaybackEngine(effectHost: effects)
        let license = LicenseService()
        self.effects = effects
        self.library = LibraryService()
        self.license = license
        self.playback = PlaybackService(engine: engine, license: license)
        self.playlists = PlaylistService()
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

import Foundation
import Observation

@Observable
@MainActor
final class AppModel {
    let library: LibraryService
    let playback: PlaybackService
    let playlists: PlaylistService
    let effects: EffectHost

    var selectedTab: AppTab = .library

    init() {
        let effects = EffectHost()
        let engine = CoreAudioPlaybackEngine(effectHost: effects)
        self.effects = effects
        self.library = LibraryService()
        self.playback = PlaybackService(engine: engine)
        self.playlists = PlaylistService()
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case library
    case playlists
    case nowPlaying
    case effects
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Catalogue"
        case .playlists: "Playlists"
        case .nowPlaying: "Deck"
        case .effects: "Rack"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "rectangle.stack"
        case .playlists: "music.note.list"
        case .nowPlaying: "hifispeaker.fill"
        case .effects: "slider.vertical.3"
        case .settings: "gearshape"
        }
    }
}

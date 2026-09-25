import Foundation

/// Every UserDefaults key the app writes, in one list so none collide or drift.
/// Changing a value orphans what users already have saved under the old key.
enum DefaultsKey {
    // Catalogue
    static let catalogueBrowseMode = "audioharbor.catalogue.browseMode"
    static let folderBookmarks = "audioharbor.library.folderBookmarks"
    static let trackLabels = "audioharbor.trackLabels"

    // Playlists
    static let playlists = "audioharbor.playlists"
    static let playlistsBrowserScope = "audioharbor.playlists.browserScope"

    // Playback
    static let outputMode = "audioharbor.outputMode"
    static let outputDevice = "audioharbor.outputDevice"
    static let outputDeviceName = "audioharbor.outputDeviceName"
    static let repeatMode = "audioharbor.repeatMode"
    static let shuffle = "audioharbor.shuffle"
    static let effectChain = "audioharbor.effectChain"

    // Deck
    static let deckStyle = "audioharbor.deckStyle"
    static let deckContextRailVisible = "audioharbor.deck.contextRailVisible"
    static let deckContextRailWidth = "audioharbor.deck.contextRailWidth"
}

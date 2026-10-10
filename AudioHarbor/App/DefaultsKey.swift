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
    static let dsdPCMLevel = "audioharbor.dsdPCMLevel"

    // Deck
    static let deckStyle = "audioharbor.deckStyle"
    static let deckContextRailVisible = "audioharbor.deck.contextRailVisible"
    static let deckContextRailWidth = "audioharbor.deck.contextRailWidth"

    // Remote
    static let remoteEnabled = "audioharbor.remote.enabled"
    static let remoteServerID = "audioharbor.remote.serverID"
    static let remotePort = "audioharbor.remote.port"

    // Sharing (the library as a UPnP / DLNA music server)
    static let sharingEnabled = "audioharbor.sharing.enabled"
    static let sharingDeviceID = "audioharbor.sharing.deviceID"
    static let sharingPort = "audioharbor.sharing.port"

    // UPnP output — HTTP media for network renderers
    static let mediaHTTPPort = "audioharbor.upnp.mediaHTTPPort"
    static let networkStreamQuality = "audioharbor.upnp.networkStreamQuality"
    /// Per-player DSD mode (`upnp:<UDN>` → `NetworkDsdMode` raw value).
    static let networkDsdModes = "audioharbor.upnp.networkDsdModes"
}

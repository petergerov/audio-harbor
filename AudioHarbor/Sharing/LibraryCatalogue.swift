#if os(macOS)
import Foundation

/// `SharedCatalogue` over the live services.
@MainActor
final class LibraryCatalogue: SharedCatalogue {
    private let library: LibraryService
    private let playlistService: PlaylistService

    init(library: LibraryService, playlists: PlaylistService) {
        self.library = library
        self.playlistService = playlists
    }

    /// The demo albums have no files behind them; nothing is shared until a directory is connected.
    private var hasMusic: Bool { !library.showsDemoLibrary }

    var albums: [Album] { hasMusic ? library.albums : [] }
    var artists: [LibraryFacet] { hasMusic ? library.artistFacets : [] }
    var labels: [LibraryFacet] { hasMusic ? library.labelFacets : [] }

    var playlists: [(id: UUID, name: String)] {
        hasMusic ? playlistService.playlists.map { ($0.id, $0.name) } : []
    }

    var folderRoots: [(id: UUID, name: String)] {
        library.remoteFolderRoots().map { ($0.bookmark.id, $0.bookmark.name) }
    }

    var revision: Int {
        (library.allTracks.count &* 31 &+ library.albums.count &* 7 &+ playlistService.playlists.count) & 0x7FFF_FFFF
    }

    func tracks(forArtist name: String) -> [Track] { library.tracks(forArtist: name) }

    func tracks(forLabel name: String) -> [Track] { library.tracks(forLabel: name) }

    func tracks(inPlaylist id: UUID) -> [Track]? {
        playlistService.playlists.first { $0.id == id }.map { playlistService.tracks(for: $0, from: library.allTracks) }
    }

    func folderListing(rootID: UUID, components: [String]) -> [FolderBrowseEntry]? {
        library.remoteFolderListing(rootID: rootID, components: components)
    }

    func track(forCataloguePath path: String) -> Track? { library.track(forCataloguePath: path) }

    func isInConnectedFolder(_ url: URL) -> Bool { library.remoteFolderLocation(of: url) != nil }
}
#endif

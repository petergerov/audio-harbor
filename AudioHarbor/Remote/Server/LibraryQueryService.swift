import Foundation

/// Builds browse/search responses from the live library without mutating UI search state.
@MainActor
enum LibraryQueryService {
    static func browse(
        _ request: BrowseRequest,
        library: LibraryService,
        playlists: PlaylistService
    ) -> (items: [BrowseItem], hasMore: Bool) {
        let offset = max(0, request.offset)
        let limit = min(max(1, request.limit), 200)

        switch request.scope {
        case .albums:
            let slice = Array(library.albums.dropFirst(offset).prefix(limit + 1))
            let hasMore = slice.count > limit
            let page = slice.prefix(limit).map { album -> BrowseItem in
                .album(
                    id: album.id,
                    title: album.title,
                    artist: album.artist,
                    trackCount: album.tracks.count,
                    artworkHash: album.artworkHash ?? album.tracks.first?.artworkHash
                )
            }
            return (Array(page), hasMore)

        case .artists:
            let facets = library.artistFacets
            let slice = Array(facets.dropFirst(offset).prefix(limit + 1))
            let hasMore = slice.count > limit
            let page = slice.prefix(limit).map { BrowseItem.artist(name: $0.name, trackCount: $0.count) }
            return (Array(page), hasMore)

        case .playlists:
            let list = playlists.playlists
            let slice = Array(list.dropFirst(offset).prefix(limit + 1))
            let hasMore = slice.count > limit
            let page = slice.prefix(limit).map { playlist -> BrowseItem in
                let count = playlists.tracks(for: playlist, from: library.allTracks).count
                return .playlist(id: playlist.id, name: playlist.name, trackCount: count)
            }
            return (Array(page), hasMore)

        case .albumTracks:
            guard let raw = request.parentID, let id = UUID(uuidString: raw),
                  let album = library.albums.first(where: { $0.id == id })
            else { return ([], false) }
            return pageTracks(album.tracks, offset: offset, limit: limit)

        case .artistTracks:
            guard let name = request.parentID else { return ([], false) }
            return pageTracks(library.tracks(forArtist: name), offset: offset, limit: limit)

        case .playlistTracks:
            guard let raw = request.parentID, let id = UUID(uuidString: raw),
                  let playlist = playlists.playlists.first(where: { $0.id == id })
            else { return ([], false) }
            let tracks = playlists.tracks(for: playlist, from: library.allTracks)
            return pageTracks(tracks, offset: offset, limit: limit)
        }
    }

    static func search(query: String, limit: Int, library: LibraryService) -> [TrackDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let cap = min(max(1, limit), 100)
        // Snapshot without mutating the UI's searchQuery.
        let previous = library.searchQuery
        library.searchQuery = trimmed
        let hits = Array(library.filteredTracks.prefix(cap)).map(TrackDTO.init(track:))
        library.searchQuery = previous
        return hits
    }

    static func resolve(
        _ selection: PlaySelection,
        library: LibraryService,
        playlists: PlaylistService
    ) -> (track: Track, queue: [Track], source: QueueSource)? {
        switch selection {
        case .album(let id):
            guard let album = library.albums.first(where: { $0.id == id }),
                  let first = album.tracks.first
            else { return nil }
            return (first, album.tracks, .album(album.title))

        case .artist(let name):
            let tracks = library.tracks(forArtist: name)
            guard let first = tracks.first else { return nil }
            return (first, tracks, .artist(name))

        case .track(let path):
            guard let track = library.track(forCataloguePath: path) else { return nil }
            if let album = library.albums.first(where: { $0.tracks.contains(where: { $0.cataloguePath == path }) }) {
                return (track, album.tracks, .album(album.title))
            }
            return (track, [track], .album(track.album))

        case .playlist(let id):
            guard let playlist = playlists.playlists.first(where: { $0.id == id }) else { return nil }
            let tracks = playlists.tracks(for: playlist, from: library.allTracks)
            guard let first = tracks.first else { return nil }
            return (first, tracks, .playlist(playlist.name))
        }
    }

    private static func pageTracks(_ tracks: [Track], offset: Int, limit: Int) -> ([BrowseItem], Bool) {
        let slice = Array(tracks.dropFirst(offset).prefix(limit + 1))
        let hasMore = slice.count > limit
        let page = slice.prefix(limit).map { BrowseItem.track(TrackDTO(track: $0)) }
        return (Array(page), hasMore)
    }
}

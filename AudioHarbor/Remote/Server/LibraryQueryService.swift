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

        case .folders:
            return browseFolders(request, library: library, offset: offset, limit: limit)
        }
    }

    private static func browseFolders(
        _ request: BrowseRequest,
        library: LibraryService,
        offset: Int,
        limit: Int
    ) -> (items: [BrowseItem], hasMore: Bool) {
        // Roots: connected directories on the Mac.
        guard let parentID = request.parentID, !parentID.isEmpty else {
            let roots = library.remoteFolderRoots()
            let slice = Array(roots.dropFirst(offset).prefix(limit + 1))
            let hasMore = slice.count > limit
            let page = slice.prefix(limit).map { root -> BrowseItem in
                .folder(
                    id: RemoteFolderRef.encode(rootID: root.bookmark.id),
                    name: root.bookmark.name,
                    childHint: root.bookmark.displayPath
                )
            }
            return (Array(page), hasMore)
        }

        guard let parsed = RemoteFolderRef.parse(parentID),
              let listing = library.remoteFolderListing(rootID: parsed.rootID, components: parsed.components)
        else { return ([], false) }

        let slice = Array(listing.dropFirst(offset).prefix(limit + 1))
        let hasMore = slice.count > limit
        let page: [BrowseItem] = slice.prefix(limit).compactMap { entry in
            switch entry.kind {
            case .directory:
                return .folder(
                    id: RemoteFolderRef.childID(parent: parentID, directoryName: entry.name),
                    name: entry.name,
                    childHint: "Folder"
                )
            case .audioFile(let track):
                return .track(TrackDTO(track: track))
            }
        }
        return (page, hasMore)
    }

    static func search(query: String, limit: Int, library: LibraryService) async -> [TrackDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let cap = min(max(1, limit), 500)

        // FTS over the whole on-disk catalogue (same index the Mac uses).
        let paths = await CatalogueIndexStore.shared.searchPaths(query: trimmed)
        if !paths.isEmpty {
            var seen = Set<String>()
            var results: [TrackDTO] = []
            results.reserveCapacity(min(cap, paths.count))
            for path in paths {
                guard seen.insert(path).inserted else { continue }
                guard let track = library.track(forCataloguePath: path) else { continue }
                results.append(TrackDTO(track: track))
                if results.count >= cap { break }
            }
            if !results.isEmpty { return results }
        }

        // Demo library / empty FTS: fall back to the in-memory catalogue index.
        return library.searchAllTracks(query: trimmed, limit: cap).map(TrackDTO.init(track:))
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

        case .folder(let id):
            guard let parsed = RemoteFolderRef.parse(id),
                  let url = library.remoteFolderURL(rootID: parsed.rootID, components: parsed.components),
                  let playback = library.directoryPlaybackQueue(at: url)
            else { return nil }
            let name = parsed.components.last
                ?? library.folders.first(where: { $0.id == parsed.rootID })?.name
                ?? url.lastPathComponent
            return (playback.track, playback.queue, .folder(name))
        }
    }

    private static func pageTracks(_ tracks: [Track], offset: Int, limit: Int) -> ([BrowseItem], Bool) {
        let slice = Array(tracks.dropFirst(offset).prefix(limit + 1))
        let hasMore = slice.count > limit
        let page = slice.prefix(limit).map { BrowseItem.track(TrackDTO(track: $0)) }
        return (Array(page), hasMore)
    }
}

import Foundation

/// Versioned envelope. `id` correlates request/response; nil for unsolicited events.
struct RemoteEnvelope<Body: Codable & Sendable>: Codable, Sendable {
    var v: Int
    var id: UInt32?
    var body: Body

    init(v: Int = RemoteProtocol.version, id: UInt32? = nil, body: Body) {
        self.v = v
        self.id = id
        self.body = body
    }
}

enum ClientMessage: Codable, Sendable, Equatable {
    case hello(clientID: UUID, name: String, platform: String, version: Int, auth: RemoteAuth)
    case subscribe(topics: [RemoteTopic])
    case transport(command: TransportCommand)
    case playSelection(selection: PlaySelection)
    case browse(request: BrowseRequest)
    case search(query: String, limit: Int)
    case artwork(hash: String, maxPixel: Int)
    /// Version 2 on: the playlists and labels for one track, answered with `trackOptions`.
    case trackOptions(cataloguePath: String)
    /// Version 2 on: also answered with `trackOptions`, as they stand after the edit.
    case editTrack(cataloguePath: String, edit: TrackEdit)
    case ping

    enum CodingKeys: String, CodingKey {
        case hello, subscribe, transport, playSelection, browse, search, artwork
        case trackOptions, editTrack, ping
    }

    enum HelloKeys: String, CodingKey {
        case clientID, name, platform, version, auth
    }

    enum SubscribeKeys: String, CodingKey { case topics }
    enum TransportKeys: String, CodingKey { case command }
    enum PlayKeys: String, CodingKey { case selection }
    enum BrowseKeys: String, CodingKey { case request }
    enum SearchKeys: String, CodingKey { case query, limit }
    enum ArtworkKeys: String, CodingKey { case hash, maxPixel }
    enum TrackOptionsKeys: String, CodingKey { case cataloguePath }
    enum EditTrackKeys: String, CodingKey { case cataloguePath, edit }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.hello) {
            let nested = try container.nestedContainer(keyedBy: HelloKeys.self, forKey: .hello)
            self = .hello(
                clientID: try nested.decode(UUID.self, forKey: .clientID),
                name: try nested.decode(String.self, forKey: .name),
                platform: try nested.decode(String.self, forKey: .platform),
                version: try nested.decode(Int.self, forKey: .version),
                auth: try nested.decode(RemoteAuth.self, forKey: .auth)
            )
            return
        }
        if container.contains(.subscribe) {
            let nested = try container.nestedContainer(keyedBy: SubscribeKeys.self, forKey: .subscribe)
            self = .subscribe(topics: try nested.decode([RemoteTopic].self, forKey: .topics))
            return
        }
        if container.contains(.transport) {
            let nested = try container.nestedContainer(keyedBy: TransportKeys.self, forKey: .transport)
            self = .transport(command: try nested.decode(TransportCommand.self, forKey: .command))
            return
        }
        if container.contains(.playSelection) {
            let nested = try container.nestedContainer(keyedBy: PlayKeys.self, forKey: .playSelection)
            self = .playSelection(selection: try nested.decode(PlaySelection.self, forKey: .selection))
            return
        }
        if container.contains(.browse) {
            let nested = try container.nestedContainer(keyedBy: BrowseKeys.self, forKey: .browse)
            self = .browse(request: try nested.decode(BrowseRequest.self, forKey: .request))
            return
        }
        if container.contains(.search) {
            let nested = try container.nestedContainer(keyedBy: SearchKeys.self, forKey: .search)
            self = .search(
                query: try nested.decode(String.self, forKey: .query),
                limit: try nested.decode(Int.self, forKey: .limit)
            )
            return
        }
        if container.contains(.artwork) {
            let nested = try container.nestedContainer(keyedBy: ArtworkKeys.self, forKey: .artwork)
            self = .artwork(
                hash: try nested.decode(String.self, forKey: .hash),
                maxPixel: try nested.decode(Int.self, forKey: .maxPixel)
            )
            return
        }
        if container.contains(.trackOptions) {
            let nested = try container.nestedContainer(keyedBy: TrackOptionsKeys.self, forKey: .trackOptions)
            self = .trackOptions(cataloguePath: try nested.decode(String.self, forKey: .cataloguePath))
            return
        }
        if container.contains(.editTrack) {
            let nested = try container.nestedContainer(keyedBy: EditTrackKeys.self, forKey: .editTrack)
            self = .editTrack(
                cataloguePath: try nested.decode(String.self, forKey: .cataloguePath),
                edit: try nested.decode(TrackEdit.self, forKey: .edit)
            )
            return
        }
        if container.contains(.ping) {
            self = .ping
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown ClientMessage")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hello(clientID, name, platform, version, auth):
            var nested = container.nestedContainer(keyedBy: HelloKeys.self, forKey: .hello)
            try nested.encode(clientID, forKey: .clientID)
            try nested.encode(name, forKey: .name)
            try nested.encode(platform, forKey: .platform)
            try nested.encode(version, forKey: .version)
            try nested.encode(auth, forKey: .auth)
        case .subscribe(let topics):
            var nested = container.nestedContainer(keyedBy: SubscribeKeys.self, forKey: .subscribe)
            try nested.encode(topics, forKey: .topics)
        case .transport(let command):
            var nested = container.nestedContainer(keyedBy: TransportKeys.self, forKey: .transport)
            try nested.encode(command, forKey: .command)
        case .playSelection(let selection):
            var nested = container.nestedContainer(keyedBy: PlayKeys.self, forKey: .playSelection)
            try nested.encode(selection, forKey: .selection)
        case .browse(let request):
            var nested = container.nestedContainer(keyedBy: BrowseKeys.self, forKey: .browse)
            try nested.encode(request, forKey: .request)
        case let .search(query, limit):
            var nested = container.nestedContainer(keyedBy: SearchKeys.self, forKey: .search)
            try nested.encode(query, forKey: .query)
            try nested.encode(limit, forKey: .limit)
        case let .artwork(hash, maxPixel):
            var nested = container.nestedContainer(keyedBy: ArtworkKeys.self, forKey: .artwork)
            try nested.encode(hash, forKey: .hash)
            try nested.encode(maxPixel, forKey: .maxPixel)
        case .trackOptions(let cataloguePath):
            var nested = container.nestedContainer(keyedBy: TrackOptionsKeys.self, forKey: .trackOptions)
            try nested.encode(cataloguePath, forKey: .cataloguePath)
        case let .editTrack(cataloguePath, edit):
            var nested = container.nestedContainer(keyedBy: EditTrackKeys.self, forKey: .editTrack)
            try nested.encode(cataloguePath, forKey: .cataloguePath)
            try nested.encode(edit, forKey: .edit)
        case .ping:
            try container.encode(true, forKey: .ping)
        }
    }
}

enum ServerMessage: Codable, Sendable, Equatable {
    case hello(serverName: String, version: Int, capabilities: [RemoteCapability], serverID: UUID)
    case paired(token: Data)
    case nowPlaying(snapshot: NowPlayingSnapshot)
    case queue(snapshot: QueueSnapshot)
    case browseResult(items: [BrowseItem], hasMore: Bool)
    case searchResult(tracks: [TrackDTO])
    /// Followed immediately by a binary frame of JPEG/PNG bytes.
    case artworkHeader(hash: String, byteCount: Int)
    case trackOptions(options: TrackOptionsDTO)
    case error(code: RemoteErrorCode, message: String)
    case pong

    enum CodingKeys: String, CodingKey {
        case hello, paired, nowPlaying, queue, browseResult, searchResult, artworkHeader
        case trackOptions, error, pong
    }

    enum HelloKeys: String, CodingKey {
        case serverName, version, capabilities, serverID
    }

    enum PairedKeys: String, CodingKey { case token }
    enum NowPlayingKeys: String, CodingKey { case snapshot }
    enum QueueKeys: String, CodingKey { case snapshot }
    enum BrowseResultKeys: String, CodingKey { case items, hasMore }
    enum SearchResultKeys: String, CodingKey { case tracks }
    enum ArtworkHeaderKeys: String, CodingKey { case hash, byteCount }
    enum TrackOptionsKeys: String, CodingKey { case options }
    enum ErrorKeys: String, CodingKey { case code, message }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.hello) {
            let nested = try container.nestedContainer(keyedBy: HelloKeys.self, forKey: .hello)
            self = .hello(
                serverName: try nested.decode(String.self, forKey: .serverName),
                version: try nested.decode(Int.self, forKey: .version),
                capabilities: try nested.decode([RemoteCapability].self, forKey: .capabilities),
                serverID: try nested.decode(UUID.self, forKey: .serverID)
            )
            return
        }
        if container.contains(.paired) {
            let nested = try container.nestedContainer(keyedBy: PairedKeys.self, forKey: .paired)
            self = .paired(token: try nested.decode(Data.self, forKey: .token))
            return
        }
        if container.contains(.nowPlaying) {
            let nested = try container.nestedContainer(keyedBy: NowPlayingKeys.self, forKey: .nowPlaying)
            self = .nowPlaying(snapshot: try nested.decode(NowPlayingSnapshot.self, forKey: .snapshot))
            return
        }
        if container.contains(.queue) {
            let nested = try container.nestedContainer(keyedBy: QueueKeys.self, forKey: .queue)
            self = .queue(snapshot: try nested.decode(QueueSnapshot.self, forKey: .snapshot))
            return
        }
        if container.contains(.browseResult) {
            let nested = try container.nestedContainer(keyedBy: BrowseResultKeys.self, forKey: .browseResult)
            self = .browseResult(
                items: try nested.decode([BrowseItem].self, forKey: .items),
                hasMore: try nested.decode(Bool.self, forKey: .hasMore)
            )
            return
        }
        if container.contains(.searchResult) {
            let nested = try container.nestedContainer(keyedBy: SearchResultKeys.self, forKey: .searchResult)
            self = .searchResult(tracks: try nested.decode([TrackDTO].self, forKey: .tracks))
            return
        }
        if container.contains(.artworkHeader) {
            let nested = try container.nestedContainer(keyedBy: ArtworkHeaderKeys.self, forKey: .artworkHeader)
            self = .artworkHeader(
                hash: try nested.decode(String.self, forKey: .hash),
                byteCount: try nested.decode(Int.self, forKey: .byteCount)
            )
            return
        }
        if container.contains(.trackOptions) {
            let nested = try container.nestedContainer(keyedBy: TrackOptionsKeys.self, forKey: .trackOptions)
            self = .trackOptions(options: try nested.decode(TrackOptionsDTO.self, forKey: .options))
            return
        }
        if container.contains(.error) {
            let nested = try container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
            self = .error(
                code: try nested.decode(RemoteErrorCode.self, forKey: .code),
                message: try nested.decode(String.self, forKey: .message)
            )
            return
        }
        if container.contains(.pong) {
            self = .pong
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown ServerMessage")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hello(serverName, version, capabilities, serverID):
            var nested = container.nestedContainer(keyedBy: HelloKeys.self, forKey: .hello)
            try nested.encode(serverName, forKey: .serverName)
            try nested.encode(version, forKey: .version)
            try nested.encode(capabilities, forKey: .capabilities)
            try nested.encode(serverID, forKey: .serverID)
        case .paired(let token):
            var nested = container.nestedContainer(keyedBy: PairedKeys.self, forKey: .paired)
            try nested.encode(token, forKey: .token)
        case .nowPlaying(let snapshot):
            var nested = container.nestedContainer(keyedBy: NowPlayingKeys.self, forKey: .nowPlaying)
            try nested.encode(snapshot, forKey: .snapshot)
        case .queue(let snapshot):
            var nested = container.nestedContainer(keyedBy: QueueKeys.self, forKey: .queue)
            try nested.encode(snapshot, forKey: .snapshot)
        case let .browseResult(items, hasMore):
            var nested = container.nestedContainer(keyedBy: BrowseResultKeys.self, forKey: .browseResult)
            try nested.encode(items, forKey: .items)
            try nested.encode(hasMore, forKey: .hasMore)
        case .searchResult(let tracks):
            var nested = container.nestedContainer(keyedBy: SearchResultKeys.self, forKey: .searchResult)
            try nested.encode(tracks, forKey: .tracks)
        case let .artworkHeader(hash, byteCount):
            var nested = container.nestedContainer(keyedBy: ArtworkHeaderKeys.self, forKey: .artworkHeader)
            try nested.encode(hash, forKey: .hash)
            try nested.encode(byteCount, forKey: .byteCount)
        case .trackOptions(let options):
            var nested = container.nestedContainer(keyedBy: TrackOptionsKeys.self, forKey: .trackOptions)
            try nested.encode(options, forKey: .options)
        case let .error(code, message):
            var nested = container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
            try nested.encode(code, forKey: .code)
            try nested.encode(message, forKey: .message)
        case .pong:
            try container.encode(true, forKey: .pong)
        }
    }
}

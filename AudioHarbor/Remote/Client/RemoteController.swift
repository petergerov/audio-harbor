#if os(iOS)
import UIKit
#endif
import Foundation
import Network
import Observation

enum RemoteControllerPhase: Equatable, Sendable {
    case idle
    case connecting
    case needsPairing
    case connected
    case failed(String)
}

/// Client-side remote controller: connects, pairs, mirrors Now Playing, sends transport commands.
@Observable
@MainActor
final class RemoteController {
    private(set) var phase: RemoteControllerPhase = .idle {
        didSet { updateVolumeButtons() }
    }
    private(set) var statusText = "Not connected"
    private(set) var serverName: String?
    private(set) var serverID: UUID?
    private(set) var capabilities: [RemoteCapability] = []
    private(set) var serverVersion = 0
    private(set) var nowPlaying: NowPlayingSnapshot? {
        didSet {
            if (oldValue?.outputVolume == nil) != (nowPlaying?.outputVolume == nil) {
                updateVolumeButtons()
            }
        }
    }
    private(set) var queue: QueueSnapshot?
    private(set) var searchResults: [TrackDTO] = []
    private(set) var browseItems: [BrowseItem] = []
    private(set) var browseHasMore = false
    private(set) var artworkByHash: [String: Data] = [:]
    /// Playlists and labels for the track last asked about.
    private(set) var trackOptions: TrackOptionsDTO?
    /// Mac Settings (protocol 3+).
    private(set) var settings: SettingsSnapshot?

    var pairingCodeInput = ""

    private let clientID = RemoteClientStore.clientID()
    private var connection: RemoteClientConnection?
    private var listenTask: Task<Void, Never>?
    private var requestCounter: UInt32 = 0
    private var didAuthenticate = false
    private var browseAppend = false
    private var lastBrowseRequest: BrowseRequest?

    /// Size of one volume-button press on the Mac's output.
    static let volumeStep = 0.05
    /// The level last asked for — shown and stepped from until the Mac's report catches up.
    private var requestedVolume: Double?
    private var requestedVolumeAt = Date.distantPast
    /// False while the app is in the background; the buttons then belong to the phone again.
    var isInForeground = true {
        didSet { updateVolumeButtons() }
    }
    #if DEBUG && os(iOS)
    /// Screenshot mode (`-remoteScreenshot <scene>`): fixture data instead of a Mac.
    @ObservationIgnored private var fixture: RemoteScreenshotFixture?
    private(set) var fixturePane: String?
    private(set) var fixtureSearchText: String?
    private(set) var fixtureShowQueue = false
    #endif
    #if os(iOS)
    @ObservationIgnored
    private lazy var volumeButtons = VolumeButtonObserver { [weak self] direction in
        self?.stepVolume(by: Double(direction) * Self.volumeStep)
    }
    #endif

    var displayedPosition: TimeInterval {
        guard let snap = nowPlaying else { return 0 }
        guard snap.rate > 0 else { return snap.position }
        let elapsed = Date().timeIntervalSince(snap.positionTimestamp)
        return min(snap.duration, max(0, snap.position + elapsed * snap.rate))
    }

    /// Macs on protocol version 2 and later take playlist and label edits.
    var canEditTracks: Bool {
        phase == .connected && serverVersion >= RemoteProtocol.trackEditsVersion
    }

    /// Macs on protocol version 2 and later filter Browse by a search query.
    var canSearchBrowse: Bool {
        phase == .connected && serverVersion >= RemoteProtocol.browseSearchVersion
    }

    /// Macs on protocol version 3 and later expose Settings.
    var canEditSettings: Bool {
        phase == .connected && serverVersion >= RemoteProtocol.settingsVersion
    }

    var isPlaying: Bool {
        nowPlaying?.state == "playing"
    }

    /// Hardware volume of the Mac's output, 0…1; nil when that output has no volume control.
    var outputVolume: Double? {
        guard let reported = nowPlaying?.outputVolume else { return nil }
        if let requestedVolume, Date().timeIntervalSince(requestedVolumeAt) < 1.5 {
            return requestedVolume
        }
        return reported
    }

    func setVolume(_ level: Double) {
        guard nowPlaying?.outputVolume != nil else { return }
        let clamped = min(1, max(0, level))
        if let requestedVolume, abs(requestedVolume - clamped) < 0.005,
           Date().timeIntervalSince(requestedVolumeAt) < 1.5 {
            return
        }
        requestedVolume = clamped
        requestedVolumeAt = Date()
        sendTransport(.setVolume(level: clamped))
    }

    func stepVolume(by delta: Double) {
        guard let current = outputVolume else { return }
        setVolume(current + delta)
    }

    func connect(to server: RemoteServerEndpoint, pairingCode: String? = nil) {
        disconnect()
        phase = .connecting
        statusText = "Connecting to \(server.name)…"
        serverName = server.name
        serverID = server.serverID
        didAuthenticate = false

        let connection = RemoteClientConnection(endpoint: server.endpoint)
        self.connection = connection

        let code = pairingCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredAuth: RemoteAuth? = {
            if let code, !code.isEmpty { return .pairingCode(code) }
            if let id = server.serverID, let token = RemoteClientStore.token(forServerID: id) {
                return .token(token)
            }
            if let match = RemoteClientStore.tokenMatching(serverName: server.name) {
                serverID = match.serverID
                return .token(match.token)
            }
            return nil
        }()

        listenTask = Task { [weak self] in
            do {
                try await connection.start()
                await self?.runReceiveLoop(connection: connection, preferredAuth: preferredAuth)
            } catch is CancellationError {
                // intentional disconnect
            } catch {
                await MainActor.run {
                    guard let self, self.phase != .idle else { return }
                    let message = error is NWError
                        ? "Can't reach \(server.name). Check that both are on the same network and that the Mac's firewall lets Audio Harbor accept incoming connections."
                        : error.localizedDescription
                    self.phase = .failed(message)
                    self.statusText = message
                }
            }
        }
    }

    func submitPairingCode() {
        let code = pairingCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, let connection, let serverID else { return }
        statusText = "Pairing…"
        Task {
            await sendHello(connection: connection, auth: .pairingCode(code), serverID: serverID)
        }
    }

    func disconnect() {
        listenTask?.cancel()
        listenTask = nil
        let conn = connection
        connection = nil
        Task { await conn?.cancel() }
        phase = .idle
        statusText = "Not connected"
        nowPlaying = nil
        queue = nil
        searchResults = []
        browseItems = []
        browseHasMore = false
        lastBrowseRequest = nil
        trackOptions = nil
        settings = nil
        serverVersion = 0
        didAuthenticate = false
    }

    func togglePlayPause() {
        sendTransport(.playPause)
        // Flip locally so a second tap before the Mac's snapshot arrives still resumes / pauses.
        applyOptimisticPlayPause()
    }
    func next() { sendTransport(.next) }
    func previous() { sendTransport(.previous) }
    func seek(to seconds: TimeInterval) { sendTransport(.seek(seconds: seconds)) }
    func playQueueIndex(_ index: Int) { sendTransport(.playQueueIndex(index: index)) }
    func toggleShuffle() {
        sendTransport(.setShuffle(on: !(nowPlaying?.isShuffled ?? false)))
    }
    func cycleRepeatMode() {
        let current = RepeatMode(rawValue: nowPlaying?.repeatMode ?? "") ?? .off
        sendTransport(.setRepeat(mode: current.cycled.rawValue))
    }
    /// Path of the last play request — used so a second tap can pause before the Mac snapshot arrives.
    private var armedPlayPath: String?

    func play(cataloguePath: String) {
        armedPlayPath = cataloguePath
        send(.playSelection(selection: .track(cataloguePath: cataloguePath)))
    }

    /// Catalogue / queue rows: first tap plays, tap again pauses, tap again resumes.
    /// Always sends `playSelection` for a track row when not clearly current-and-paused/playing
    /// via transport — the Mac's `PlaybackService.play` toggles when the path matches.
    func playOrToggle(cataloguePath: String) {
        if shouldToggle(cataloguePath: cataloguePath) {
            togglePlayPause()
            return
        }
        play(cataloguePath: cataloguePath)
    }

    func playOrToggleQueueIndex(_ index: Int) {
        if let queue, queue.tracks.indices.contains(index) {
            let path = queue.tracks[index].cataloguePath
            if queue.index == index || shouldToggle(cataloguePath: path) {
                togglePlayPause()
                return
            }
        }
        playQueueIndex(index)
    }

    private func shouldToggle(cataloguePath: String) -> Bool {
        if nowPlaying?.track?.cataloguePath == cataloguePath {
            return true
        }
        // Snapshot not updated yet, but we already asked to play this path.
        if armedPlayPath == cataloguePath {
            let state = nowPlaying?.state
            return state == nil || state == "loading" || state == "playing" || state == "paused"
        }
        return false
    }

    private func applyOptimisticPlayPause() {
        guard var snap = nowPlaying else { return }
        let playing = snap.state == "playing" || snap.state == "loading"
        snap.state = playing ? "paused" : "playing"
        snap.rate = playing ? 0 : 1
        snap.positionTimestamp = Date()
        nowPlaying = snap
    }
    func play(albumID: UUID) {
        send(.playSelection(selection: .album(id: albumID)))
    }
    func play(playlistID: UUID) {
        send(.playSelection(selection: .playlist(id: playlistID)))
    }

    func playArtist(name: String) {
        send(.playSelection(selection: .artist(name: name)))
    }

    func playFolder(id: String) {
        send(.playSelection(selection: .folder(id: id)))
    }

    func search(_ query: String) {
        #if DEBUG && os(iOS)
        if fixture != nil { return }
        #endif
        send(.search(query: query, limit: 200))
    }

    func browse(
        scope: BrowseScope,
        parentID: String? = nil,
        query: String? = nil,
        offset: Int = 0,
        append: Bool = false
    ) {
        browseAppend = append
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = BrowseRequest(
            scope: scope,
            parentID: parentID,
            offset: offset,
            limit: 50,
            query: trimmed?.isEmpty == false ? trimmed : nil
        )
        lastBrowseRequest = request
        #if DEBUG && os(iOS)
        if let fixture {
            browseItems = fixture.browseItems(scope: scope, parentID: parentID)
            browseHasMore = false
            return
        }
        #endif
        if !append {
            browseItems = []
            browseHasMore = false
        }
        send(.browse(request: request))
    }

    func loadMoreBrowse() {
        guard browseHasMore, let last = lastBrowseRequest else { return }
        browse(
            scope: last.scope,
            parentID: last.parentID,
            query: last.query,
            offset: last.offset + last.limit,
            append: true
        )
    }

    func loadTrackOptions(cataloguePath: String) {
        if trackOptions?.cataloguePath != cataloguePath {
            trackOptions = nil
        }
        send(.trackOptions(cataloguePath: cataloguePath))
    }

    /// The Mac answers with the track's playlists and labels as they stand after the edit.
    func editTrack(cataloguePath: String, _ edit: TrackEdit) {
        send(.editTrack(cataloguePath: cataloguePath, edit: edit))
        // Playlist rows carry track counts; reload them behind the edit.
        switch edit {
        case .addToPlaylist, .removeFromPlaylist, .addToNewPlaylist:
            if let last = lastBrowseRequest, last.scope == .playlists || last.scope == .playlistTracks {
                browse(scope: last.scope, parentID: last.parentID, query: last.query)
            }
        case .addLabel, .removeLabel:
            break
        }
    }

    func clearSearch() {
        searchResults = []
    }

    func requestArtwork(hash: String, maxPixel: Int = 512) {
        guard artworkByHash[hash] == nil else { return }
        send(.artwork(hash: hash, maxPixel: maxPixel))
    }

    func refreshSettings() {
        guard canEditSettings else { return }
        send(.getSettings)
    }

    func applySettings(_ patch: SettingsPatch) {
        guard canEditSettings else { return }
        send(.setSettings(patch: patch))
    }

    #if DEBUG && os(iOS)
    func showFixture(_ fixture: RemoteScreenshotFixture) {
        self.fixture = fixture
        serverName = RemoteScreenshotFixture.serverName
        artworkByHash = fixture.artwork()
        switch fixture.scene {
        case .nearby:
            break
        case .pairing:
            pairingCodeInput = fixture.pairingCode
            statusText = "Enter the pairing code from the Mac"
            phase = .needsPairing
        case .now, .browse, .queue:
            nowPlaying = fixture.nowPlaying
            queue = fixture.queue
            searchResults = fixture.searchResults
            fixturePane = fixture.pane
            fixtureSearchText = fixture.searchQuery
            fixtureShowQueue = fixture.showQueue
            statusText = "Connected to \(RemoteScreenshotFixture.serverName)"
            phase = .connected
        }
    }
    #endif

    // MARK: - Receive

    private func runReceiveLoop(connection: RemoteClientConnection, preferredAuth: RemoteAuth?) async {
        var expectingArtworkHash: String?
        var expectingArtworkBytes = 0

        for await frame in await connection.frames {
            if Task.isCancelled { break }

            switch frame.kind {
            case .binary:
                if let hash = expectingArtworkHash {
                    artworkByHash[hash] = frame.payload
                    _ = expectingArtworkBytes
                }
                expectingArtworkHash = nil
                expectingArtworkBytes = 0

            case .json:
                do {
                    let envelope = try FrameCodec.decodeJSON(
                        RemoteEnvelope<ServerMessage>.self,
                        from: frame.payload
                    )
                    if case let .artworkHeader(hash, byteCount) = envelope.body {
                        expectingArtworkHash = hash
                        expectingArtworkBytes = byteCount
                    } else {
                        await handle(envelope.body, preferredAuth: preferredAuth, connection: connection)
                    }
                } catch {
                    phase = .failed(error.localizedDescription)
                    statusText = error.localizedDescription
                }
            }
        }

        if phase == .connected || phase == .needsPairing || phase == .connecting {
            phase = .failed("Disconnected")
            statusText = "Disconnected"
        }
    }

    private func handle(
        _ message: ServerMessage,
        preferredAuth: RemoteAuth?,
        connection: RemoteClientConnection
    ) async {
        switch message {
        case let .hello(name, version, capabilities, serverID):
            serverName = name
            self.serverID = serverID
            self.capabilities = capabilities
            serverVersion = version
            guard version >= RemoteProtocol.minimumSupported else {
                phase = .failed("Unsupported protocol \(version)")
                statusText = "Unsupported protocol \(version)"
                return
            }

            if let preferredAuth {
                statusText = "Authenticating…"
                await sendHello(connection: connection, auth: preferredAuth, serverID: serverID)
                // Wait for `.paired` before subscribing — do not assume token success.
            } else if let token = RemoteClientStore.token(forServerID: serverID) {
                statusText = "Authenticating…"
                await sendHello(connection: connection, auth: .token(token), serverID: serverID)
            } else if let match = RemoteClientStore.tokenMatching(serverName: name) {
                self.serverID = match.serverID
                statusText = "Authenticating…"
                await sendHello(connection: connection, auth: .token(match.token), serverID: match.serverID)
            } else {
                phase = .needsPairing
                statusText = "Enter the pairing code from the Mac"
            }

        case .paired(let token):
            if let serverID {
                RemoteClientStore.storeToken(token, serverID: serverID, serverName: serverName ?? "Audio Harbor")
            }
            pairingCodeInput = ""
            await finishAuthenticated(connection: connection)

        case .nowPlaying(let snapshot):
            nowPlaying = snapshot
            if let path = snapshot.track?.cataloguePath {
                armedPlayPath = path
            }
            if let hash = snapshot.track?.artworkHash {
                requestArtwork(hash: hash)
            }

        case .queue(let snapshot):
            queue = snapshot

        case .searchResult(let tracks):
            searchResults = tracks

        case .trackOptions(let options):
            trackOptions = options

        case .settings(let snapshot):
            settings = snapshot

        case .browseResult(let items, let hasMore):
            if browseAppend {
                browseItems.append(contentsOf: items)
            } else {
                browseItems = items
            }
            browseHasMore = hasMore
            browseAppend = false
            for item in items {
                if case let .album(_, _, _, _, hash) = item, let hash {
                    requestArtwork(hash: hash, maxPixel: 128)
                }
            }

        case .error(let code, let message):
            if code == .unauthorized {
                // Only drop the stored token when the hello auth itself was rejected.
                if message.localizedCaseInsensitiveContains("token")
                    || message.localizedCaseInsensitiveContains("pairing code")
                {
                    if let serverID { RemoteClientStore.forget(serverID: serverID) }
                }
                didAuthenticate = false
                phase = .needsPairing
                statusText = message
            } else {
                statusText = message
                if phase == .connecting {
                    phase = .failed(message)
                }
            }

        case .pong, .artworkHeader:
            break
        }
    }

    private func sendHello(connection: RemoteClientConnection, auth: RemoteAuth, serverID: UUID) async {
        self.serverID = serverID
        #if os(macOS)
        let platform = "macOS"
        let name = Host.current().localizedName ?? "Remote"
        #else
        let platform = "iOS"
        let name = UIDevice.current.name
        #endif
        await send(
            .hello(
                clientID: clientID,
                name: name,
                platform: platform,
                version: RemoteProtocol.version,
                auth: auth
            ),
            on: connection
        )
    }

    private func finishAuthenticated(connection: RemoteClientConnection) async {
        guard !didAuthenticate else { return }
        didAuthenticate = true
        phase = .connected
        statusText = "Connected to \(serverName ?? "Audio Harbor")"
        var topics: [RemoteTopic] = [.nowPlaying, .queue]
        if serverVersion >= RemoteProtocol.settingsVersion {
            topics.append(.settings)
        }
        await send(.subscribe(topics: topics), on: connection)
        if serverVersion >= RemoteProtocol.settingsVersion {
            await send(.getSettings, on: connection)
        }
    }

    /// The phone's volume buttons steer the Mac while connected to an output with a volume control.
    private func updateVolumeButtons() {
        #if DEBUG && os(iOS)
        if fixture != nil { return }
        #endif
        #if os(iOS)
        let wanted = isInForeground && phase == .connected && nowPlaying?.outputVolume != nil
        if wanted {
            volumeButtons.start()
        } else if volumeButtons.isActive {
            volumeButtons.stop()
        }
        #endif
    }

    private func sendTransport(_ command: TransportCommand) {
        send(.transport(command: command))
    }

    private func send(_ message: ClientMessage) {
        guard let connection else { return }
        Task { await send(message, on: connection) }
    }

    private func send(_ message: ClientMessage, on connection: RemoteClientConnection) async {
        requestCounter &+= 1
        let envelope = RemoteEnvelope(id: requestCounter, body: message)
        do {
            try await connection.sendJSON(envelope)
        } catch {
            phase = .failed(error.localizedDescription)
            statusText = error.localizedDescription
        }
    }
}

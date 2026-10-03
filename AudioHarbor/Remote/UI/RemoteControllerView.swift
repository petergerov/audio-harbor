import SwiftUI

private enum RemotePane: String, CaseIterable, Identifiable {
    case now, browse, queue
    var id: String { rawValue }
    var title: String {
        switch self {
        case .now: "Now"
        case .browse: "Browse"
        case .queue: "Queue"
        }
    }
}

private enum BrowseRoot: String, CaseIterable, Identifiable {
    case folders, albums, artists, playlists
    var id: String { rawValue }
    var title: String {
        switch self {
        case .folders: "Dirs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .playlists: "Lists"
        }
    }
    var scope: BrowseScope {
        switch self {
        case .folders: .folders
        case .albums: .albums
        case .artists: .artists
        case .playlists: .playlists
        }
    }
}

private struct BrowseDrill: Equatable {
    var title: String
    var scope: BrowseScope
    var parentID: String
}

/// Remote Now Playing surface — controls a Harbor engine over the LAN.
struct RemoteControllerView: View {
    @Bindable var controller: RemoteController
    @Environment(\.scenePhase) private var scenePhase
    @State private var pane: RemotePane = .now
    @State private var seekDraft: Double = 0
    @State private var isSeeking = false
    @State private var searchText = ""
    @State private var browseRoot: BrowseRoot = .folders
    @State private var drill: BrowseDrill?
    @State private var tick = Date()
    @State private var searchTask: Task<Void, Never>?
    /// Track whose playlists or labels are being edited.
    @State private var optionsRequest: RemoteTrackOptionsRequest?

    private let tickTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ReceiverChassis {
            VStack(alignment: .leading, spacing: 10) {
                header
                switch controller.phase {
                case .needsPairing:
                    pairingPanel
                case .connected:
                    panePicker
                    switch pane {
                    case .now:
                        VStack(alignment: .leading, spacing: 10) {
                            compactNowPlaying
                            searchPanel
                        }
                    case .browse:
                        browsePanel
                    case .queue:
                        queuePanel
                    }
                case .connecting:
                    ProgressView()
                        .tint(HarborColor.amber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    Text(message)
                        .font(HarborFont.body(14))
                        .foregroundStyle(HarborColor.ivoryDim)
                    Button("Disconnect") { controller.disconnect() }
                        .foregroundStyle(HarborColor.amber)
                case .idle:
                    Text("Not connected")
                        .foregroundStyle(HarborColor.ivoryDim)
                }
            }
            // Short panels (pairing, errors) start under the header instead of floating mid-screen.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The iPad shows the iPhone layout, centred at a phone-like width.
            .remoteReadableWidth()
        }
        .onReceive(tickTimer) { tick = $0 }
        .sheet(item: $optionsRequest) { request in
            RemoteTrackOptionsSheet(controller: controller, track: request.track, kind: request.kind)
        }
        #if DEBUG && os(iOS)
        .onAppear {
            if let raw = controller.fixturePane, let fixturePane = RemotePane(rawValue: raw) {
                pane = fixturePane
                if fixturePane == .browse {
                    browseRoot = .albums
                    reloadBrowseRoot()
                }
            }
            if let text = controller.fixtureSearchText {
                searchText = text
            }
        }
        #endif
        .onChange(of: scenePhase, initial: true) { _, phase in
            controller.isInForeground = phase != .background
        }
        .onChange(of: controller.phase) { _, phase in
            if phase == .connected {
                reloadBrowseRoot()
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 640)
        #endif
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.serverName ?? "Remote")
                    .font(HarborFont.title(15))
                    .foregroundStyle(HarborColor.ivory)
                Text(controller.statusText)
                    .font(HarborFont.mono(10))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .lineLimit(1)
            }
            Spacer()
            if controller.phase != .idle {
                Button("Disconnect") { controller.disconnect() }
                    .buttonStyle(.plain)
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.amber)
            }
        }
    }

    private var panePicker: some View {
        HStack(spacing: 0) {
            ForEach(RemotePane.allCases) { item in
                Button {
                    pane = item
                    if item == .browse, controller.browseItems.isEmpty {
                        reloadBrowseRoot()
                    }
                } label: {
                    Text(item.title)
                        .font(HarborFont.title(13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(pane == item ? HarborColor.chassis : HarborColor.ivory)
                        .background(pane == item ? HarborColor.amber : HarborColor.faceplateLift)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var pairingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the 6-digit code shown under Settings → Remote on the Mac.")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)

            TextField("000000", text: $controller.pairingCodeInput)
                .textFieldStyle(.plain)
                .font(HarborFont.mono(28))
                .tracking(6)
                .foregroundStyle(HarborColor.amber)
                .padding(12)
                .background(HarborColor.faceplateLift)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif

            Button {
                controller.submitPairingCode()
            } label: {
                Text("Pair")
                    .font(HarborFont.title(14))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(HarborColor.chassis)
                    .background(HarborColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(controller.pairingCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).count < 6)
        }
        .padding(.top, 8)
    }

    private var compactNowPlaying: some View {
        let snap = controller.nowPlaying
        let track = snap?.track
        let position = isSeeking ? seekDraft : controller.displayedPosition
        _ = tick

        return VStack(spacing: 8) {
            if snap?.playbackLocked == true {
                Text("The trial on \(controller.serverName ?? "the Mac") has ended. Unlock Audio Harbor in its Settings to keep playing.")
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                artwork(for: track?.artworkHash, large: false)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track?.title ?? "Nothing playing")
                        .font(HarborFont.title(14))
                        .foregroundStyle(HarborColor.ivory)
                        .lineLimit(1)
                    Text(track.map { "\($0.artist) — \($0.album)" } ?? " ")
                        .font(HarborFont.body(11))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .lineLimit(1)
                    if let path = snap?.pathLabel {
                        let format = snap?.activeFormatLabel
                        Text([path, format].compactMap { $0 }.joined(separator: " · "))
                            .font(HarborFont.mono(10))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if controller.canEditTracks, let track {
                    Menu {
                        trackOptionsButtons(track)
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .frame(width: 26, height: 30)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Playlist and Labels")
                }

                HStack(spacing: 6) {
                    compactTransport("backward.end.fill") { controller.previous() }
                    compactTransport(controller.isPlaying ? "pause.fill" : "play.fill", emphasized: true) {
                        controller.togglePlayPause()
                    }
                    compactTransport("forward.end.fill") { controller.next() }
                }
            }

            HStack(spacing: 8) {
                Text(formatTime(position))
                    .font(HarborFont.mono(10))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .frame(width: 36, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { position },
                        set: { seekDraft = $0; isSeeking = true }
                    ),
                    in: 0...max(1, snap?.duration ?? 1),
                    onEditingChanged: { editing in
                        if !editing {
                            controller.seek(to: seekDraft)
                            isSeeking = false
                        }
                    }
                )
                .tint(HarborColor.amber)
                Text(formatTime(snap?.duration ?? 0))
                    .font(HarborFont.mono(10))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .frame(width: 36, alignment: .trailing)
            }

            RemoteVolumeRow(
                volume: controller.outputVolume,
                outputName: snap?.outputName,
                onChange: controller.setVolume
            )
        }
        .padding(10)
        .background(HarborColor.faceplateLift)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HarborColor.ivoryDim)
                TextField("Search whole catalogue", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(HarborColor.ivory)
                    .onChange(of: searchText) { _, newValue in
                        scheduleSearch(newValue)
                    }
                    .onSubmit { controller.search(searchText) }
                if !searchText.isEmpty {
                    Button("Go") { controller.search(searchText) }
                        .buttonStyle(.plain)
                        .foregroundStyle(HarborColor.amber)
                    Button {
                        searchTask?.cancel()
                        searchText = ""
                        controller.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(HarborColor.ivoryDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(HarborColor.faceplateLift)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if controller.searchResults.isEmpty {
                Text(searchText.isEmpty ? "Search the whole Mac catalogue" : "No matches")
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("\(controller.searchResults.count) match\(controller.searchResults.count == 1 ? "" : "es")")
                    .font(HarborFont.mono(10))
                    .foregroundStyle(HarborColor.ivoryDim)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.searchResults, id: \.cataloguePath) { track in
                            trackRow(track)
                            Divider().overlay(HarborColor.aluminumDark.opacity(0.4))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            controller.clearSearch()
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            controller.search(trimmed)
        }
    }

    private func compactTransport(_ systemName: String, emphasized: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: emphasized ? 16 : 13, weight: .semibold))
                .foregroundStyle(emphasized ? HarborColor.chassis : HarborColor.ivory)
                .frame(width: emphasized ? 36 : 30, height: emphasized ? 36 : 30)
                .background(emphasized ? HarborColor.amber : HarborColor.faceplate)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var browsePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The roots stay while drilling in; choosing one goes back to its top level.
            browseRootPicker
            if let drill {
                browseDrillHeader(drill)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(controller.browseItems, id: \.listID) { item in
                        browseRow(item)
                        Divider().overlay(HarborColor.aluminumDark.opacity(0.4))
                    }
                    if controller.browseHasMore {
                        Button("Load more") {
                            controller.loadMoreBrowse()
                        }
                        .buttonStyle(.plain)
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.amber)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var browseRootPicker: some View {
        HStack(spacing: 0) {
            ForEach(BrowseRoot.allCases) { root in
                Button {
                    browseRoot = root
                    reloadBrowseRoot()
                } label: {
                    Text(root.title)
                        .font(HarborFont.body(12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(browseRoot == root ? HarborColor.amber : HarborColor.ivoryDim)
                        .background(
                            browseRoot == root
                                ? HarborColor.amber.opacity(0.12)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(HarborColor.faceplateLift)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func browseDrillHeader(_ drill: BrowseDrill) -> some View {
        HStack {
            Button {
                navigateBrowseBack(from: drill)
            } label: {
                Label(drill.title, systemImage: "chevron.left")
                    .font(HarborFont.title(13))
                    .foregroundStyle(HarborColor.amber)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Play all") {
                playAll(for: drill)
            }
            .buttonStyle(.plain)
            .font(HarborFont.body(13))
            .foregroundStyle(HarborColor.amber)
        }
    }

    private var queuePanel: some View {
        let queue = controller.queue
        return Group {
            if let queue, !queue.tracks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(queue.sourceKind)\(queue.sourceName.map { " · \($0)" } ?? "")")
                        .font(HarborFont.body(12))
                        .foregroundStyle(HarborColor.ivoryDim)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(queue.tracks.enumerated()), id: \.element.cataloguePath) { index, track in
                                Button {
                                    controller.playQueueIndex(index)
                                } label: {
                                    HStack(spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(HarborFont.mono(11))
                                            .foregroundStyle(HarborColor.ivoryDim)
                                            .frame(width: 28, alignment: .trailing)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title)
                                                .font(HarborFont.body(13))
                                                .foregroundStyle(
                                                    index == queue.index ? HarborColor.amber : HarborColor.ivory
                                                )
                                            Text(track.artist)
                                                .font(HarborFont.body(11))
                                                .foregroundStyle(HarborColor.ivoryDim)
                                        }
                                        Spacer()
                                        if index == queue.index {
                                            Image(systemName: controller.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                                .font(.system(size: 11))
                                                .foregroundStyle(HarborColor.amber)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    trackMenu(track) { controller.playQueueIndex(index) }
                                }
                                Divider().overlay(HarborColor.aluminumDark.opacity(0.4))
                            }
                        }
                    }
                }
            } else {
                Text("Queue is empty")
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func browseRow(_ item: BrowseItem) -> some View {
        if case .track(let dto) = item {
            browseRowButton(item)
                .contextMenu {
                    trackMenu(dto) { handleBrowseTap(item) }
                }
        } else {
            browseRowButton(item)
        }
    }

    private func browseRowButton(_ item: BrowseItem) -> some View {
        let current: Bool = if case .track(let dto) = item { isCurrent(dto) } else { false }
        return Button {
            handleBrowseTap(item)
        } label: {
            HStack(spacing: 12) {
                switch item {
                case let .album(_, _, _, _, hash):
                    artwork(for: hash, large: false)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                case .artist:
                    iconTile("person.fill")
                case .playlist:
                    iconTile("music.note.list")
                case .folder:
                    iconTile("folder.fill")
                case .track:
                    iconTile("music.note")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(HarborFont.body(13))
                        .foregroundStyle(current ? HarborColor.amber : HarborColor.ivory)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(HarborFont.body(11))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .lineLimit(1)
                }
                Spacer()
                if case .track = item {
                    trackStateIcon(isCurrent: current)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HarborColor.aluminumDark)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func trackRow(_ track: TrackDTO) -> some View {
        let current = isCurrent(track)
        return Button {
            controller.play(cataloguePath: track.cataloguePath)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(HarborFont.body(13))
                        .foregroundStyle(current ? HarborColor.amber : HarborColor.ivory)
                        .lineLimit(1)
                    Text("\(track.artist) — \(track.album)")
                        .font(HarborFont.body(11))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .lineLimit(1)
                }
                Spacer()
                trackStateIcon(isCurrent: current)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            trackMenu(track) { controller.play(cataloguePath: track.cataloguePath) }
        }
    }

    /// The track the Mac has loaded — marked in the lists, since choosing a song stays in them.
    private func isCurrent(_ track: TrackDTO) -> Bool {
        controller.nowPlaying?.track?.cataloguePath == track.cataloguePath
    }

    private func trackStateIcon(isCurrent: Bool) -> some View {
        let name = isCurrent
            ? (controller.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
            : "play.fill"
        return Image(systemName: name)
            .font(.system(size: 11))
            .foregroundStyle(HarborColor.amber)
    }

    /// Long-press menu on a track row: Play, then Add to Playlist and Labels when the Mac takes edits.
    @ViewBuilder
    private func trackMenu(_ track: TrackDTO, play: @escaping () -> Void) -> some View {
        Button(action: play) {
            Label("Play", systemImage: "play.fill")
        }
        if controller.canEditTracks {
            trackOptionsButtons(track)
        }
    }

    @ViewBuilder
    private func trackOptionsButtons(_ track: TrackDTO) -> some View {
        ForEach([RemoteTrackOptionsKind.playlists, .labels], id: \.self) { kind in
            Button {
                optionsRequest = RemoteTrackOptionsRequest(track: track, kind: kind)
            } label: {
                Label("\(kind.title)…", systemImage: kind.systemImage)
            }
        }
    }

    private func handleBrowseTap(_ item: BrowseItem) {
        switch item {
        case let .album(id, title, _, _, _):
            drill = BrowseDrill(title: title, scope: .albumTracks, parentID: id.uuidString)
            controller.browse(scope: .albumTracks, parentID: id.uuidString)
        case let .artist(name, _):
            drill = BrowseDrill(title: name, scope: .artistTracks, parentID: name)
            controller.browse(scope: .artistTracks, parentID: name)
        case let .playlist(id, name, _):
            drill = BrowseDrill(title: name, scope: .playlistTracks, parentID: id.uuidString)
            controller.browse(scope: .playlistTracks, parentID: id.uuidString)
        case let .folder(id, name, _):
            drill = BrowseDrill(title: name, scope: .folders, parentID: id)
            controller.browse(scope: .folders, parentID: id)
        case .track(let dto):
            // Stay in the list; the row marks the track once the Mac plays it.
            controller.play(cataloguePath: dto.cataloguePath)
        }
    }

    private func navigateBrowseBack(from drill: BrowseDrill) {
        if drill.scope == .folders, let parent = RemoteFolderRef.parentID(of: drill.parentID) {
            let title = RemoteFolderRef.parse(parent)?.components.last
                ?? browseRoot.title
            self.drill = BrowseDrill(title: title, scope: .folders, parentID: parent)
            controller.browse(scope: .folders, parentID: parent)
            return
        }
        self.drill = nil
        reloadBrowseRoot()
    }

    /// Stays in the list, like choosing a single song; the playing row is marked.
    private func playAll(for drill: BrowseDrill) {
        switch drill.scope {
        case .albumTracks:
            if let id = UUID(uuidString: drill.parentID) {
                controller.play(albumID: id)
            }
        case .playlistTracks:
            if let id = UUID(uuidString: drill.parentID) {
                controller.play(playlistID: id)
            }
        case .artistTracks:
            controller.playArtist(name: drill.parentID)
        case .folders:
            controller.playFolder(id: drill.parentID)
        default:
            break
        }
    }

    private func reloadBrowseRoot() {
        drill = nil
        if browseRoot == .folders {
            controller.browse(scope: .folders, parentID: nil)
        } else {
            controller.browse(scope: browseRoot.scope)
        }
    }

    @ViewBuilder
    private func artwork(for hash: String?, large: Bool) -> some View {
        let data = hash.flatMap { controller.artworkByHash[$0] }
        if let data, let image = Image(artworkData: data) {
            image
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                HarborColor.faceplate
                Image(systemName: "hifispeaker.fill")
                    .font(.system(size: large ? 22 : 16))
                    .foregroundStyle(HarborColor.aluminumDark)
            }
        }
    }

    private func iconTile(_ systemName: String) -> some View {
        ZStack {
            HarborColor.faceplateLift
            Image(systemName: systemName)
                .font(.system(size: 16))
                .foregroundStyle(HarborColor.aluminumDark)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Hardware volume of the Mac's output — the DAC when it has a volume control.
/// The phone's volume buttons step the same level.
private struct RemoteVolumeRow: View {
    let volume: Double?
    let outputName: String?
    let onChange: (Double) -> Void

    var body: some View {
        if let volume {
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .frame(width: 36, alignment: .leading)
                Slider(value: Binding(get: { volume }, set: onChange), in: 0...1)
                    .tint(HarborColor.amber)
                Text("\(Int((volume * 100).rounded()))")
                    .font(HarborFont.mono(10))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .frame(width: 36, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Volume\(outputName.map { " on \($0)" } ?? "")")
        } else if let outputName {
            Text("\(outputName) has no volume control — set the level on the amp")
                .font(HarborFont.mono(10))
                .foregroundStyle(HarborColor.ivoryDim)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

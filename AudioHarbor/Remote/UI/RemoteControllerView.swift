import SwiftUI

private enum RemoteTab: String, CaseIterable, Identifiable {
    case deck, catalogue, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .deck: "Deck"
        case .catalogue: "Catalogue"
        case .settings: "Settings"
        }
    }
    var systemImage: String {
        switch self {
        case .deck: "hifispeaker.fill"
        case .catalogue: "rectangle.stack"
        case .settings: "gearshape"
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
    /// Same wording as the Mac's catalogue search field.
    var searchPrompt: String {
        switch self {
        case .folders: "Find directories & files"
        case .albums: "Find album, artist, track"
        case .artists: "Find artist, album, track"
        case .playlists: "Find playlist, artist, track"
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

/// Remote surface — controls a Harbor engine over the LAN.
/// Bottom tabs match the Mac: Deck · Catalogue · Settings.
struct RemoteControllerView: View {
    @Bindable var controller: RemoteController
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DefaultsKey.deckStyle) private var deckStyleRaw: String = DeckStyle.turntable.rawValue
    @State private var tab: RemoteTab = .deck
    @State private var scrubRatio: Double?
    @State private var showQueue = false
    /// Volume slider stays collapsed so Playlist / Labels is not next to a live thumb.
    @State private var showVolumeControl = false
    @State private var browseRoot: BrowseRoot = .folders
    @State private var drill: BrowseDrill?
    @State private var tick = Date()
    /// Browse search, under the Dirs / Albums / Artists / Lists tabs.
    @State private var browseQuery = ""
    @State private var browseSearchTask: Task<Void, Never>?
    /// Track whose playlists or labels are being edited.
    @State private var optionsRequest: RemoteTrackOptionsRequest?

    private let tickTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var deckStyle: Binding<DeckStyle> {
        Binding(
            get: { DeckStyle(rawValue: deckStyleRaw) ?? .turntable },
            set: { deckStyleRaw = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            switch controller.phase {
            case .connected:
                connectedTabs
            case .needsPairing, .connecting, .failed, .idle:
                ReceiverChassis {
                    VStack(alignment: .leading, spacing: 10) {
                        connectionHeader
                        switch controller.phase {
                        case .needsPairing:
                            pairingPanel
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
                        default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .remoteReadableWidth()
                }
            }
        }
        .onReceive(tickTimer) { tick = $0 }
        .sheet(item: $optionsRequest) { request in
            RemoteTrackOptionsSheet(controller: controller, track: request.track, kind: request.kind)
        }
        .sheet(isPresented: $showQueue) {
            remoteQueueSheet
        }
        #if DEBUG && os(iOS)
        .onAppear {
            if let raw = controller.fixturePane {
                switch raw {
                case "browse", "catalogue":
                    tab = .catalogue
                    browseRoot = .albums
                    reloadBrowseRoot()
                case "queue", "deck", "now":
                    tab = .deck
                default:
                    break
                }
            }
            if controller.fixtureShowQueue {
                showQueue = true
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

    private var connectedTabs: some View {
        TabView(selection: $tab) {
            deckPage
                .tabItem { Label(RemoteTab.deck.title, systemImage: RemoteTab.deck.systemImage) }
                .tag(RemoteTab.deck)

            cataloguePage
                .tabItem { Label(RemoteTab.catalogue.title, systemImage: RemoteTab.catalogue.systemImage) }
                .tag(RemoteTab.catalogue)

            settingsPage
                .tabItem { Label(RemoteTab.settings.title, systemImage: RemoteTab.settings.systemImage) }
                .tag(RemoteTab.settings)
        }
        .tint(HarborColor.amber)
        #if os(iOS)
        .toolbarBackground(HarborColor.chassis, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        #endif
        .onChange(of: tab) { _, newTab in
            if newTab == .catalogue, controller.browseItems.isEmpty {
                reloadBrowseRoot()
            }
            if newTab == .settings {
                controller.refreshSettings()
            }
        }
    }

    // MARK: - Deck

    private var deckPage: some View {
        NavigationStack {
            ReceiverChassis {
                GeometryReader { geo in
                    ScrollView {
                        VStack(spacing: 10) {
                            if controller.nowPlaying?.playbackLocked == true {
                                Text("The trial on \(controller.serverName ?? "the Mac") has ended. Unlock Audio Harbor in its Settings to keep playing.")
                                    .font(HarborFont.body(12))
                                    .foregroundStyle(HarborColor.amber)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            deckChrome(heroHeight: deckHeroHeight(in: geo.size))
                        }
                        .padding(.bottom, 8)
                    }
                    #if os(iOS)
                    .scrollBounceBehavior(.basedOnSize)
                    #endif
                }
            }
            .navigationTitle(controller.serverName ?? "Deck")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { disconnectToolbar }
        }
    }

    private func deckChrome(heroHeight: CGFloat) -> some View {
        let snap = controller.nowPlaying
        let track = snap?.track
        let duration = max(snap?.duration ?? 0, 0.1)
        let display = scrubRatio.map { $0 * duration } ?? controller.displayedPosition
        let progress = min(max(display / duration, 0), 1)
        let style = deckStyle.wrappedValue.resolvedForCompact
        let artworkImage = artworkImage(for: track?.artworkHash)
        _ = tick

        return VStack(spacing: 12) {
            DeckStage(
                style: deckStyle,
                artwork: artworkImage,
                isPlaying: controller.isPlaying,
                progress: progress,
                heroHeight: heroHeight,
                meterLeft: 0,
                meterRight: 0
            ) {
                // Live/Standby is the LED on the stage photo (top trailing) — no room for PowerLamp here.
                HStack(spacing: 8) {
                    volumeToolbarButton(
                        volume: controller.outputVolume,
                        outputName: snap?.outputName
                    )
                    queueToggle
                }
            }

            if showVolumeControl, let volume = controller.outputVolume {
                volumeSliderRow(volume: volume, outputName: snap?.outputName)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(spacing: 5) {
                Text(track?.title ?? idleTitle(style))
                    .font(HarborFont.display(20))
                    .foregroundStyle(HarborColor.ivory)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                Text(track.map { "\($0.artist)  ·  \($0.album)" } ?? idleSubtitle(style))
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }

            VStack(spacing: 6) {
                SeekBar(
                    progress: progress,
                    onSeeking: { scrubRatio = $0 },
                    onSeekEnded: { ratio in
                        controller.seek(to: ratio * duration)
                        scrubRatio = nil
                    }
                )
                ZStack {
                    HStack {
                        Text(display.clockText)
                        Spacer()
                        Text(duration.clockText)
                    }
                    if let track {
                        FormatBadge(
                            format: AudioFormat(rawValue: track.format) ?? .unknown,
                            sampleRateHz: track.sampleRateHz,
                            bitDepth: track.bitDepth,
                            path: snap?.pathLabel,
                            liveLabel: snap?.activeFormatLabel != track.format
                                ? snap?.activeFormatLabel
                                : nil
                        )
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 52)
                    }
                }
                .font(HarborFont.mono(12))
                .foregroundStyle(HarborColor.ivoryDim)
            }

            HStack(spacing: 14) {
                HardwareButton(
                    systemName: "shuffle",
                    isLit: snap?.isShuffled == true,
                    isSatellite: true
                ) {
                    controller.toggleShuffle()
                }
                .accessibilityLabel("Shuffle")
                .accessibilityValue(snap?.isShuffled == true ? "On" : "Off")

                HardwareButton(systemName: "backward.fill") {
                    controller.previous()
                }
                HardwareButton(
                    systemName: controller.isPlaying ? "pause.fill" : "play.fill",
                    isPrimary: true,
                    isLit: controller.isPlaying
                ) {
                    controller.togglePlayPause()
                }
                HardwareButton(systemName: "forward.fill") {
                    controller.next()
                }

                let repeatMode = RepeatMode(rawValue: snap?.repeatMode ?? "") ?? .off
                HardwareButton(
                    systemName: repeatMode.systemImage,
                    isLit: repeatMode != .off,
                    isSatellite: true
                ) {
                    controller.cycleRepeatMode()
                }
                .accessibilityLabel("Repeat")
                .accessibilityValue(repeatMode.title)
            }
            .scaleEffect(0.86, anchor: .center)
            .padding(.vertical, -6)

            if controller.canEditTracks, let track {
                Menu {
                    trackOptionsButtons(track)
                } label: {
                    Label("Playlist and Labels", systemImage: "text.badge.plus")
                        .font(HarborFont.title(14))
                        .foregroundStyle(HarborColor.amber)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(HarborColor.faceplateLift)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showVolumeControl)
        .faceplate(compact: true)
    }

    /// Same chrome pill as Queue — lives in the stage toolbar, away from Playlist / Labels.
    @ViewBuilder
    private func volumeToolbarButton(volume: Double?, outputName: String?) -> some View {
        if let volume {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeControl.toggle()
                }
            } label: {
                Image(systemName: RemoteVolumeSymbols.symbol(for: volume))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(showVolumeControl ? HarborColor.faceplate : HarborColor.ivoryDim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(showVolumeControl ? HarborColor.amber : HarborColor.faceplate.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(HarborColor.aluminumDark, lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Volume\(outputName.map { " on \($0)" } ?? "")")
            .accessibilityValue("\(Int((volume * 100).rounded())) percent")
            .accessibilityHint(showVolumeControl ? "Hides the volume slider" : "Shows the volume slider")
        } else if outputName != nil {
            Image(systemName: "speaker.slash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HarborColor.aluminumDark)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(HarborColor.faceplate.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(HarborColor.aluminumDark.opacity(0.6), lineWidth: 1)
                        )
                )
                .accessibilityLabel(outputName.map { "\($0) has no volume control" } ?? "No volume control")
        }
    }

    private func volumeSliderRow(volume: Double, outputName: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: RemoteVolumeSymbols.symbol(for: volume))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HarborColor.amber)
                .frame(width: 22)
            Slider(
                value: Binding(
                    get: { volume },
                    set: { controller.setVolume($0) }
                ),
                in: 0...1
            )
            .tint(HarborColor.amber)
            Text("\(Int((volume * 100).rounded()))")
                .font(HarborFont.mono(11))
                .foregroundStyle(HarborColor.ivoryDim)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(HarborColor.faceplateLift)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Volume\(outputName.map { " on \($0)" } ?? "")")
    }

    private var queueToggle: some View {
        Button {
            showQueue = true
        } label: {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(showQueue ? HarborColor.faceplate : HarborColor.ivoryDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(showQueue ? HarborColor.amber : HarborColor.faceplate.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(HarborColor.aluminumDark, lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show queue")
    }

    private var remoteQueueSheet: some View {
        NavigationStack {
            ReceiverChassis {
                queuePanel
                    .padding(.horizontal, 4)
            }
            .navigationTitle(queueNavigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showQueue = false }
                        .foregroundStyle(HarborColor.amber)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var queueNavigationTitle: String {
        if let name = controller.queue?.sourceName, !name.isEmpty { return name }
        return controller.queue?.sourceKind ?? "Queue"
    }

    private func deckHeroHeight(in size: CGSize) -> CGFloat {
        let reserved: CGFloat = 360
        return min(228, max(128, size.height - reserved))
    }

    private func idleTitle(_ style: DeckStyle) -> String {
        switch style {
        case .turntable: "Nothing on the platter"
        case .reelToReel: "No tape threaded"
        case .receiver: "No source selected"
        }
    }

    private func idleSubtitle(_ style: DeckStyle) -> String {
        switch style {
        case .turntable: "Drop the needle from Catalogue"
        case .reelToReel: "Load a track from Catalogue"
        case .receiver: "Choose a track from Catalogue"
        }
    }

    // MARK: - Catalogue

    private var cataloguePage: some View {
        NavigationStack {
            ReceiverChassis {
                browsePanel
            }
            .navigationTitle("Catalogue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { disconnectToolbar }
        }
    }

    // MARK: - Settings

    private var settingsPage: some View {
        RemoteMacSettingsView(
            controller: controller,
            showsDismissButton: false,
            onDisconnect: { controller.disconnect() }
        )
    }

    // MARK: - Shared chrome

    private var connectionHeader: some View {
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

    @ToolbarContentBuilder
    private var disconnectToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button("Disconnect") { controller.disconnect() }
                .foregroundStyle(HarborColor.amber)
        }
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

    private var browsePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The roots stay while drilling in; choosing one goes back to its top level.
            browseRootPicker
            if controller.canSearchBrowse {
                browseSearchField
            }
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

    private var browseSearchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(HarborColor.ivoryDim)
            // Set through the binding so clearing it in code does not reload the list. Only a real
            // change searches: losing focus writes the same text back, and must not undo a drill-in.
            TextField(browseRoot.searchPrompt, text: Binding(
                get: { browseQuery },
                set: { newValue in
                    guard newValue != browseQuery else { return }
                    browseQuery = newValue
                    scheduleBrowseSearch()
                }
            ))
            .textFieldStyle(.plain)
            .foregroundStyle(HarborColor.ivory)
            .submitLabel(.search)
            .onSubmit {
                browseSearchTask?.cancel()
                reloadBrowseRoot()
            }
            if !browseQuery.isEmpty {
                Button {
                    browseQuery = ""
                    browseSearchTask?.cancel()
                    reloadBrowseRoot()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(HarborColor.ivoryDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(10)
        .background(HarborColor.faceplateLift)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// A pause after typing, then the current tab's top level, filtered.
    private func scheduleBrowseSearch() {
        browseSearchTask?.cancel()
        browseSearchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            reloadBrowseRoot()
        }
    }

    /// The query the Mac filters by — nil when the Mac predates browse search.
    private var activeBrowseQuery: String? {
        controller.canSearchBrowse && !browseQuery.isEmpty ? browseQuery : nil
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
                    Text("\(queue.sourceKind)\(queue.sourceName.map { " · \($0)" } ?? "") · \(queue.tracks.count) tracks")
                        .font(HarborFont.body(12))
                        .foregroundStyle(HarborColor.ivoryDim)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(queue.tracks.enumerated()), id: \.element.cataloguePath) { index, track in
                                Button {
                                    controller.playOrToggleQueueIndex(index)
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
                    // Context "Play" always starts the song; row tap toggles pause when current.
                    trackMenu(dto) { controller.play(cataloguePath: dto.cataloguePath) }
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
        // A search still waiting to run would replace what this opens.
        browseSearchTask?.cancel()
        switch item {
        case let .album(id, title, _, _, _):
            drill = BrowseDrill(title: title, scope: .albumTracks, parentID: id.uuidString)
            controller.browse(scope: .albumTracks, parentID: id.uuidString, query: activeBrowseQuery)
        case let .artist(name, _):
            drill = BrowseDrill(title: name, scope: .artistTracks, parentID: name)
            controller.browse(scope: .artistTracks, parentID: name, query: activeBrowseQuery)
        case let .playlist(id, name, _):
            drill = BrowseDrill(title: name, scope: .playlistTracks, parentID: id.uuidString)
            controller.browse(scope: .playlistTracks, parentID: id.uuidString, query: activeBrowseQuery)
        case let .folder(id, name, _):
            // As on the Mac, opening a directory from the search clears it.
            browseQuery = ""
            drill = BrowseDrill(title: name, scope: .folders, parentID: id)
            controller.browse(scope: .folders, parentID: id)
        case .track(let dto):
            // Stay in the list; a second tap on the playing song pauses (or resumes).
            controller.playOrToggle(cataloguePath: dto.cataloguePath)
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
        controller.browse(scope: browseRoot.scope, query: activeBrowseQuery)
    }

    private func artworkImage(for hash: String?) -> Image? {
        hash.flatMap { controller.artworkByHash[$0] }.flatMap(Image.init(artworkData:))
    }

    @ViewBuilder
    private func artwork(for hash: String?, large: Bool) -> some View {
        if let image = artworkImage(for: hash) {
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
}

private enum RemoteVolumeSymbols {
    static func symbol(for volume: Double) -> String {
        if volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

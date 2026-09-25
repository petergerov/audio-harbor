import SwiftUI
import UniformTypeIdentifiers

private enum PlaylistBrowserScope: String, CaseIterable, Identifiable {
    case playlists
    case labels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .labels: "Labels"
        }
    }

    func contains(_ item: PlaylistBrowserItem) -> Bool {
        switch (self, item) {
        case (.playlists, .playlist): true
        case (.labels, .label): true
        default: false
        }
    }
}

private enum PlaylistBrowserItem: Hashable, Identifiable {
    case playlist(UUID)
    case label(String)

    var id: String {
        switch self {
        case .playlist(let id): "playlist-\(id.uuidString)"
        case .label(let name): "label-\(name)"
        }
    }

    var title: String {
        switch self {
        case .playlist: "Playlist"
        case .label(let name): name
        }
    }

    var kindLabel: String {
        switch self {
        case .playlist: "Playlist"
        case .label: "Label"
        }
    }

    func queueSource(named name: String) -> QueueSource {
        switch self {
        case .playlist: .playlist(name)
        case .label: .label(name)
        }
    }
}

struct PlaylistsView: View {
    @Environment(AppModel.self) private var appModel
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var newName = ""
    @State private var isCreating = false
    @State private var renameDraft = ""
    @State private var renaming: Playlist?
    @State private var selection: PlaylistBrowserItem?
    @State private var isImportingM3U = false
    @State private var importReport: ImportReport?
    @AppStorage("audioharbor.playlists.browserScope") private var browserScopeRaw: String = PlaylistBrowserScope.playlists.rawValue

    private var browserScope: Binding<PlaylistBrowserScope> {
        Binding(
            get: { PlaylistBrowserScope(rawValue: browserScopeRaw) ?? .playlists },
            set: { browserScopeRaw = $0.rawValue }
        )
    }

    var body: some View {
        ReceiverChassis {
            VStack(spacing: 14) {
                header
                Group {
                    #if os(macOS)
                    HStack(spacing: 0) {
                        browserSidebar
                            .frame(width: 280)
                        Divider().overlay(HarborColor.aluminumDark.opacity(0.55))
                        detailPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    #else
                    if horizontalSizeClass == .regular {
                        HStack(spacing: 0) {
                            browserSidebar
                                .frame(width: 280)
                            Divider().overlay(HarborColor.aluminumDark.opacity(0.55))
                            detailPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else if selection != nil {
                        detailPane
                    } else {
                        browserSidebar
                    }
                    #endif
                }
                .faceplate()
            }
        }
        #if os(iOS)
        .navigationTitle(selection.map(navigationTitle(for:)) ?? "Playlists")
        .toolbar {
            if selection != nil, horizontalSizeClass == .compact {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { selection = nil }
                }
            }
        }
        #endif
        .onChange(of: browserScopeRaw) { _, _ in
            if let selection, !browserScope.wrappedValue.contains(selection) {
                self.selection = nil
            }
        }
        .sheet(isPresented: $isCreating) {
            newPlaylistSheet
        }
        .fileImporter(
            isPresented: $isImportingM3U,
            allowedContentTypes: Self.m3uContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importM3U(urls: urls)
            }
        }
        .alert(
            importReport?.title ?? "",
            isPresented: Binding(
                get: { importReport != nil },
                set: { if !$0 { importReport = nil } }
            ),
            presenting: importReport
        ) { _ in
            Button("OK", role: .cancel) { importReport = nil }
        } message: { report in
            Text(report.message)
        }
        .alert("Rename Playlist", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let renaming {
                    appModel.playlists.rename(renaming, to: renameDraft)
                }
                self.renaming = nil
            }
        }
    }

    private var header: some View {
        ScreenHeader(
            title: "Playlists",
            subtitle: "Switch the list on the left — playlists or labels."
        ) {
            HarborButton(
                title: "Import M3U",
                systemImage: "square.and.arrow.down",
                kind: .secondary,
                action: { isImportingM3U = true }
            )
            HarborButton(
                title: "Add Playlist",
                systemImage: "plus",
                kind: .primary,
                action: {
                    newName = ""
                    isCreating = true
                }
            )
        }
    }

    private var browserSidebar: some View {
        VStack(spacing: 10) {
            scopePicker
            List(selection: $selection) {
                switch browserScope.wrappedValue {
                case .playlists:
                    playlistsSection
                case .labels:
                    labelsSection
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 8)
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PlaylistBrowserScope.allCases) { scope in
                    let selected = browserScope.wrappedValue == scope
                    Button {
                        browserScope.wrappedValue = scope
                    } label: {
                        Text(scope.title.uppercased())
                            .font(HarborFont.panel(9))
                            .tracking(0.8)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? HarborColor.faceplate : HarborColor.ivoryDim)
                            .background(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(selected ? HarborColor.amber : HarborColor.faceplate.opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .stroke(HarborColor.aluminumDark, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
        .scrollClipDisabled()
        .accessibilityLabel("Switch between playlists and labels")
    }

    @ViewBuilder
    private var playlistsSection: some View {
        if appModel.playlists.playlists.filter({ !$0.isSmart }).isEmpty {
            Text("No playlists yet")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
                .listRowBackground(HarborColor.faceplate)
        } else {
            ForEach(appModel.playlists.playlists.filter { !$0.isSmart }) { playlist in
                sidebarRow(
                    title: playlist.name,
                    subtitle: "\(playlist.trackPaths.count) tracks",
                    systemImage: "music.note.list",
                    item: .playlist(playlist.id)
                )
                .contextMenu {
                    Button("Play") { play(item: .playlist(playlist.id)) }
                    #if os(macOS)
                    Button("Export M3U8…") { exportM3U8(item: .playlist(playlist.id)) }
                    #endif
                    Button("Rename") {
                        renameDraft = playlist.name
                        renaming = playlist
                    }
                    Button("Delete", role: .destructive) {
                        if selection == .playlist(playlist.id) { selection = nil }
                        appModel.playlists.delete(playlist)
                    }
                }
            }
            .onDelete { offsets in
                let manuals = appModel.playlists.playlists.filter { !$0.isSmart }
                offsets.map { manuals[$0] }.forEach(appModel.playlists.delete)
            }
        }
    }

    @ViewBuilder
    private var labelsSection: some View {
        if appModel.library.labelFacets.isEmpty {
            Text("Add labels from Catalogue (right‑click a track).")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
                .listRowBackground(HarborColor.faceplate)
        } else {
            ForEach(appModel.library.labelFacets) { facet in
                sidebarRow(
                    title: facet.name,
                    subtitle: "\(facet.count) tracks",
                    systemImage: "tag",
                    item: .label(facet.name)
                )
                .contextMenu {
                    Button("Play") { play(item: .label(facet.name)) }
                }
            }
        }
    }

    private func sidebarRow(
        title: String,
        subtitle: String,
        systemImage: String,
        item: PlaylistBrowserItem
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(HarborColor.amber)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HarborFont.title(14))
                    .foregroundStyle(HarborColor.ivory)
                    .lineLimit(1)
                Text(subtitle)
                    .font(HarborFont.panel(10))
                    .foregroundStyle(HarborColor.ivoryDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .tag(item)
        .listRowBackground(
            selection == item
                ? HarborColor.amber.opacity(0.14)
                : HarborColor.faceplate
        )
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selection {
            let tracks = tracks(for: selection)
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        EngravedLabel(text: selection.kindLabel)
                        Text(detailTitle(for: selection))
                            .font(HarborFont.title(18))
                            .foregroundStyle(HarborColor.ivory)
                        Text("\(tracks.count) tracks")
                            .font(HarborFont.panel(10))
                            .foregroundStyle(HarborColor.ivoryDim)
                    }
                    Spacer()
                    #if os(macOS)
                    Button("Export M3U8") { exportM3U8(item: selection) }
                        .font(HarborFont.panel(11))
                        .foregroundStyle(HarborColor.ivory)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(HarborColor.faceplateLift)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .buttonStyle(.plain)
                        .disabled(tracks.isEmpty)
                    #endif
                    Button("Play All") { play(item: selection) }
                        .font(HarborFont.panel(11))
                        .foregroundStyle(HarborColor.faceplate)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(HarborColor.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .buttonStyle(.plain)
                        .disabled(tracks.isEmpty)
                }
                .padding(.bottom, 12)

                if tracks.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Text("No tracks")
                            .font(HarborFont.title(16))
                            .foregroundStyle(HarborColor.ivory)
                        Text(emptyDetailMessage(for: selection))
                            .font(HarborFont.body(13))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let playlists = appModel.playlists.playlists.filter { !$0.isSmart }
                    let labels = appModel.library.allLabels
                    List {
                        ForEach(tracks) { track in
                            TrackRow(
                                track: track,
                                playlists: playlists,
                                onPlay: {
                                    appModel.play(
                                        tracks,
                                        startingAt: track,
                                        from: selection.queueSource(named: detailTitle(for: selection))
                                    )
                                },
                                onAddToPlaylist: { playlist in
                                    appModel.playlists.add(track, to: playlist)
                                },
                                onAddLabel: { label in
                                    appModel.library.addLabel(label, to: track)
                                },
                                onRemoveLabel: { label in
                                    appModel.library.removeLabel(label, from: track)
                                },
                                knownLabels: labels
                            )
                            .listRowBackground(HarborColor.faceplate)
                            .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
                        }
                        .onDelete(perform: deleteHandler(for: selection, tracks: tracks))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(12)
        } else {
            VStack(spacing: 12) {
                Spacer()
                EngravedLabel(text: "Select a collection")
                Text("Choose a playlist or label on the left.")
                    .font(HarborFont.body(14))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
    }

    private func tracks(for item: PlaylistBrowserItem) -> [Track] {
        switch item {
        case .playlist(let id):
            guard let playlist = appModel.playlists.playlists.first(where: { $0.id == id }) else { return [] }
            return appModel.playlists.tracks(for: playlist, from: appModel.library.allTracks)
        case .label(let name):
            return appModel.library.tracks(forLabel: name)
        }
    }

    private func detailTitle(for item: PlaylistBrowserItem) -> String {
        switch item {
        case .playlist(let id):
            return appModel.playlists.playlists.first(where: { $0.id == id })?.name ?? "Playlist"
        case .label(let name):
            return name
        }
    }

    private func navigationTitle(for item: PlaylistBrowserItem) -> String {
        detailTitle(for: item)
    }

    private func emptyDetailMessage(for item: PlaylistBrowserItem) -> String {
        switch item {
        case .playlist:
            return "Open Catalogue, right‑click a track, Add to Playlist."
        case .label:
            return "No tracks use this label yet."
        }
    }

    private func deleteHandler(
        for item: PlaylistBrowserItem,
        tracks: [Track]
    ) -> ((IndexSet) -> Void)? {
        guard case .playlist(let id) = item,
              let playlist = appModel.playlists.playlists.first(where: { $0.id == id }),
              !playlist.isSmart
        else { return nil }
        return { offsets in
            offsets.forEach { i in
                appModel.playlists.removeTrack(tracks[i], from: playlist)
            }
        }
    }

    private func play(item: PlaylistBrowserItem) {
        appModel.play(tracks(for: item), from: item.queueSource(named: detailTitle(for: item)))
    }

    private var newPlaylistSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            EngravedLabel(text: "Collections")
            Text("New Playlist")
                .font(HarborFont.title(18))
                .foregroundStyle(HarborColor.ivory)
            TextField("Name", text: $newName)
                .textFieldStyle(.plain)
                .font(HarborFont.body(14))
                .foregroundStyle(HarborColor.ivory)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(HarborColor.faceplateLift)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(HarborColor.aluminumDark.opacity(0.7), lineWidth: 1)
                        )
                )
                .onSubmit(createManual)
            HStack {
                Spacer()
                HarborButton(title: "Cancel", kind: .secondary) {
                    newName = ""
                    isCreating = false
                }
                HarborButton(title: "Create", kind: .primary, action: createManual)
            }
        }
        .padding(22)
        .frame(minWidth: 360)
        .background(HarborColor.faceplate)
        #if os(macOS)
        .frame(width: 400)
        #endif
    }

    private func createManual() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? nextUntitledPlaylistName() : trimmed
        appModel.playlists.createPlaylist(named: name)
        browserScopeRaw = PlaylistBrowserScope.playlists.rawValue
        if let created = appModel.playlists.playlists.first(where: { !$0.isSmart && $0.name == name }) {
            selection = .playlist(created.id)
        }
        newName = ""
        isCreating = false
    }

    private func nextUntitledPlaylistName() -> String {
        let existing = Set(appModel.playlists.playlists.map(\.name))
        if !existing.contains("Untitled Playlist") {
            return "Untitled Playlist"
        }
        var index = 2
        while existing.contains("Untitled Playlist \(index)") {
            index += 1
        }
        return "Untitled Playlist \(index)"
    }

    // MARK: - M3U8 export

    #if os(macOS)
    private func exportM3U8(item: PlaylistBrowserItem) {
        let tracks = tracks(for: item)
        guard !tracks.isEmpty else { return }
        let name = detailTitle(for: item)

        let panel = NSSavePanel()
        panel.title = "Export Playlist"
        panel.message = "Saves an M3U8 file that foobar2000, VLC and other players can open."
        panel.prompt = "Export"
        // `.m3u8` is a tag of public.m3u-playlist; the panel keeps it instead of forcing `.m3u`.
        panel.allowedContentTypes = [.m3uPlaylist]
        panel.nameFieldStringValue = "\(name.replacingOccurrences(of: "/", with: "-")).m3u8"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Data(M3UWriter.render(name: name, tracks: tracks).utf8).write(to: url, options: .atomic)
        } catch {
            importReport = ImportReport(
                title: "Export Failed",
                message: "\(url.lastPathComponent) could not be written. \(error.localizedDescription)"
            )
        }
    }
    #endif

    // MARK: - M3U import

    private struct ImportReport {
        var title: String
        var message: String
    }

    private static let m3uContentTypes: [UTType] = {
        var types: [UTType] = [.m3uPlaylist]
        for ext in ["m3u", "m3u8"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }()

    private func importM3U(urls: [URL]) {
        let libraryTracks = appModel.library.allTracks
        guard !libraryTracks.isEmpty else {
            importReport = ImportReport(
                title: "Nothing to Match Yet",
                message: "Add the folders with your music first. Playlists only point at files Harbor already knows."
            )
            return
        }

        let matcher = M3UMatcher(tracks: libraryTracks)
        var lines: [String] = []
        var lastImported: Playlist?
        for url in urls {
            // Picker URLs are security-scoped; read synchronously while access is open.
            let started = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if started {
                url.stopAccessingSecurityScopedResource()
            }
            guard let data, let text = M3UParser.decode(data) else {
                lines.append("\(url.lastPathComponent): could not be read.")
                continue
            }

            let result = matcher.resolve(M3UParser.parse(text), playlistURL: url)
            guard !result.trackPaths.isEmpty else {
                lines.append("“\(result.name)”: none of \(result.entryCount) entries found in your folders — not imported.")
                continue
            }

            let playlist = appModel.playlists.importPlaylist(named: result.name, trackPaths: result.trackPaths)
            lastImported = playlist
            lines.append(summary(for: result, importedAs: playlist.name))
        }

        if let lastImported {
            browserScopeRaw = PlaylistBrowserScope.playlists.rawValue
            selection = .playlist(lastImported.id)
        }
        importReport = ImportReport(
            title: lastImported == nil ? "Import Failed" : "Playlist Imported",
            message: lines.joined(separator: "\n\n")
        )
    }

    private func summary(for result: M3UImportResult, importedAs name: String) -> String {
        let fileEntries = result.entryCount - result.skippedRemoteCount
        var text = "“\(name)”: \(fileEntries - result.unmatched.count) of \(fileEntries) tracks."
        if result.skippedRemoteCount > 0 {
            text += " \(result.skippedRemoteCount) stream URLs skipped."
        }
        if !result.unmatched.isEmpty {
            let names = result.unmatched.prefix(5).map { entry in
                entry.displayName ?? URL(fileURLWithPath: entry.location.replacingOccurrences(of: "\\", with: "/")).lastPathComponent
            }
            text += "\nNot in your folders:\n" + names.map { "· \($0)" }.joined(separator: "\n")
            if result.unmatched.count > names.count {
                text += "\n· … and \(result.unmatched.count - names.count) more"
            }
        }
        return text
    }
}

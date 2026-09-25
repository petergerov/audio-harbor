import SwiftUI
import UniformTypeIdentifiers

struct PlaylistsView: View {
    @Environment(AppModel.self) private var appModel
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var model: PlaylistsViewModel
    @State private var newName = ""
    @State private var isCreating = false
    @State private var renameDraft = ""
    @State private var renaming: Playlist?
    @State private var isImportingM3U = false

    init(appModel: AppModel) {
        _model = State(initialValue: PlaylistsViewModel(app: appModel))
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
                    } else if model.selection != nil {
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
        .navigationTitle(model.selection.map(model.title(for:)) ?? "Playlists")
        .toolbar {
            if model.selection != nil, horizontalSizeClass == .compact {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { model.selection = nil }
                }
            }
        }
        #endif
        .sheet(isPresented: $isCreating) {
            newPlaylistSheet
        }
        .fileImporter(
            isPresented: $isImportingM3U,
            allowedContentTypes: Self.m3uContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.importM3U(from: urls)
            }
        }
        .alert(
            model.report?.title ?? "",
            isPresented: Binding(
                get: { model.report != nil },
                set: { if !$0 { model.report = nil } }
            ),
            presenting: model.report
        ) { _ in
            Button("OK", role: .cancel) { model.report = nil }
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
                    model.rename(renaming, to: renameDraft)
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
            List(selection: $model.selection) {
                switch model.scope {
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
                    let selected = model.scope == scope
                    Button {
                        model.scope = scope
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
        if model.manualPlaylists.isEmpty {
            Text("No playlists yet")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
                .listRowBackground(HarborColor.faceplate)
        } else {
            ForEach(model.manualPlaylists) { playlist in
                sidebarRow(
                    title: playlist.name,
                    subtitle: "\(playlist.trackPaths.count) tracks",
                    systemImage: "music.note.list",
                    item: .playlist(playlist.id)
                )
                .contextMenu {
                    Button("Play") { model.play(.playlist(playlist.id)) }
                    #if os(macOS)
                    Button("Export M3U8…") { exportM3U8(item: .playlist(playlist.id)) }
                    #endif
                    Button("Rename") {
                        renameDraft = playlist.name
                        renaming = playlist
                    }
                    Button("Delete", role: .destructive) {
                        model.delete(playlist)
                    }
                }
            }
            .onDelete(perform: model.deleteManualPlaylists)
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
                    Button("Play") { model.play(.label(facet.name)) }
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
            model.selection == item
                ? HarborColor.amber.opacity(0.14)
                : HarborColor.faceplate
        )
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selection = model.selection {
            let tracks = model.tracks(for: selection)
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        EngravedLabel(text: selection.kindLabel)
                        Text(model.title(for: selection))
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
                    Button("Play All") { model.play(selection) }
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
                        Text(model.emptyMessage(for: selection))
                            .font(HarborFont.body(13))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(tracks) { track in
                            TrackRow(track: track) { model.play(selection, startingAt: track) }
                                .listRowBackground(HarborColor.faceplate)
                                .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
                        }
                        .onDelete(perform: model.canRemoveTracks(from: selection)
                            ? { model.removeTracks(at: $0, of: tracks, from: selection) }
                            : nil)
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
        model.createPlaylist(named: newName)
        newName = ""
        isCreating = false
    }

    // MARK: - M3U8 export

    #if os(macOS)
    private func exportM3U8(item: PlaylistBrowserItem) {
        guard !model.tracks(for: item).isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = "Export Playlist"
        panel.message = "Saves an M3U8 file that foobar2000, VLC and other players can open."
        panel.prompt = "Export"
        // `.m3u8` is a tag of public.m3u-playlist; the panel keeps it instead of forcing `.m3u`.
        panel.allowedContentTypes = [.m3uPlaylist]
        panel.nameFieldStringValue = model.exportFileName(for: item)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportM3U8(item, to: url)
    }
    #endif

    // MARK: - M3U import

    private static let m3uContentTypes: [UTType] = {
        var types: [UTType] = [.m3uPlaylist]
        for ext in ["m3u", "m3u8"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }()
}

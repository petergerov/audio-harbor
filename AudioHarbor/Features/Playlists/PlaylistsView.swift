import SwiftUI

private enum PlaylistBrowserItem: Hashable, Identifiable {
    case playlist(UUID)
    case artist(String)
    case label(String)
    case year(Int)

    var id: String {
        switch self {
        case .playlist(let id): "playlist-\(id.uuidString)"
        case .artist(let name): "artist-\(name)"
        case .label(let name): "label-\(name)"
        case .year(let year): "year-\(year)"
        }
    }

    var title: String {
        switch self {
        case .playlist: "Playlist"
        case .artist(let name): name
        case .label(let name): name
        case .year(let year): String(year)
        }
    }

    var kindLabel: String {
        switch self {
        case .playlist: "Playlist"
        case .artist: "Artist"
        case .label: "Label"
        case .year: "Year"
        }
    }
}

struct PlaylistsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var newName = ""
    @State private var isCreating = false
    @State private var renameDraft = ""
    @State private var renaming: Playlist?
    @State private var selection: PlaylistBrowserItem?

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
                    if selection != nil {
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
            if selection != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { selection = nil }
                }
            }
        }
        #endif
        .alert("New Playlist", isPresented: $isCreating) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {
                newName = ""
            }
            Button("Create") {
                createManual()
            }
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                EngravedLabel(text: "Collections")
                Text("Playlists")
                    .font(HarborFont.display(28))
                    .foregroundStyle(HarborColor.ivory)
                Text("Your playlists, plus auto collections by artist, label, and year.")
                    .font(HarborFont.body(14))
                    .foregroundStyle(HarborColor.ivoryDim)
            }
            Spacer(minLength: 0)
            Button {
                newName = ""
                isCreating = true
            } label: {
                Label("Add Playlist", systemImage: "plus")
                    .font(HarborFont.panel(11))
                    .foregroundStyle(HarborColor.faceplate)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(HarborColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var browserSidebar: some View {
        List(selection: $selection) {
            Section {
                if appModel.playlists.playlists.filter({ !$0.isSmart }).isEmpty {
                    Text("No playlists yet")
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .listRowBackground(HarborColor.faceplate)
                } else {
                    ForEach(appModel.playlists.playlists.filter { !$0.isSmart }) { playlist in
                        sidebarRow(
                            title: playlist.name,
                            subtitle: "\(trackCount(for: .playlist(playlist.id))) tracks",
                            systemImage: "music.note.list",
                            item: .playlist(playlist.id)
                        )
                        .contextMenu {
                            Button("Play") { play(item: .playlist(playlist.id)) }
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
            } header: {
                EngravedLabel(text: "Playlists")
            }

            Section {
                if appModel.library.allArtists.isEmpty {
                    Text("No artists yet")
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .listRowBackground(HarborColor.faceplate)
                } else {
                    ForEach(appModel.library.allArtists, id: \.self) { artist in
                        sidebarRow(
                            title: artist,
                            subtitle: "\(trackCount(for: .artist(artist))) tracks",
                            systemImage: "person.wave.2",
                            item: .artist(artist)
                        )
                        .contextMenu {
                            Button("Play") { play(item: .artist(artist)) }
                        }
                    }
                }
            } header: {
                EngravedLabel(text: "Artists")
            }

            Section {
                if appModel.library.allLabels.isEmpty {
                    Text("Add labels from Catalogue (right‑click a track).")
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .listRowBackground(HarborColor.faceplate)
                } else {
                    ForEach(appModel.library.allLabels, id: \.self) { label in
                        sidebarRow(
                            title: label,
                            subtitle: "\(trackCount(for: .label(label))) tracks",
                            systemImage: "tag",
                            item: .label(label)
                        )
                        .contextMenu {
                            Button("Play") { play(item: .label(label)) }
                        }
                    }
                }
            } header: {
                EngravedLabel(text: "Labels")
            }

            Section {
                if appModel.library.allYears.isEmpty {
                    Text("No release years in metadata yet")
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .listRowBackground(HarborColor.faceplate)
                } else {
                    ForEach(appModel.library.allYears, id: \.self) { year in
                        sidebarRow(
                            title: String(year),
                            subtitle: "\(trackCount(for: .year(year))) tracks",
                            systemImage: "calendar",
                            item: .year(year)
                        )
                        .contextMenu {
                            Button("Play") { play(item: .year(year)) }
                        }
                    }
                }
            } header: {
                EngravedLabel(text: "Years")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
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
                    List {
                        ForEach(tracks) { track in
                            TrackRow(
                                track: track,
                                playlists: appModel.playlists.playlists.filter { !$0.isSmart },
                                onPlay: {
                                    appModel.playback.play(
                                        track: track,
                                        in: tracks,
                                        sourceName: detailTitle(for: selection),
                                        sourceKind: selection.kindLabel
                                    )
                                    appModel.selectedTab = .nowPlaying
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
                                knownLabels: appModel.library.allLabels
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
                Text("Choose a playlist, artist, label, or year on the left.")
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
        let all = appModel.library.allTracks
        switch item {
        case .playlist(let id):
            guard let playlist = appModel.playlists.playlists.first(where: { $0.id == id }) else { return [] }
            return appModel.playlists.tracks(for: playlist, from: all)
        case .artist(let name):
            return all
                .filter { $0.artist.caseInsensitiveCompare(name) == .orderedSame }
                .sorted {
                    if $0.album.localizedCaseInsensitiveCompare($1.album) != .orderedSame {
                        return $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending
                    }
                    return ($0.trackNumber ?? 9999) < ($1.trackNumber ?? 9999)
                }
        case .label(let name):
            return all
                .filter { track in
                    track.labels.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
                }
                .sorted {
                    $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
                }
        case .year(let year):
            return all
                .filter { $0.year == year }
                .sorted {
                    if $0.artist.localizedCaseInsensitiveCompare($1.artist) != .orderedSame {
                        return $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending
                    }
                    return $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending
                }
        }
    }

    private func trackCount(for item: PlaylistBrowserItem) -> Int {
        tracks(for: item).count
    }

    private func detailTitle(for item: PlaylistBrowserItem) -> String {
        switch item {
        case .playlist(let id):
            return appModel.playlists.playlists.first(where: { $0.id == id })?.name ?? "Playlist"
        case .artist(let name), .label(let name):
            return name
        case .year(let year):
            return String(year)
        }
    }

    private func navigationTitle(for item: PlaylistBrowserItem) -> String {
        detailTitle(for: item)
    }

    private func emptyDetailMessage(for item: PlaylistBrowserItem) -> String {
        switch item {
        case .playlist:
            return "Open Catalogue, right‑click a track, Add to Playlist."
        case .artist:
            return "No tracks for this artist in the catalogue."
        case .label:
            return "No tracks use this label yet."
        case .year:
            return "No tracks with this release year."
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
        let tracks = tracks(for: item)
        guard let first = tracks.first else { return }
        appModel.playback.play(
            track: first,
            in: tracks,
            sourceName: detailTitle(for: item),
            sourceKind: item.kindLabel
        )
        appModel.selectedTab = .nowPlaying
    }

    private func createManual() {
        appModel.playlists.createPlaylist(named: newName)
        newName = ""
    }
}

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct LibraryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isImporterPresented = false
    @State private var searchDraft = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var expandedAlbumID: UUID?
    @State private var expandedArtistName: String?
    @State private var folderPlaylistDraft = ""
    @State private var folderPlaylistTrack: Track?

    var body: some View {
        @Bindable var library = appModel.library

        ReceiverChassis {
            VStack(spacing: 14) {
                header
                modePicker($library.browseMode)
                searchBar($searchDraft, mode: library.browseMode)
                CatalogueScanBanner()
                Group {
                    switch library.browseMode {
                    case .smart:
                        if library.filteredAlbums.isEmpty {
                            emptyState
                        } else {
                            CatalogueAlbumList(expandedAlbumID: $expandedAlbumID)
                        }
                    case .artists:
                        if library.filteredArtistFacets.isEmpty {
                            emptyState
                        } else {
                            CatalogueArtistList(expandedArtistName: $expandedArtistName)
                        }
                    case .folders:
                        folderBrowser
                    }
                }
                .faceplate()
            }
        }
        .onAppear {
            searchDraft = appModel.library.searchQuery
        }
        .onChange(of: searchDraft) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                appModel.library.searchQuery = newValue
                expandedAlbumID = nil
                expandedArtistName = nil
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appModel.library.addFolders(urls: urls)
                if appModel.library.browseMode != .folders {
                    appModel.library.setBrowseMode(.folders)
                }
            }
        }
        .alert("New Playlist", isPresented: Binding(
            get: { folderPlaylistTrack != nil },
            set: { if !$0 { folderPlaylistTrack = nil } }
        )) {
            TextField("Name", text: $folderPlaylistDraft)
            Button("Cancel", role: .cancel) {
                folderPlaylistTrack = nil
            }
            Button("Create") {
                if let track = folderPlaylistTrack,
                   let playlist = appModel.playlists.createPlaylist(named: folderPlaylistDraft) {
                    appModel.playlists.add(track, to: playlist)
                }
                folderPlaylistTrack = nil
                folderPlaylistDraft = ""
            }
        }
        #if os(iOS)
        .navigationTitle("Catalogue")
        #endif
    }

    private var header: some View {
        ScreenHeader(
            title: "Catalogue",
            subtitle: catalogueSubtitle
        ) {
            HStack(spacing: 8) {
                HarborButton(
                    title: "Rebuild",
                    systemImage: "arrow.triangle.2.circlepath",
                    kind: .secondary,
                    action: { appModel.requestIndexRebuild() }
                )
                .disabled(appModel.library.isScanning || appModel.library.folders.isEmpty)
                .help("Rebuild the catalogue index from disk")

                HarborButton(
                    title: "Add Directory",
                    systemImage: "folder.badge.plus",
                    kind: .primary,
                    action: presentAddDirectory
                )
                .disabled(appModel.library.isScanning)
                .help("Connect a music directory to the catalogue")
            }
        }
    }

    private var catalogueSubtitle: String {
        if appModel.library.showsDemoLibrary {
            return "Demo library — add a directory to start."
        }
        if let status = appModel.library.indexStatusText {
            return "\(appModel.library.browseMode.title) — \(status)."
        }
        return "\(appModel.library.browseMode.title) — \(appModel.library.browseMode.subtitle.lowercased())."
    }

    private func presentAddDirectory() {
        #if os(macOS)
        appModel.library.addFolder()
        if appModel.library.browseMode != .folders {
            appModel.library.setBrowseMode(.folders)
        }
        #else
        isImporterPresented = true
        #endif
    }

    private func modePicker(_ mode: Binding<CatalogueBrowseMode>) -> some View {
        HStack(spacing: 6) {
            ForEach(CatalogueBrowseMode.allCases) { option in
                let selected = mode.wrappedValue == option
                Button {
                    appModel.library.setBrowseMode(option)
                } label: {
                    Text(option.title.uppercased())
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityLabel("Switch between directories, albums, and artists")
    }

    private func searchBar(_ query: Binding<String>, mode: CatalogueBrowseMode) -> some View {
        AluminumField {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HarborColor.ivoryDim)
                TextField(
                    searchPrompt(for: mode),
                    text: query
                )
                    .textFieldStyle(.plain)
                    .foregroundStyle(HarborColor.ivory)
            }
        }
        .padding(.horizontal, 4)
    }

    private func searchPrompt(for mode: CatalogueBrowseMode) -> String {
        switch mode {
        case .folders: "Find directories & files"
        case .smart: "Find album, artist, track"
        case .artists: "Find artist, album, track"
        }
    }

    @ViewBuilder
    private var folderBrowser: some View {
        if appModel.library.folders.isEmpty {
            emptyState
        } else if appModel.library.isFolderSearchActive {
            folderSearchResults
        } else if appModel.library.folderRootID == nil {
            folderRootsList
        } else {
            folderContentsList
        }
    }

    private var folderSearchResults: some View {
        VStack(spacing: 0) {
            HStack {
                Text(
                    appModel.library.folderRootID == nil
                        ? "Search across directories"
                        : "Search in \(appModel.library.folderBreadcrumb)"
                )
                .font(HarborFont.panel(10))
                .foregroundStyle(HarborColor.ivoryDim)
                Spacer()
                Text("\(appModel.library.folderSearchHits.count)")
                    .font(HarborFont.mono(11))
                    .foregroundStyle(HarborColor.amber)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(HarborColor.aluminumDark.opacity(0.5))

            if appModel.library.folderSearchHits.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No matches")
                        .font(HarborFont.title(16))
                        .foregroundStyle(HarborColor.ivory)
                    Text("Try another name, artist, or album.")
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appModel.library.folderSearchHits) { hit in
                        folderSearchHitRow(hit)
                            .listRowBackground(HarborColor.faceplate)
                            .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private func folderSearchHitRow(_ hit: FolderSearchHit) -> some View {
        switch hit.entry.kind {
        case .directory:
            directoryRow(
                title: hit.entry.name,
                subtitle: hit.relativePath,
                onOpen: {
                    searchDraft = ""
                    appModel.library.searchQuery = ""
                    appModel.library.revealInFolders(url: hit.entry.url)
                },
                onPlay: { playDirectory(hit.entry.url, name: hit.entry.name) }
            )

        case .audioFile:
            let track = appModel.library.trackForPlayback(at: hit.entry.url, identity: hit.entry.id)
            let folderName = hit.entry.url.deletingLastPathComponent().lastPathComponent
            HStack(spacing: 10) {
                Button {
                    playFolderOfHit(hit, startingAtHit: true)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .foregroundStyle(HarborColor.amber)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(HarborFont.title(14))
                                .foregroundStyle(HarborColor.ivory)
                                .lineLimit(1)
                            Text(hit.relativePath)
                                .font(HarborFont.body(11))
                                .foregroundStyle(HarborColor.ivoryDim)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        FormatBadge(
                            format: track.format,
                            sampleRateHz: track.sampleRateHz,
                            bitDepth: track.bitDepth
                        )
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HarborIconButton(
                    systemName: "play.square.stack",
                    help: "Play the whole \"\(folderName)\" folder from the top"
                ) {
                    playFolderOfHit(hit, startingAtHit: false)
                }
            }
            .contextMenu {
                Button("Play This Track First") {
                    playFolderOfHit(hit, startingAtHit: true)
                }
                Button("Play Folder “\(folderName)” from Start") {
                    playFolderOfHit(hit, startingAtHit: false)
                }
                Divider()
                Button("Reveal in Folders") {
                    searchDraft = ""
                    appModel.library.searchQuery = ""
                    appModel.library.revealInFolders(url: hit.entry.url)
                }
                Menu("Add to Playlist") {
                    Button("New Playlist…") {
                        folderPlaylistDraft = ""
                        folderPlaylistTrack = track
                    }
                    let manuals = appModel.playlists.playlists.filter { !$0.isSmart }
                    if !manuals.isEmpty {
                        Divider()
                        ForEach(manuals) { playlist in
                            Button(playlist.name) {
                                appModel.playlists.add(track, to: playlist)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Queue the folder holding the hit — either from the hit itself or from the folder's first track.
    private func playFolderOfHit(_ hit: FolderSearchHit, startingAtHit: Bool) {
        let playback = appModel.library.folderPlaybackQueue(
            startingAt: hit.entry.url,
            identity: hit.entry.id
        )
        guard let start = startingAtHit ? playback.track : playback.queue.first else { return }
        appModel.playback.play(
            track: start,
            in: playback.queue,
            sourceName: hit.entry.url.deletingLastPathComponent().lastPathComponent,
            sourceKind: "Folder"
        )
        appModel.selectedTab = .nowPlaying
    }

    private var folderRootsList: some View {
        List {
            Section {
                ForEach(appModel.library.filteredFolderRoots) { bookmark in
                    directoryRow(
                        title: bookmark.name,
                        subtitle: bookmark.displayPath,
                        onOpen: { appModel.library.openFolderRoot(bookmark) },
                        onPlay: {
                            if let url = appModel.library.accessibleFolderURLs[bookmark.id] {
                                playDirectory(url, name: bookmark.name)
                            }
                        }
                    )
                    .contextMenu {
                        Button("Play") {
                            if let url = appModel.library.accessibleFolderURLs[bookmark.id] {
                                playDirectory(url, name: bookmark.name)
                            }
                        }
                        Button("Remove Directory", role: .destructive) {
                            appModel.library.removeFolder(bookmark)
                        }
                    }
                    .listRowBackground(HarborColor.faceplate)
                }
            } header: {
                EngravedLabel(text: "Connected directories")
                    .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var folderContentsList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    appModel.library.folderGoUp()
                } label: {
                    Label("Up", systemImage: "chevron.left")
                        .font(HarborFont.panel(11))
                        .foregroundStyle(HarborColor.amber)
                }
                .buttonStyle(.plain)

                folderBreadcrumbs
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let url = appModel.library.folderBrowseURL {
                    HarborIconButton(systemName: "play.fill", help: "Play this directory") {
                        playDirectory(url, name: appModel.library.folderBreadcrumb)
                    }
                }

                Button("Directories") {
                    appModel.library.resetFolderBrowseToRoots()
                }
                .buttonStyle(.plain)
                .font(HarborFont.panel(11))
                .foregroundStyle(HarborColor.amber)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(HarborColor.aluminumDark.opacity(0.5))

            if appModel.library.folderListing.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("Empty folder")
                        .font(HarborFont.title(16))
                        .foregroundStyle(HarborColor.ivory)
                    Text("No subfolders or audio files here.")
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appModel.library.folderListing) { entry in
                        folderEntryRow(entry)
                            .listRowBackground(HarborColor.faceplate)
                            .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var folderBreadcrumbs: some View {
        let rootName = appModel.library.selectedFolderRoot?.name ?? "Directory"
        let components = appModel.library.folderPathComponents
        let currentDepth = components.count

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                breadcrumbButton(title: rootName, depth: 0, isCurrent: currentDepth == 0)

                ForEach(Array(components.enumerated()), id: \.offset) { index, name in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(HarborColor.ivoryDim.opacity(0.7))

                    let depth = index + 1
                    breadcrumbButton(title: name, depth: depth, isCurrent: depth == currentDepth)
                }
            }
        }
    }

    private func breadcrumbButton(title: String, depth: Int, isCurrent: Bool) -> some View {
        Button {
            appModel.library.navigateFolderBreadcrumb(depth: depth)
        } label: {
            Text(title)
                .font(HarborFont.body(12))
                .foregroundStyle(isCurrent ? HarborColor.ivory : HarborColor.amber)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }

    @ViewBuilder
    private func folderEntryRow(_ entry: FolderBrowseEntry) -> some View {
        switch entry.kind {
        case .directory:
            directoryRow(
                title: entry.name,
                subtitle: nil,
                onOpen: { appModel.library.enterFolder(entry) },
                onPlay: { playDirectory(entry.url, name: entry.name) }
            )
            .contextMenu {
                Button("Play") { playDirectory(entry.url, name: entry.name) }
            }

        case .audioFile:
            let track = appModel.library.trackForPlayback(at: entry.url, identity: entry.id)
            TrackRow(
                track: track,
                playlists: appModel.playlists.playlists,
                onPlay: {
                    let playback = appModel.library.folderPlaybackQueue(startingAt: entry.url, identity: entry.id)
                    let folderName = entry.url.deletingLastPathComponent().lastPathComponent
                    appModel.playback.play(
                        track: playback.track,
                        in: playback.queue,
                        sourceName: folderName,
                        sourceKind: "Folder"
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
        }
    }

    private func directoryRow(
        title: String,
        subtitle: String?,
        onOpen: @escaping () -> Void,
        onPlay: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(HarborColor.amber)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(HarborFont.title(14))
                            .foregroundStyle(HarborColor.ivory)
                            .lineLimit(1)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(HarborFont.body(11))
                                .foregroundStyle(HarborColor.ivoryDim)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HarborColor.ivoryDim)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HarborIconButton(systemName: "play.fill", help: "Play this directory", action: onPlay)
        }
    }

    private func playDirectory(_ url: URL, name: String) {
        guard let playback = appModel.library.directoryPlaybackQueue(at: url) else { return }
        appModel.playback.play(
            track: playback.track,
            in: playback.queue,
            sourceName: name,
            sourceKind: "Folder"
        )
        appModel.selectedTab = .nowPlaying
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            EngravedLabel(text: "No directories")
            Text("No music yet")
                .font(HarborFont.display(24))
                .foregroundStyle(HarborColor.ivory)
            Text("Add a music directory to fill the catalogue.")
                .font(HarborFont.body(14))
                .foregroundStyle(HarborColor.ivoryDim)
                .multilineTextAlignment(.center)
            HarborButton(
                title: "Add Directory",
                systemImage: "folder.badge.plus",
                kind: .primary,
                action: presentAddDirectory
            )
            .disabled(appModel.library.isScanning)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private struct CatalogueScanBanner: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let progress = appModel.library.scanProgressText {
            Text(progress)
                .font(HarborFont.mono(11))
                .foregroundStyle(HarborColor.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
    }
}

private struct CatalogueAlbumList: View {
    @Environment(AppModel.self) private var appModel
    @Binding var expandedAlbumID: UUID?

    var body: some View {
        let playlists = appModel.playlists.playlists
        let labels = appModel.library.allLabels
        List {
            ForEach(appModel.library.filteredAlbums) { album in
                let isExpanded = expandedAlbumID == album.id
                let tracks = appModel.library.visibleTracks(in: album)
                albumHeader(album, trackCount: tracks.count, isExpanded: isExpanded)
                    .listRowBackground(HarborColor.faceplate)
                    .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
                if isExpanded {
                    ForEach(tracks) { track in
                        TrackRow(
                            track: track,
                            playlists: playlists,
                            onPlay: {
                                appModel.playback.play(
                                    track: track,
                                    in: album.tracks,
                                    sourceName: album.title,
                                    sourceKind: "Album"
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
                            knownLabels: labels
                        )
                        .listRowBackground(HarborColor.faceplate)
                        .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
                        .padding(.leading, 12)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func albumHeader(_ album: Album, trackCount: Int, isExpanded: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedAlbumID = isExpanded ? nil : album.id
                }
            } label: {
                HStack(spacing: 12) {
                    HarborArtwork(hash: album.artworkHash, data: album.artworkData, size: 56, corner: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.title)
                            .font(HarborFont.title(15))
                            .foregroundStyle(HarborColor.ivory)
                            .lineLimit(1)
                        Text(album.artist)
                            .font(HarborFont.body(12))
                            .foregroundStyle(HarborColor.brass)
                        Text(trackCount == 1 ? "1 track" : "\(trackCount) tracks")
                            .font(HarborFont.body(11))
                            .foregroundStyle(HarborColor.ivoryDim)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HarborIconButton(systemName: "play.fill", help: "Play album") {
                guard let first = album.tracks.first else { return }
                appModel.playback.play(
                    track: first,
                    in: album.tracks,
                    sourceName: album.title,
                    sourceKind: "Album"
                )
                appModel.selectedTab = .nowPlaying
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CatalogueArtistList: View {
    @Environment(AppModel.self) private var appModel
    @Binding var expandedArtistName: String?

    var body: some View {
        let playlists = appModel.playlists.playlists
        let labels = appModel.library.allLabels
        List {
            ForEach(appModel.library.filteredArtistFacets) { facet in
                let isExpanded = expandedArtistName == facet.name
                let tracks = appModel.library.visibleTracks(forArtist: facet.name)
                artistHeader(facet, trackCount: tracks.count, isExpanded: isExpanded)
                    .listRowBackground(HarborColor.faceplate)
                    .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
                if isExpanded {
                    ForEach(tracks) { track in
                        TrackRow(
                            track: track,
                            playlists: playlists,
                            onPlay: {
                                appModel.playback.play(
                                    track: track,
                                    in: tracks,
                                    sourceName: facet.name,
                                    sourceKind: "Artist"
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
                            knownLabels: labels
                        )
                        .listRowBackground(HarborColor.faceplate)
                        .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
                        .padding(.leading, 12)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func artistHeader(_ facet: LibraryFacet, trackCount: Int, isExpanded: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedArtistName = isExpanded ? nil : facet.name
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(HarborColor.amber)
                        .frame(width: 56, height: 56)
                        .background(HarborColor.faceplateLift)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(facet.name)
                            .font(HarborFont.title(15))
                            .foregroundStyle(HarborColor.ivory)
                            .lineLimit(1)
                        Text(trackCount == 1 ? "1 track" : "\(trackCount) tracks")
                            .font(HarborFont.body(11))
                            .foregroundStyle(HarborColor.ivoryDim)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HarborIconButton(systemName: "play.fill", help: "Play artist") {
                let tracks = appModel.library.visibleTracks(forArtist: facet.name)
                guard let first = tracks.first else { return }
                appModel.playback.play(
                    track: first,
                    in: tracks,
                    sourceName: facet.name,
                    sourceKind: "Artist"
                )
                appModel.selectedTab = .nowPlaying
            }
        }
        .padding(.vertical, 4)
    }
}

struct TrackRow: View {
    @Environment(AppModel.self) private var appModel
    let track: Track
    var playlists: [Playlist] = []
    let onPlay: () -> Void
    var onAddToPlaylist: ((Playlist) -> Void)?
    var onAddLabel: ((String) -> Void)?
    var onRemoveLabel: ((String) -> Void)?
    var knownLabels: [String] = []
    @State private var newLabelDraft = ""
    @State private var showNewLabelAlert = false
    @State private var newPlaylistDraft = ""
    @State private var showNewPlaylistAlert = false

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(HarborFont.title(14))
                        .foregroundStyle(HarborColor.ivory)
                        .lineLimit(1)
                    Text(durationArtistLine)
                        .font(HarborFont.body(12))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .lineLimit(1)
                    if !track.labels.isEmpty {
                        Text(track.labels.joined(separator: " · "))
                            .font(HarborFont.panel(10))
                            .foregroundStyle(HarborColor.amber.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                Spacer()
                FormatBadge(
                    format: track.format,
                    sampleRateHz: track.sampleRateHz,
                    bitDepth: track.bitDepth
                )
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onAddToPlaylist {
                let manual = playlists.filter { !$0.isSmart }
                Menu("Add to Playlist") {
                    Button("New Playlist…") {
                        newPlaylistDraft = ""
                        showNewPlaylistAlert = true
                    }
                    if !manual.isEmpty {
                        Divider()
                        ForEach(manual) { playlist in
                            Button(playlist.name) {
                                onAddToPlaylist(playlist)
                            }
                        }
                    }
                }
            }
            if onAddLabel != nil || onRemoveLabel != nil {
                Menu("Labels") {
                    Button("New Label…") {
                        newLabelDraft = ""
                        showNewLabelAlert = true
                    }
                    if !mergedLabelSuggestions.isEmpty {
                        Divider()
                        ForEach(mergedLabelSuggestions, id: \.self) { label in
                            let hasLabel = track.labels.contains {
                                $0.caseInsensitiveCompare(label) == .orderedSame
                            }
                            Button {
                                if hasLabel {
                                    onRemoveLabel?(label)
                                } else {
                                    onAddLabel?(label)
                                }
                            } label: {
                                if hasLabel {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Name", text: $newPlaylistDraft)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                onCreatePlaylistFromContext()
            }
        }
        .alert("New Label", isPresented: $showNewLabelAlert) {
            TextField("Label", text: $newLabelDraft)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                onAddLabel?(newLabelDraft)
            }
        }
    }

    private var mergedLabelSuggestions: [String] {
        Array(Set(knownLabels + track.labels))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var durationArtistLine: String {
        var parts: [String] = [track.artist]
        if let year = track.year {
            parts.append(String(year))
        }
        if track.duration > 0 {
            let total = Int(track.duration)
            parts.append("\(total / 60):\(String(format: "%02d", total % 60))")
        }
        return parts.joined(separator: " · ")
    }

    private func onCreatePlaylistFromContext() {
        guard let playlist = appModel.playlists.createPlaylist(named: newPlaylistDraft) else { return }
        onAddToPlaylist?(playlist)
        newPlaylistDraft = ""
    }
}

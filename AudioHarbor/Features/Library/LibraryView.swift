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

    var body: some View {
        @Bindable var library = appModel.library

        ReceiverChassis {
            VStack(spacing: 14) {
                header
                modePicker($library.browseMode)
                searchBar($library.searchQuery, mode: library.browseMode)
                if let progress = library.scanProgressText {
                    Text(progress)
                        .font(HarborFont.mono(11))
                        .foregroundStyle(HarborColor.amber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
                Group {
                    switch library.browseMode {
                    case .smart:
                        if library.filteredAlbums.isEmpty {
                            emptyState
                        } else {
                            albumList
                        }
                    case .folders:
                        folderBrowser
                    }
                }
                .faceplate()
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
        #if os(iOS)
        .navigationTitle("Catalogue")
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                BrandMark(compact: true)
                Text(appModel.library.showsDemoLibrary
                     ? "Demo library — add a directory to start."
                     : appModel.library.browseMode == .smart
                        ? "Smart catalogue — albums & metadata search."
                        : "Directories — walk your music as it sits on disk.")
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.ivoryDim)
                EngravedLabel(text: "Catalogue")
            }
            Spacer(minLength: 8)
            Button(action: presentAddDirectory) {
                Label("Add Directory", systemImage: "folder.badge.plus")
                    .font(HarborFont.title(13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(HarborColor.amber)
                    .foregroundStyle(HarborColor.faceplate)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(appModel.library.isScanning)
            .help("Connect a music directory to the catalogue")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        Picker("Browse mode", selection: mode) {
            ForEach(CatalogueBrowseMode.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 4)
        .onChange(of: mode.wrappedValue) { _, newValue in
            appModel.library.setBrowseMode(newValue)
        }
    }

    private func searchBar(_ query: Binding<String>, mode: CatalogueBrowseMode) -> some View {
        AluminumField {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HarborColor.ivoryDim)
                TextField(
                    mode == .smart
                        ? "Find album, artist, track"
                        : "Find directories & files",
                    text: query
                )
                    .textFieldStyle(.plain)
                    .foregroundStyle(HarborColor.ivory)
            }
        }
        .padding(.horizontal, 4)
    }

    private var albumList: some View {
        List {
            ForEach(appModel.library.filteredAlbums) { album in
                Section {
                    ForEach(album.tracks) { track in
                        TrackRow(
                            track: track,
                            playlists: appModel.playlists.playlists,
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
                            knownLabels: appModel.library.allLabels
                        )
                        .listRowBackground(HarborColor.faceplate)
                        .listRowSeparatorTint(HarborColor.aluminumDark.opacity(0.5))
                    }
                } header: {
                    HStack(spacing: 12) {
                        artworkThumb(album.artworkData)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title)
                                .font(HarborFont.title(15))
                                .foregroundStyle(HarborColor.ivory)
                            Text(album.artist.uppercased())
                                .font(HarborFont.panel(10))
                                .tracking(1.2)
                                .foregroundStyle(HarborColor.amber)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
            Button {
                appModel.library.searchQuery = ""
                appModel.library.revealInFolders(url: hit.entry.url)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(HarborColor.amber)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hit.entry.name)
                            .font(HarborFont.title(14))
                            .foregroundStyle(HarborColor.ivory)
                            .lineLimit(1)
                        Text(hit.relativePath)
                            .font(HarborFont.body(11))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HarborColor.ivoryDim)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case .audioFile:
            let track = appModel.library.trackForPlayback(at: hit.entry.url)
            Button {
                let playback = appModel.library.folderPlaybackQueue(startingAt: hit.entry.url)
                let folderName = hit.entry.url.deletingLastPathComponent().lastPathComponent
                appModel.playback.play(
                    track: playback.track,
                    in: playback.queue,
                    sourceName: folderName,
                    sourceKind: "Folder"
                )
                appModel.selectedTab = .nowPlaying
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
                    Spacer()
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
            .contextMenu {
                Button("Reveal in Folders") {
                    appModel.library.searchQuery = ""
                    appModel.library.revealInFolders(url: hit.entry.url)
                }
                if !appModel.playlists.playlists.isEmpty {
                    Menu("Add to Playlist") {
                        ForEach(appModel.playlists.playlists) { playlist in
                            Button(playlist.name) {
                                appModel.playlists.add(track, to: playlist)
                            }
                        }
                    }
                }
            }
        }
    }

    private var folderRootsList: some View {
        List {
            Section {
                Button(action: presentAddDirectory) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(HarborColor.faceplate)
                            .frame(width: 28, height: 28)
                            .background(HarborColor.amber)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Add Directory")
                                .font(HarborFont.title(14))
                                .foregroundStyle(HarborColor.ivory)
                            Text("Connect another music folder to browse and play.")
                                .font(HarborFont.body(11))
                                .foregroundStyle(HarborColor.ivoryDim)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(appModel.library.isScanning)
                .listRowBackground(HarborColor.faceplate)
            }

            Section {
                ForEach(appModel.library.filteredFolderRoots) { bookmark in
                    Button {
                        appModel.library.openFolderRoot(bookmark)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(HarborColor.amber)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bookmark.name)
                                    .font(HarborFont.title(14))
                                    .foregroundStyle(HarborColor.ivory)
                                Text(bookmark.displayPath)
                                    .font(HarborFont.body(11))
                                    .foregroundStyle(HarborColor.ivoryDim)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HarborColor.ivoryDim)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
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
            Button {
                appModel.library.enterFolder(entry)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(HarborColor.amber)
                        .frame(width: 22)
                    Text(entry.name)
                        .font(HarborFont.title(14))
                        .foregroundStyle(HarborColor.ivory)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HarborColor.ivoryDim)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case .audioFile:
            let track = appModel.library.trackForPlayback(at: entry.url)
            TrackRow(
                track: track,
                playlists: appModel.playlists.playlists,
                onPlay: {
                    let playback = appModel.library.folderPlaybackQueue(startingAt: entry.url)
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
            Button(action: presentAddDirectory) {
                Label("Add Directory", systemImage: "folder.badge.plus")
                    .font(HarborFont.title(14))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(HarborColor.amber)
                    .foregroundStyle(HarborColor.faceplate)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(appModel.library.isScanning)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func artworkThumb(_ data: Data?) -> some View {
        Group {
            if let data, let image = makeImage(data) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(HarborColor.aluminumDark)
                    .overlay {
                        Image(systemName: "opticaldisc")
                            .foregroundStyle(HarborColor.ivoryDim)
                    }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(HarborColor.aluminumDark, lineWidth: 1)
        )
    }

    private func makeImage(_ data: Data) -> Image? {
        #if os(macOS)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #else
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #endif
        return nil
    }
}

struct TrackRow: View {
    let track: Track
    var playlists: [Playlist] = []
    let onPlay: () -> Void
    var onAddToPlaylist: ((Playlist) -> Void)?
    var onAddLabel: ((String) -> Void)?
    var onRemoveLabel: ((String) -> Void)?
    var knownLabels: [String] = []
    @State private var newLabelDraft = ""
    @State private var showNewLabelAlert = false

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
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onAddToPlaylist {
                let manual = playlists.filter { !$0.isSmart }
                if !manual.isEmpty {
                    Menu("Add to Playlist") {
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
                    Divider()
                    Button("New Label…") {
                        newLabelDraft = ""
                        showNewLabelAlert = true
                    }
                }
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
}

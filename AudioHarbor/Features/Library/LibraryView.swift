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
    @State private var model: LibraryViewModel

    init(appModel: AppModel) {
        _model = State(initialValue: LibraryViewModel(app: appModel))
    }

    var body: some View {
        @Bindable var library = appModel.library

        ReceiverChassis {
            VStack(spacing: 14) {
                header
                modePicker($library.browseMode)
                searchBar($model.searchDraft, mode: library.browseMode)
                CatalogueScanBanner()
                Group {
                    switch library.browseMode {
                    case .smart:
                        if library.filteredAlbums.isEmpty {
                            emptyState
                        } else {
                            CatalogueAlbumList(model: model)
                        }
                    case .artists:
                        if library.filteredArtistFacets.isEmpty {
                            emptyState
                        } else {
                            CatalogueArtistList(model: model)
                        }
                    case .folders:
                        folderBrowser
                    }
                }
                .faceplate()
            }
        }
        .fileImporter(
            isPresented: $model.isDirectoryImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.addDirectories(urls)
            }
        }
        #if os(iOS)
        .navigationTitle("Catalogue")
        #endif
    }

    private var header: some View {
        ScreenHeader(
            title: "Catalogue",
            subtitle: model.subtitle
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
                    action: model.addDirectory
                )
                .disabled(appModel.library.isScanning)
                .help("Connect a music directory to the catalogue")
            }
        }
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
        } else if appModel.library.folderNavigation.rootID == nil {
            folderRootsList
        } else {
            folderContentsList
        }
    }

    private var folderSearchResults: some View {
        VStack(spacing: 0) {
            HStack {
                Text(
                    appModel.library.folderNavigation.rootID == nil
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
                EmptyPanel(title: "No matches", message: "Try another name, artist, or album.")
            } else {
                List {
                    ForEach(appModel.library.folderSearchHits) { hit in
                        folderSearchHitRow(hit)
                            .harborListRow()
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
                onOpen: { model.reveal(hit.entry.url) },
                onPlay: { model.playDirectory(hit.entry.url, name: hit.entry.name) }
            )

        case .audioFile(let track):
            let folderName = hit.entry.url.deletingLastPathComponent().lastPathComponent
            HStack(spacing: 10) {
                Button {
                    model.playFolder(containing: hit.entry)
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
                    model.playFolder(containing: hit.entry, startingAtEntry: false)
                }
            }
            .trackContextMenu(for: track, includesLabels: false) {
                Button("Play This Track First") {
                    model.playFolder(containing: hit.entry)
                }
                Button("Play Folder “\(folderName)” from Start") {
                    model.playFolder(containing: hit.entry, startingAtEntry: false)
                }
                Divider()
                Button("Reveal in Folders") {
                    model.reveal(hit.entry.url)
                }
            }
        }
    }

    private var folderRootsList: some View {
        List {
            Section {
                ForEach(appModel.library.filteredFolderRoots) { bookmark in
                    directoryRow(
                        title: bookmark.name,
                        subtitle: bookmark.displayPath,
                        onOpen: { appModel.library.openFolderRoot(bookmark) },
                        onPlay: { model.playRoot(bookmark) }
                    )
                    .contextMenu {
                        Button("Play") { model.playRoot(bookmark) }
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
                        model.playDirectory(url, name: appModel.library.folderBreadcrumb)
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
                EmptyPanel(title: "Empty folder", message: "No subfolders or audio files here.")
            } else {
                List {
                    ForEach(appModel.library.folderListing) { entry in
                        folderEntryRow(entry)
                            .harborListRow()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var folderBreadcrumbs: some View {
        let rootName = appModel.library.selectedFolderRoot?.name ?? "Directory"
        let components = appModel.library.folderNavigation.pathComponents
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
                onPlay: { model.playDirectory(entry.url, name: entry.name) }
            )
            .contextMenu {
                Button("Play") { model.playDirectory(entry.url, name: entry.name) }
            }

        case .audioFile(let track):
            TrackRow(track: track) { model.playFolder(containing: entry) }
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
                action: model.addDirectory
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
    let model: LibraryViewModel

    var body: some View {
        List {
            ForEach(appModel.library.filteredAlbums) { album in
                ExpandableTrackGroup(
                    title: album.title,
                    subtitle: album.artist,
                    tracks: appModel.library.visibleTracks(in: album),
                    isExpanded: model.expandedAlbumID == album.id,
                    playHelp: "Play album",
                    onToggle: { model.toggleAlbum(album) },
                    onPlay: { model.playAlbum(album, startingAt: $0) }
                ) {
                    HarborArtwork(hash: album.artworkHash, data: album.artworkData, size: 56, corner: 8)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct CatalogueArtistList: View {
    @Environment(AppModel.self) private var appModel
    let model: LibraryViewModel

    var body: some View {
        List {
            ForEach(appModel.library.filteredArtistFacets) { facet in
                ExpandableTrackGroup(
                    title: facet.name,
                    tracks: appModel.library.visibleTracks(forArtist: facet.name),
                    isExpanded: model.expandedArtistName == facet.name,
                    playHelp: "Play artist",
                    onToggle: { model.toggleArtist(facet.name) },
                    onPlay: { model.playArtist(facet.name, startingAt: $0) }
                ) {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(HarborColor.amber)
                        .frame(width: 56, height: 56)
                        .background(HarborColor.faceplateLift)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

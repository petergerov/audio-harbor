import SwiftUI

/// A playable track line: title, artist · year · length, labels and format badge.
/// The loaded track is marked, since playing no longer leaves the list.
/// Right-click offers Play and Show Deck, Add to Playlist and Labels.
struct TrackRow: View {
    @Environment(AppModel.self) private var appModel
    let track: Track
    let onPlay: () -> Void

    var body: some View {
        let isCurrent = appModel.playback.currentTrack?.cataloguePath == track.cataloguePath
        Button(action: onPlay) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isCurrent {
                            Image(systemName: appModel.playback.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(HarborColor.amber)
                        }
                        Text(track.title)
                            .font(HarborFont.title(14))
                            .foregroundStyle(isCurrent ? HarborColor.amber : HarborColor.ivory)
                            .lineLimit(1)
                    }
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
        .trackContextMenu(for: track) {
            Button("Play and Show Deck") {
                onPlay()
                appModel.showDeck()
            }
            Divider()
        }
    }

    private var durationArtistLine: String {
        var parts: [String] = [track.artist]
        if let year = track.year {
            parts.append(String(year))
        }
        if track.duration > 0 {
            parts.append(track.duration.clockText)
        }
        return parts.joined(separator: " · ")
    }
}

extension View {
    /// Adds the shared track context menu: `leading` items first, then Add to Playlist and,
    /// if `includesLabels`, Labels. The "New Playlist…" / "New Label…" prompts come with it.
    func trackContextMenu<Leading: View>(
        for track: Track,
        includesLabels: Bool = true,
        @ViewBuilder leading: () -> Leading = { EmptyView() }
    ) -> some View {
        tracksContextMenu(includesLabels: includesLabels, tracks: { [track] }, leading: leading)
    }

    /// The same menu for a group — a directory, an album, an artist. `tracks` is resolved
    /// only when the menu opens or an item runs, so long lists stay cheap.
    func tracksContextMenu<Leading: View, Trailing: View>(
        includesLabels: Bool = true,
        tracks: @escaping () -> [Track],
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(TrackContextMenu(
            tracks: tracks,
            includesLabels: includesLabels,
            leading: leading(),
            trailing: trailing()
        ))
    }
}

private struct TrackContextMenu<Leading: View, Trailing: View>: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let tracks: () -> [Track]
    let includesLabels: Bool
    let leading: Leading
    let trailing: Trailing

    @State private var isNamingPlaylist = false
    @State private var newPlaylistName = ""
    @State private var isNamingLabel = false
    @State private var newLabel = ""

    func body(content: Content) -> some View {
        content
            .contextMenu {
                leading
                TrackMenuItems(
                    tracks: tracks,
                    includesLabels: includesLabels,
                    onNewPlaylist: {
                        newPlaylistName = ""
                        isNamingPlaylist = true
                    },
                    onNewLabel: {
                        newLabel = ""
                        isNamingLabel = true
                    }
                )
                trailing
            }
            .alert("New Playlist", isPresented: $isNamingPlaylist) {
                TextField("Name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    if let playlist = appModel.playlists.createPlaylist(named: newPlaylistName) {
                        appModel.playlists.add(tracks(), to: playlist)
                    }
                    newPlaylistName = ""
                }
            }
            .alert("New Label", isPresented: $isNamingLabel) {
                TextField("Label", text: $newLabel)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    appModel.library.addLabel(newLabel, to: tracks())
                }
            }
    }
}

/// Add to Playlist and Labels. A separate view so `tracks` resolves when the menu is built,
/// not on every redraw of the row it hangs on.
private struct TrackMenuItems: View {
    @Environment(AppModel.self) private var appModel
    let tracks: () -> [Track]
    let includesLabels: Bool
    let onNewPlaylist: () -> Void
    let onNewLabel: () -> Void

    var body: some View {
        let tracks = tracks()
        playlistMenu(tracks)
            .disabled(tracks.isEmpty)
        if includesLabels {
            labelsMenu(tracks)
                .disabled(tracks.isEmpty)
        }
    }

    private func playlistMenu(_ tracks: [Track]) -> some View {
        Menu("Add to Playlist") {
            Button("New Playlist…", action: onNewPlaylist)
            let manual = appModel.playlists.playlists.filter { !$0.isSmart }
            if !manual.isEmpty {
                Divider()
                ForEach(manual) { playlist in
                    Button(playlist.name) {
                        appModel.playlists.add(tracks, to: playlist)
                    }
                }
            }
        }
    }

    private func labelsMenu(_ tracks: [Track]) -> some View {
        Menu("Labels") {
            Button("New Label…", action: onNewLabel)
            let suggestions = labelSuggestions(tracks)
            if !suggestions.isEmpty {
                Divider()
                ForEach(suggestions, id: \.self) { label in
                    // Checked when every track carries it; choosing it then clears it from all.
                    let everyTrackHasIt = tracks.allSatisfy { track in
                        track.labels.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
                    }
                    Button {
                        if everyTrackHasIt {
                            appModel.library.removeLabel(label, from: tracks)
                        } else {
                            appModel.library.addLabel(label, to: tracks)
                        }
                    } label: {
                        if everyTrackHasIt {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }
        }
    }

    /// Every label in the catalogue plus the tracks' own, alphabetically.
    private func labelSuggestions(_ tracks: [Track]) -> [String] {
        Array(Set(appModel.library.allLabels + tracks.flatMap(\.labels)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

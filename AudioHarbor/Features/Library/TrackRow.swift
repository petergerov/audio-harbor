import SwiftUI

/// A playable track line: title, artist · year · length, labels and format badge.
/// Right-click offers Add to Playlist and Labels.
struct TrackRow: View {
    let track: Track
    let onPlay: () -> Void

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
        .trackContextMenu(for: track)
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
        modifier(TrackContextMenu(track: track, includesLabels: includesLabels, leading: leading()))
    }
}

private struct TrackContextMenu<Leading: View>: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let track: Track
    let includesLabels: Bool
    let leading: Leading

    @State private var isNamingPlaylist = false
    @State private var newPlaylistName = ""
    @State private var isNamingLabel = false
    @State private var newLabel = ""

    func body(content: Content) -> some View {
        content
            .contextMenu {
                leading
                playlistMenu
                if includesLabels {
                    labelsMenu
                }
            }
            .alert("New Playlist", isPresented: $isNamingPlaylist) {
                TextField("Name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    if let playlist = appModel.playlists.createPlaylist(named: newPlaylistName) {
                        appModel.playlists.add(track, to: playlist)
                    }
                    newPlaylistName = ""
                }
            }
            .alert("New Label", isPresented: $isNamingLabel) {
                TextField("Label", text: $newLabel)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    appModel.library.addLabel(newLabel, to: track)
                }
            }
    }

    private var playlistMenu: some View {
        Menu("Add to Playlist") {
            Button("New Playlist…") {
                newPlaylistName = ""
                isNamingPlaylist = true
            }
            let manual = appModel.playlists.playlists.filter { !$0.isSmart }
            if !manual.isEmpty {
                Divider()
                ForEach(manual) { playlist in
                    Button(playlist.name) {
                        appModel.playlists.add(track, to: playlist)
                    }
                }
            }
        }
    }

    private var labelsMenu: some View {
        Menu("Labels") {
            Button("New Label…") {
                newLabel = ""
                isNamingLabel = true
            }
            let suggestions = labelSuggestions
            if !suggestions.isEmpty {
                Divider()
                ForEach(suggestions, id: \.self) { label in
                    let hasLabel = track.labels.contains {
                        $0.caseInsensitiveCompare(label) == .orderedSame
                    }
                    Button {
                        if hasLabel {
                            appModel.library.removeLabel(label, from: track)
                        } else {
                            appModel.library.addLabel(label, to: track)
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

    /// Every label in the catalogue plus this track's own, alphabetically.
    private var labelSuggestions: [String] {
        Array(Set(appModel.library.allLabels + track.labels))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

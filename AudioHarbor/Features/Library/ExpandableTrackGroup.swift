import SwiftUI

/// A list header for a group of tracks (an album, an artist) that expands in place to show
/// them. Produces several list rows: the header, then one per track while expanded.
struct ExpandableTrackGroup<Thumbnail: View>: View {
    let title: String
    var subtitle: String?
    let tracks: [Track]
    let isExpanded: Bool
    /// Help text for the play button, e.g. "Play album".
    let playHelp: String
    let onToggle: () -> Void
    /// Plays the group, from `track` or (when `nil`) from the start.
    let onPlay: (_ track: Track?) -> Void
    @ViewBuilder let thumbnail: Thumbnail

    var body: some View {
        header
            .harborListRow()
        if isExpanded {
            ForEach(tracks) { track in
                TrackRow(track: track) { onPlay(track) }
                    .harborListRow()
                    .padding(.leading, 12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15), onToggle)
            } label: {
                HStack(spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(HarborFont.title(15))
                            .foregroundStyle(HarborColor.ivory)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(HarborFont.body(12))
                                .foregroundStyle(HarborColor.brass)
                        }
                        Text(tracks.count == 1 ? "1 track" : "\(tracks.count) tracks")
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

            HarborIconButton(systemName: "play.fill", help: playHelp) {
                onPlay(nil)
            }
        }
        .padding(.vertical, 4)
    }
}

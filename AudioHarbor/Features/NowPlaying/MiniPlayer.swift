import SwiftUI

/// Compact player for the row under a screen's title, next to its mode switches.
/// Shows nothing until a track is loaded. Tapping the track opens the Deck.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let playback = appModel.playback
        ZStack {
            if let track = playback.currentTrack {
                content(track, playback: playback)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: playback.currentTrack != nil)
    }

    private func content(_ track: Track, playback: PlaybackService) -> some View {
        HStack(spacing: 8) {
            Button {
                appModel.selectedTab = .nowPlaying
            } label: {
                HStack(spacing: 8) {
                    HarborArtwork(hash: track.artworkHash, data: track.artworkData, size: 26, corner: 4)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(track.title)
                            .font(HarborFont.title(12))
                            .foregroundStyle(HarborColor.ivory)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(HarborFont.body(10))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the Deck")

            HStack(spacing: 2) {
                control("backward.fill", label: "Previous track") { playback.playPrevious() }
                control(
                    playback.isPlaying ? "pause.fill" : "play.fill",
                    label: playback.isPlaying ? "Pause" : "Play",
                    isPrimary: true
                ) {
                    playback.togglePlayPause()
                }
                control("forward.fill", label: "Next track") { playback.playNext() }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .background(alignment: .bottom) {
            PlaybackProgressLine(playback: playback)
                .padding(.horizontal, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HarborColor.faceplate.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(HarborColor.aluminumDark, lineWidth: 1)
                )
        )
        .frame(maxWidth: 340)
    }

    private func control(
        _ systemName: String,
        label: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isPrimary ? 11 : 9, weight: .bold))
                .foregroundStyle(isPrimary ? HarborColor.chassis : HarborColor.ivoryDim)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isPrimary ? HarborColor.amber : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Hairline of how far the track has played. Its own view, so the 20 Hz time updates
/// redraw only this line.
private struct PlaybackProgressLine: View {
    let playback: PlaybackService

    var body: some View {
        let ratio = playback.duration > 0
            ? min(max(playback.currentTime / playback.duration, 0), 1)
            : 0
        GeometryReader { geo in
            Capsule()
                .fill(HarborColor.amber.opacity(0.8))
                .frame(width: geo.size.width * ratio)
        }
        .frame(height: 1.5)
    }
}

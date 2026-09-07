import SwiftUI

/// Compact queue / album context beside the Deck — highlights and scrolls to the current track.
struct DeckContextRail: View {
    @Environment(AppModel.self) private var appModel
    var onClose: (() -> Void)?

    private var playback: PlaybackService { appModel.playback }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(HarborColor.aluminumDark.opacity(0.55))
            if playback.queue.isEmpty {
                emptyState
            } else {
                queueList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HarborColor.faceplate)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                EngravedLabel(text: playback.queueSourceKind)
                Text(contextTitle)
                    .font(HarborFont.title(14))
                    .foregroundStyle(HarborColor.ivory)
                    .lineLimit(2)
                if let subtitle = contextSubtitle {
                    Text(subtitle)
                        .font(HarborFont.panel(10))
                        .tracking(0.8)
                        .foregroundStyle(HarborColor.amber)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HarborColor.ivoryDim)
                }
                .buttonStyle(.plain)
                .help("Hide context")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var contextTitle: String {
        if let name = playback.queueSourceName, !name.isEmpty {
            return name
        }
        if let album = playback.currentTrack?.album, !album.isEmpty {
            return album
        }
        return playback.queue.isEmpty ? "No queue" : "Queue"
    }

    private var contextSubtitle: String? {
        if playback.queueSourceKind == "Playlist" {
            return "\(playback.queue.count) tracks"
        }
        guard let artist = playback.currentTrack?.artist, !artist.isEmpty else {
            guard !playback.queue.isEmpty else { return nil }
            return "\(playback.queue.count) tracks"
        }
        return "\(artist.uppercased()) · \(playback.queue.count)"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Nothing queued")
                .font(HarborFont.title(14))
                .foregroundStyle(HarborColor.ivory)
            Text("Play something from Catalogue or Playlists.")
                .font(HarborFont.body(12))
                .foregroundStyle(HarborColor.ivoryDim)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queueList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(playback.queue.enumerated()), id: \.element.id) { index, track in
                        DeckContextRow(
                            index: index,
                            track: track,
                            isCurrent: index == playback.queueIndex,
                            isPlaying: index == playback.queueIndex && playback.isPlaying
                        ) {
                            playback.playQueueItem(at: index)
                        }
                        .id(track.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                scrollToCurrent(proxy)
            }
            .onChange(of: playback.queueIndex) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    scrollToCurrent(proxy)
                }
            }
            .onChange(of: playback.currentTrack?.id) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    scrollToCurrent(proxy)
                }
            }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard playback.queue.indices.contains(playback.queueIndex) else { return }
        let id = playback.queue[playback.queueIndex].id
        proxy.scrollTo(id, anchor: .center)
    }
}

private struct DeckContextRow: View {
    let index: Int
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "waveform")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(HarborColor.amber)
                    } else {
                        Text("\(index + 1)")
                            .font(HarborFont.mono(11))
                            .foregroundStyle(HarborColor.ivoryDim)
                    }
                }
                .frame(width: 22, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(HarborFont.title(13))
                        .foregroundStyle(isCurrent ? HarborColor.ivory : HarborColor.ivory.opacity(0.88))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(HarborFont.body(11))
                        .foregroundStyle(isCurrent ? HarborColor.amber.opacity(0.9) : HarborColor.ivoryDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if track.duration > 0 {
                    Text(timeString(track.duration))
                        .font(HarborFont.mono(10))
                        .foregroundStyle(HarborColor.ivoryDim)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isCurrent ? HarborColor.amber.opacity(0.14) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isCurrent {
                    Rectangle()
                        .fill(HarborColor.amber)
                        .frame(width: 2)
                        .padding(.vertical, 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

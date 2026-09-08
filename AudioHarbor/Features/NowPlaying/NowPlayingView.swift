import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct NowPlayingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var scrubRatio: Double?
    @AppStorage("audioharbor.deckStyle") private var deckStyleRaw: String = DeckStyle.turntable.rawValue
    @AppStorage("audioharbor.deck.contextRailVisible") private var contextRailVisible = true
    #if os(iOS)
    @State private var showContextSheet = false
    #endif

    private var deckStyle: Binding<DeckStyle> {
        Binding(
            get: { DeckStyle(rawValue: deckStyleRaw) ?? .turntable },
            set: { deckStyleRaw = $0.rawValue }
        )
    }

    var body: some View {
        let playback = appModel.playback
        let track = playback.currentTrack
        let duration = max(playback.duration, 0.1)
        let display = scrubRatio.map { $0 * duration } ?? playback.currentTime
        let progress = min(max(display / duration, 0), 1)
        let style = deckStyle.wrappedValue

        #if os(macOS)
        HStack(spacing: 0) {
            deckChrome(
                playback: playback,
                track: track,
                style: style,
                progress: progress,
                display: display,
                duration: duration
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if contextRailVisible {
                Divider().overlay(HarborColor.aluminumDark.opacity(0.6))
                DeckContextRail {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        contextRailVisible = false
                    }
                }
                .frame(width: 300)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: contextRailVisible)
        #else
        deckChrome(
            playback: playback,
            track: track,
            style: style,
            progress: progress,
            display: display,
            duration: duration
        )
        .sheet(isPresented: $showContextSheet) {
            NavigationStack {
                DeckContextRail()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showContextSheet = false }
                        }
                    }
                    .navigationTitle("Queue")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        #endif
    }

    private func deckChrome(
        playback: PlaybackService,
        track: Track?,
        style: DeckStyle,
        progress: Double,
        display: TimeInterval,
        duration: TimeInterval
    ) -> some View {
        ReceiverChassis {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        EngravedLabel(text: style.engraved)
                        Spacer()
                        contextToggle
                        PowerLamp(isOn: playback.isPlaying)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 22) {
                        DeckStage(
                            style: deckStyle,
                            artwork: artworkImage(track),
                            isPlaying: playback.isPlaying,
                            progress: progress,
                            currentTime: display
                        )

                        metadata(track, style: style)
                        meter(playback, progress: progress, display: display, duration: duration)
                        transport(playback)
                    }
                    .faceplate()

                    DeckRackPanel()
                }
                .padding(.bottom, 8)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var contextToggle: some View {
        Button {
            #if os(macOS)
            withAnimation(.easeInOut(duration: 0.2)) {
                contextRailVisible.toggle()
            }
            #else
            showContextSheet = true
            #endif
        } label: {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(contextToggleTint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show queue beside the deck")
        #if os(macOS)
        .keyboardShortcut("\\", modifiers: .command)
        #endif
    }

    private var contextToggleTint: Color {
        #if os(macOS)
        contextRailVisible ? HarborColor.amber : HarborColor.ivoryDim
        #else
        HarborColor.ivoryDim
        #endif
    }

    @ViewBuilder
    private func metadata(_ track: Track?, style: DeckStyle) -> some View {
        VStack(spacing: 10) {
            Text(track?.title ?? idleTitle(style))
                .font(HarborFont.display(28))
                .foregroundStyle(HarborColor.ivory)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(track.map { "\($0.artist)  ·  \($0.album)" } ?? idleSubtitle(style))
                .font(HarborFont.body(14))
                .foregroundStyle(HarborColor.ivoryDim)
                .multilineTextAlignment(.center)
            if let track {
                FormatBadge(
                    format: track.format,
                    sampleRateHz: track.sampleRateHz,
                    bitDepth: track.bitDepth
                )
            }
            HStack(spacing: 8) {
                if let label = appModel.playback.activeFormatLabel {
                    Text(label)
                }
                Text("·")
                Text(appModel.playback.pathLabel)
            }
            .font(HarborFont.mono(11))
            .foregroundStyle(HarborColor.ivoryDim)

            if case .failed(let message) = appModel.playback.state {
                Text(message)
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.danger)
                    .multilineTextAlignment(.center)
            }
            if case .loading = appModel.playback.state {
                ProgressView()
                    .tint(HarborColor.amber)
            }
        }
    }

    private func idleTitle(_ style: DeckStyle) -> String {
        switch style {
        case .turntable: "Nothing on the platter"
        case .reelToReel: "No tape threaded"
        case .cassette: "No cassette loaded"
        case .receiver: "No source selected"
        }
    }

    private func idleSubtitle(_ style: DeckStyle) -> String {
        switch style {
        case .turntable: "Drop the needle from Catalogue or Playlists"
        case .reelToReel: "Load a track from Catalogue or Playlists"
        case .cassette: "Press play from Catalogue or Playlists"
        case .receiver: "Choose a track from Catalogue or Playlists"
        }
    }

    private func meter(
        _ playback: PlaybackService,
        progress: Double,
        display: TimeInterval,
        duration: TimeInterval
    ) -> some View {
        VStack(spacing: 6) {
            EngravedLabel(text: "Position")
            SeekBar(
                progress: progress,
                onSeeking: { ratio in
                    scrubRatio = ratio
                },
                onSeekEnded: { ratio in
                    playback.seek(to: ratio * duration)
                    scrubRatio = nil
                }
            )
            HStack {
                Text(timeString(display))
                Spacer()
                Text(timeString(playback.duration))
            }
            .font(HarborFont.mono(12))
            .foregroundStyle(HarborColor.ivoryDim)
        }
    }

    private func transport(_ playback: PlaybackService) -> some View {
        HStack(spacing: 28) {
            HardwareButton(systemName: "backward.fill") {
                playback.playPrevious()
            }
            HardwareButton(
                systemName: playback.isPlaying ? "pause.fill" : "play.fill",
                isPrimary: true,
                isLit: playback.isPlaying
            ) {
                playback.togglePlayPause()
            }
            HardwareButton(systemName: "forward.fill") {
                playback.playNext()
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func artworkImage(_ track: Track?) -> Image? {
        guard let data = track.flatMap({ ArtworkCache.data(for: $0) }) else { return nil }
        #if os(macOS)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #else
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #endif
        return nil
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

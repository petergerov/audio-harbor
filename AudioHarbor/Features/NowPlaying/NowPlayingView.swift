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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showContextSheet = false
    #endif

    private var deckStyle: Binding<DeckStyle> {
        Binding(
            get: {
                let raw = deckStyleRaw
                if raw == "cassette" { return .turntable }
                return DeckStyle(rawValue: raw) ?? .turntable
            },
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
        GeometryReader { geo in
            deckChrome(
                playback: playback,
                track: track,
                style: style,
                progress: progress,
                display: display,
                duration: duration,
                heroHeight: compactHeroHeight(in: geo.size.height, hasRack: track != nil)
            )
        }
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
        duration: TimeInterval,
        heroHeight: CGFloat? = nil
    ) -> some View {
        let compact = heroHeight != nil
        return ReceiverChassis {
            ScrollView {
                VStack(spacing: compact ? 10 : 16) {
                    HStack {
                        EngravedLabel(text: style.engraved)
                        Spacer()
                        contextToggle
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: compact ? 12 : 22) {
                        VStack(spacing: compact ? 8 : 10) {
                            DeckStage(
                                style: deckStyle,
                                artwork: artworkImage(track),
                                isPlaying: playback.isPlaying,
                                progress: progress,
                                heroHeight: heroHeight,
                                meterLeft: playback.meterLeft,
                                meterRight: playback.meterRight
                            )
                            PowerLamp(isOn: playback.isPlaying)
                        }

                        metadata(track, style: style, compact: compact)
                        meter(
                            playback,
                            track: track,
                            progress: progress,
                            display: display,
                            duration: duration
                        )
                        transport(playback, compact: compact)
                    }
                    .faceplate(compact: compact)

                    if track != nil {
                        DeckRackPanel()
                    }
                }
                .padding(.bottom, 8)
            }
            #if os(iOS)
            .scrollBounceBehavior(.basedOnSize)
            #endif
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    #if os(iOS)
    private func compactHeroHeight(in viewport: CGFloat, hasRack: Bool) -> CGFloat? {
        guard horizontalSizeClass == .compact else { return nil }
        let reserved: CGFloat = hasRack ? 400 : 320
        return min(228, max(128, viewport - reserved))
    }
    #endif

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
    private func metadata(_ track: Track?, style: DeckStyle, compact: Bool) -> some View {
        VStack(spacing: compact ? 5 : 10) {
            Text(track?.title ?? idleTitle(style))
                .font(HarborFont.display(compact ? 20 : 28))
                .foregroundStyle(HarborColor.ivory)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 1 : 2)
            Text(track.map { "\($0.artist)  ·  \($0.album)" } ?? idleSubtitle(style))
                .font(HarborFont.body(compact ? 12 : 14))
                .foregroundStyle(HarborColor.ivoryDim)
                .multilineTextAlignment(.center)
                .lineLimit(1)
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
        case .receiver: "No source selected"
        }
    }

    private func idleSubtitle(_ style: DeckStyle) -> String {
        switch style {
        case .turntable: "Drop the needle from Catalogue or Playlists"
        case .reelToReel: "Load a track from Catalogue or Playlists"
        case .receiver: "Choose a track from Catalogue or Playlists"
        }
    }

    private func meter(
        _ playback: PlaybackService,
        track: Track?,
        progress: Double,
        display: TimeInterval,
        duration: TimeInterval
    ) -> some View {
        VStack(spacing: 6) {
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
            ZStack {
                HStack {
                    Text(timeString(display))
                    Spacer()
                    Text(timeString(playback.duration))
                }
                // Centred on the full width, so it stays put as the times change.
                if let track {
                    FormatBadge(
                        format: track.format,
                        sampleRateHz: track.sampleRateHz,
                        bitDepth: track.bitDepth,
                        path: playback.pathLabel
                    )
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 52)
                }
            }
            .font(HarborFont.mono(12))
            .foregroundStyle(HarborColor.ivoryDim)
        }
    }

    private func transport(_ playback: PlaybackService, compact: Bool) -> some View {
        HStack(spacing: compact ? 14 : 20) {
            HardwareButton(
                systemName: "shuffle",
                isLit: playback.isShuffled,
                isSatellite: true
            ) {
                playback.toggleShuffle()
            }
            .help(playback.isShuffled ? "Shuffle on" : "Shuffle off")
            .accessibilityLabel("Shuffle")
            .accessibilityValue(playback.isShuffled ? "On" : "Off")

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

            HardwareButton(
                systemName: playback.repeatMode.systemImage,
                isLit: playback.repeatMode != .off,
                isSatellite: true
            ) {
                playback.cycleRepeatMode()
            }
            .help(playback.repeatMode.title)
            .accessibilityLabel("Repeat")
            .accessibilityValue(playback.repeatMode.title)
        }
        .padding(.top, compact ? 0 : 4)
        .padding(.bottom, compact ? 2 : 8)
        .scaleEffect(compact ? 0.86 : 1, anchor: .center)
        .padding(.vertical, compact ? -6 : 0)
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

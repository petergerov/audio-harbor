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
    /// A little more than 2/3, or almost the full iPad screen.
    @State private var queueExtent: CGFloat = IPadQueuePanel.almostFull
    @State private var queueDrag: CGFloat = 0
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
            ZStack(alignment: .bottom) {
                deckChrome(
                    playback: playback,
                    track: track,
                    style: style,
                    progress: progress,
                    display: display,
                    duration: duration,
                    heroHeight: compactHeroHeight(in: geo.size.height, hasRack: track != nil)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isPad && showContextSheet {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { dismissQueuePanel() }
                        .transition(.opacity)

                    IPadQueuePanel(
                        onClose: dismissQueuePanel,
                        onToggleExtent: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                queueExtent = queueExtent > 0.85
                                    ? IPadQueuePanel.twoThirds
                                    : IPadQueuePanel.almostFull
                            }
                        }
                    ) { value in
                        queueDrag = value.translation.height
                    } onGrabEnd: { value in
                        snapQueuePanel(translation: value.translation.height, in: geo.size.height)
                    }
                    .frame(height: queuePanelHeight(in: geo.size.height))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showContextSheet)
            .animation(.easeInOut(duration: 0.2), value: queueExtent)
        }
        .sheet(isPresented: compactQueuePresented) {
            contextQueuePage
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                    VStack(spacing: compact ? 12 : 22) {
                        DeckStage(
                            style: deckStyle,
                            artwork: artworkImage(track),
                            isPlaying: playback.isPlaying,
                            progress: progress,
                            heroHeight: heroHeight,
                            meterLeft: playback.meterLeft,
                            meterRight: playback.meterRight
                        ) {
                            HStack(spacing: 12) {
                                PowerLamp(isOn: playback.isPlaying)
                                contextToggle
                            }
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
    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var compactQueuePresented: Binding<Bool> {
        Binding(
            get: { showContextSheet && !isPad },
            set: { if !$0 { showContextSheet = false } }
        )
    }

    private func queuePanelHeight(in viewport: CGFloat) -> CGFloat {
        let live = queueExtent - (queueDrag / max(viewport, 1))
        return viewport * min(IPadQueuePanel.almostFull, max(0.45, live))
    }

    private func snapQueuePanel(translation: CGFloat, in viewport: CGFloat) {
        let live = queueExtent - (translation / max(viewport, 1))
        queueDrag = 0
        if live < 0.52 {
            dismissQueuePanel()
            return
        }
        let two = IPadQueuePanel.twoThirds
        let full = IPadQueuePanel.almostFull
        withAnimation(.easeInOut(duration: 0.2)) {
            queueExtent = abs(live - two) < abs(live - full) ? two : full
        }
    }

    private func presentQueuePanel() {
        queueExtent = IPadQueuePanel.almostFull
        queueDrag = 0
        withAnimation(.easeInOut(duration: 0.25)) {
            showContextSheet = true
        }
    }

    private func dismissQueuePanel() {
        queueDrag = 0
        withAnimation(.easeInOut(duration: 0.25)) {
            showContextSheet = false
        }
    }

    private var contextQueuePage: some View {
        NavigationStack {
            DeckContextRail {
                showContextSheet = false
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showContextSheet = false }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HarborColor.faceplate, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .background(HarborColor.faceplate.ignoresSafeArea())
    }

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
            if showContextSheet {
                dismissQueuePanel()
            } else {
                presentQueuePanel()
            }
            #endif
        } label: {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(contextToggleForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(contextToggleFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(HarborColor.aluminumDark, lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show queue beside the deck")
        #if os(macOS)
        .keyboardShortcut("\\", modifiers: .command)
        #endif
    }

    private var contextToggleForeground: Color {
        #if os(macOS)
        contextRailVisible ? HarborColor.faceplate : HarborColor.ivoryDim
        #else
        showContextSheet ? HarborColor.faceplate : HarborColor.ivoryDim
        #endif
    }

    private var contextToggleFill: Color {
        #if os(macOS)
        contextRailVisible ? HarborColor.amber : HarborColor.faceplate.opacity(0.5)
        #else
        showContextSheet ? HarborColor.amber : HarborColor.faceplate.opacity(0.5)
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

#if os(iOS)
/// Almost-fullscreen queue on iPad, with a grabber that snaps to ~2/3 or ~94%.
private struct IPadQueuePanel: View {
    static let twoThirds: CGFloat = 0.72
    static let almostFull: CGFloat = 0.94

    var onClose: () -> Void
    var onToggleExtent: () -> Void
    var onGrab: (DragGesture.Value) -> Void
    var onGrabEnd: (DragGesture.Value) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(HarborColor.aluminum.opacity(0.55))
                .frame(width: 48, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged(onGrab)
                        .onEnded(onGrabEnd)
                )
                .onTapGesture(perform: onToggleExtent)
                .accessibilityLabel("Resize queue")
                .accessibilityHint("Two thirds or almost full screen")

            DeckContextRail(onClose: onClose)
        }
        .background(HarborColor.faceplate)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HarborColor.aluminumDark.opacity(0.55), lineWidth: 1)
        )
    }
}
#endif

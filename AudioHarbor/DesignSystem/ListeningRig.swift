import SwiftUI

/// Listening desk: photoreal macro turntable.
/// Wide layout → `NicePlayer1`; portrait / tight width → `NicePlayer3`.
struct ListeningRig: View {
    let artwork: Image?
    let isPlaying: Bool
    let progress: Double
    var stageHeight: CGFloat? = nil

    var body: some View {
        if let stageHeight {
            TurntableMacroView(
                isPlaying: isPlaying,
                progress: progress,
                artwork: artwork,
                layout: .wide,
                stageHeightOverride: stageHeight
            )
            .frame(maxWidth: .infinity)
        } else {
            ViewThatFits(in: .horizontal) {
                TurntableMacroView(
                    isPlaying: isPlaying,
                    progress: progress,
                    artwork: artwork,
                    layout: .wide
                )
                .frame(minWidth: 480)
                .frame(maxWidth: .infinity)
                TurntableMacroView(
                    isPlaying: isPlaying,
                    progress: progress,
                    artwork: artwork,
                    layout: .portrait
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Photoreal macro

private enum TurntableHeroLayout {
    /// Landscape hero (`nice_player_1`).
    case wide
    /// Stacked / narrow — portrait hero (`nice_player_3`).
    case portrait

    var imageName: String {
        switch self {
        case .wide: "NicePlayer1"
        case .portrait: "NicePlayer3"
        }
    }

    var stageHeight: CGFloat {
        switch self {
        case .wide: 400
        case .portrait: 520
        }
    }

    /// Dolly toward the stylus / cartridge. Wide crop stays left-weighted so the
    /// truncated tonearm on the right of `nice_player_1` never sits on the frame edge.
    var dollyAnchor: UnitPoint {
        switch self {
        case .wide: UnitPoint(x: 0.36, y: 0.52)
        case .portrait: UnitPoint(x: 0.62, y: 0.42)
        }
    }

    var vignetteCenter: UnitPoint {
        switch self {
        case .wide: UnitPoint(x: 0.42, y: 0.52)
        case .portrait: UnitPoint(x: 0.55, y: 0.45)
        }
    }
}

/// Hero photograph switches by layout. Motion: groove shimmer + progress dolly.
private struct TurntableMacroView: View {
    let isPlaying: Bool
    let progress: Double
    let artwork: Image?
    let layout: TurntableHeroLayout
    var stageHeightOverride: CGFloat? = nil

    /// 33⅓ RPM shimmer period.
    private static let secondsPerRevolution: Double = 1.8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                EngravedLabel(text: isPlaying ? "Needle Down · 33⅓" : "Cue Rest", size: 9)
                Spacer(minLength: 12)
                EngravedLabel(text: grooveLabel, size: 8)
            }

            GeometryReader { geo in
                hero(size: geo.size)
            }
            .frame(height: stageHeightOverride ?? layout.stageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.72, green: 0.55, blue: 0.32).opacity(0.55),
                                HarborColor.aluminumDark.opacity(0.7),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: .black.opacity(0.65), radius: 22, y: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPlaying ? "Turntable playing" : "Turntable paused")
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }

    private func hero(size: CGSize) -> some View {
        let t = clampedProgress
        let cover: CGFloat = layout == .wide ? 1.22 : 1.06
        let scale: CGFloat = cover + 0.08 * t
        // Wide: keep the source's hard-cut tonearm off the right edge of the frame.
        let panX: CGFloat = layout == .wide
            ? size.width * (0.04 + 0.02 * t)
            : size.width * (-0.02 - 0.06 * t)
        let panY: CGFloat = size.height * (0.01 + 0.03 * t)

        return ZStack {
            Color(red: 0.06, green: 0.04, blue: 0.03)

            Image(layout.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale, anchor: layout.dollyAnchor)
                .offset(x: panX, y: panY)
                .animation(.spring(response: 0.85, dampingFraction: 0.92), value: progress)
                .animation(.easeInOut(duration: 0.25), value: layout.imageName)
                .allowsHitTesting(false)

            grooveShimmer(size: size)

            Color.black.opacity(isPlaying ? 0 : 0.28)
                .animation(.easeInOut(duration: 0.4), value: isPlaying)
                .allowsHitTesting(false)

            warmGrade(size: size)

            if layout == .wide {
                LinearGradient(
                    colors: [
                        .clear,
                        Color(red: 0.05, green: 0.03, blue: 0.02).opacity(0.35),
                        Color(red: 0.04, green: 0.02, blue: 0.02).opacity(0.88),
                    ],
                    startPoint: UnitPoint(x: 0.58, y: 0.5),
                    endPoint: .trailing
                )
                .allowsHitTesting(false)
            }

            RadialGradient(
                colors: [.clear, .clear, Color.black.opacity(0.45)],
                center: layout.vignetteCenter,
                startRadius: size.width * 0.22,
                endRadius: size.width * 0.78
            )
            .allowsHitTesting(false)
        }
        .clipped()
        .overlay(alignment: .bottomLeading) { artworkChip }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(isPlaying ? HarborColor.powerLED : HarborColor.aluminumDark)
                .frame(width: 7, height: 7)
                .shadow(color: isPlaying ? HarborColor.powerLED.opacity(0.85) : .clear, radius: 5)
                .padding(14)
        }
    }

    /// Warm specular bands that drift along the grooves while playing —
    /// reads as vinyl spin without rotating the perspective photo.
    private func grooveShimmer(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let phase = seconds.truncatingRemainder(dividingBy: Self.secondsPerRevolution)
                / Self.secondsPerRevolution
            let slow = seconds.truncatingRemainder(dividingBy: Self.secondsPerRevolution * 3.5)
                / (Self.secondsPerRevolution * 3.5)

            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color(red: 1.0, green: 0.82, blue: 0.45).opacity(isPlaying ? 0.16 : 0.04),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size.width * 0.55, height: size.height * 0.18)
                    .rotationEffect(.degrees(18))
                    .blur(radius: 28)
                    .position(
                        x: size.width * CGFloat(-0.1 + 1.2 * phase),
                        y: size.height * CGFloat(0.55 + 0.15 * phase)
                    )

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(isPlaying ? 0.10 : 0.03),
                                .clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size.width * 0.75, height: size.height * 0.28)
                    .rotationEffect(.degrees(22))
                    .blur(radius: 40)
                    .position(
                        x: size.width * CGFloat(0.05 + 0.9 * slow),
                        y: size.height * CGFloat(0.48 + 0.2 * slow)
                    )
            }
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    private func warmGrade(size: CGSize) -> some View {
        ZStack {
            // Amber bounce from the bokeh lamps in the reference.
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.55, blue: 0.18).opacity(isPlaying ? 0.14 : 0.06),
                    .clear,
                ],
                center: UnitPoint(x: 0.82, y: 0.18),
                startRadius: 0,
                endRadius: size.width * 0.55
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [Color.black.opacity(0.25), .clear],
                startPoint: .bottom,
                endPoint: .center
            )
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var artworkChip: some View {
        if let artwork {
            artwork
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Color(red: 0.72, green: 0.55, blue: 0.32).opacity(0.55), lineWidth: 0.8)
                )
                .rotationEffect(.degrees(-3))
                .shadow(color: .black.opacity(0.7), radius: 10, y: 5)
                .padding(16)
                .allowsHitTesting(false)
        }
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    private var grooveLabel: String {
        let p = min(max(progress, 0), 1)
        if p <= 0.02 { return "Lead-in" }
        if p >= 0.98 { return "Run-out" }
        return "Groove \(Int(p * 100))%"
    }
}

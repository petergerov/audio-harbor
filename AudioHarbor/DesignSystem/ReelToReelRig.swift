import SwiftUI

/// Photoreal reel-to-reel: `tonband_2` wide, `tonband_3` portrait / tight width.
struct ReelToReelRig: View {
    let isPlaying: Bool
    let progress: Double
    var stageHeight: CGFloat? = nil

    var body: some View {
        if let stageHeight {
            ReelHeroView(
                isPlaying: isPlaying,
                progress: progress,
                layout: .wide,
                stageHeightOverride: stageHeight
            )
            .frame(maxWidth: .infinity)
        } else {
            ViewThatFits(in: .horizontal) {
                ReelHeroView(isPlaying: isPlaying, progress: progress, layout: .wide)
                    .frame(minWidth: 480, maxWidth: 720)
                ReelHeroView(isPlaying: isPlaying, progress: progress, layout: .portrait)
                    .frame(maxWidth: 720)
            }
        }
    }
}

private enum ReelHeroLayout {
    case wide
    case portrait

    var imageName: String {
        switch self {
        case .wide: "TonbandWide"
        case .portrait: "TonbandPortrait"
        }
    }

    var stageHeight: CGFloat {
        switch self {
        case .wide: 340
        case .portrait: 460
        }
    }

    /// Dolly toward take-up / transport as the tape advances.
    var dollyAnchor: UnitPoint {
        switch self {
        case .wide: UnitPoint(x: 0.52, y: 0.38)
        case .portrait: UnitPoint(x: 0.55, y: 0.32)
        }
    }

    var engraved: String {
        switch self {
        case .wide: "Open Reel · GX"
        case .portrait: "Open Reel · A80"
        }
    }
}

private struct ReelHeroView: View {
    let isPlaying: Bool
    let progress: Double
    let layout: ReelHeroLayout
    var stageHeightOverride: CGFloat? = nil

    private static let secondsPerRevolution: Double = 2.2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                EngravedLabel(text: isPlaying ? "\(layout.engraved) · Transport" : "\(layout.engraved) · Stop", size: 9)
                Spacer(minLength: 12)
                EngravedLabel(text: tapeLabel, size: 8)
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
                                HarborColor.aluminum.opacity(0.55),
                                HarborColor.aluminumDark.opacity(0.7),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: .black.opacity(0.55), radius: 20, y: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPlaying ? "Reel to reel playing" : "Reel to reel stopped")
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }

    private func hero(size: CGSize) -> some View {
        let t = clampedProgress
        // Supply → take-up: ease framing toward the right reel / transport as tape advances.
        let scale: CGFloat = 1.0 + 0.10 * t
        let panX: CGFloat = size.width * (0.01 + 0.05 * t)
        let panY: CGFloat = size.height * (0.00 + 0.03 * t)

        return ZStack {
            Color(red: 0.05, green: 0.04, blue: 0.035)

            Image(layout.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale, anchor: layout.dollyAnchor)
                .offset(x: panX, y: panY)
                .animation(.spring(response: 0.85, dampingFraction: 0.92), value: progress)
                .animation(.easeInOut(duration: 0.25), value: layout.imageName)
                .allowsHitTesting(false)

            reelShimmer(size: size)

            Color.black.opacity(isPlaying ? 0 : 0.30)
                .animation(.easeInOut(duration: 0.4), value: isPlaying)
                .allowsHitTesting(false)

            // Amber bounce from the VU lamps in the photos.
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.55, blue: 0.15).opacity(isPlaying ? 0.16 : 0.06),
                    .clear,
                ],
                center: UnitPoint(x: 0.55, y: 0.72),
                startRadius: 0,
                endRadius: size.width * 0.5
            )
            .blendMode(.screen)
            .allowsHitTesting(false)

            RadialGradient(
                colors: [.clear, .clear, Color.black.opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: size.width * 0.2,
                endRadius: size.width * 0.78
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(isPlaying ? HarborColor.powerLED : HarborColor.aluminumDark)
                .frame(width: 7, height: 7)
                .shadow(color: isPlaying ? HarborColor.powerLED.opacity(0.85) : .clear, radius: 5)
                .padding(14)
        }
    }

    /// Soft specular drift — sells reel motion without rotating the photo.
    private func reelShimmer(size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let phase = seconds.truncatingRemainder(dividingBy: Self.secondsPerRevolution)
                / Self.secondsPerRevolution
            let slow = seconds.truncatingRemainder(dividingBy: Self.secondsPerRevolution * 3.2)
                / (Self.secondsPerRevolution * 3.2)

            ZStack {
                // Left (supply) sheen
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isPlaying ? 0.14 : 0.04),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 80
                        )
                    )
                    .frame(width: size.width * 0.28, height: size.height * 0.22)
                    .blur(radius: 18)
                    .position(
                        x: size.width * (0.28 + 0.04 * sin(phase * .pi * 2)),
                        y: size.height * 0.28
                    )

                // Right (take-up) sheen
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isPlaying ? 0.16 : 0.04),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 90
                        )
                    )
                    .frame(width: size.width * 0.30, height: size.height * 0.24)
                    .blur(radius: 20)
                    .position(
                        x: size.width * (0.72 + 0.04 * cos(phase * .pi * 2)),
                        y: size.height * 0.28
                    )

                // Tape path glint
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color(red: 1.0, green: 0.75, blue: 0.35).opacity(isPlaying ? 0.18 : 0.04),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size.width * 0.35, height: 10)
                    .blur(radius: 8)
                    .position(
                        x: size.width * CGFloat(0.25 + 0.5 * slow),
                        y: size.height * 0.42
                    )
            }
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    private var tapeLabel: String {
        let p = min(max(progress, 0), 1)
        if p <= 0.02 { return "Leader" }
        if p >= 0.98 { return "Tail" }
        return "Tape \(Int(p * 100))%"
    }
}

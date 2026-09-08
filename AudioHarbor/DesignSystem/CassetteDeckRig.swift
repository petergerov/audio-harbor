import SwiftUI

/// Compact cassette transport with window, hubs, and mechanical counter.
struct CassetteDeckRig: View {
    let artwork: Image?
    let isPlaying: Bool
    let progress: Double
    let currentTime: TimeInterval
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack {
                EngravedLabel(text: "Cassette Deck", size: 9)
                Spacer()
                mechanicalCounter
            }

            cassetteShell

            if !compact {
                HStack(spacing: 18) {
                    transportKey(symbol: "backward.fill", lit: false)
                    transportKey(symbol: isPlaying ? "pause.fill" : "play.fill", lit: isPlaying)
                    transportKey(symbol: "forward.fill", lit: false)
                }
                .opacity(0.55)
                .allowsHitTesting(false)
            }
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.15, blue: 0.14),
                            Color(red: 0.08, green: 0.08, blue: 0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(HarborColor.aluminum.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
    }

    private var mechanicalCounter: some View {
        let total = max(Int(currentTime), 0)
        let digits = String(format: "%04d", min(total, 9999))
        return HStack(spacing: 2) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(HarborFont.mono(14))
                    .foregroundStyle(HarborColor.amber)
                    .frame(width: 16, height: 22)
                    .background(Color.black.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(HarborColor.aluminumDark, lineWidth: 1)
                    )
            }
        }
        .accessibilityLabel("Tape counter \(digits)")
    }

    private var cassetteShell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.18, blue: 0.12),
                            Color(red: 0.12, green: 0.10, blue: 0.07),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(HarborColor.aluminumDark, lineWidth: 1.5)
                )
                .frame(height: compact ? 110 : 150)

            // Label area
            HStack(spacing: 12) {
                Group {
                    if let artwork {
                        artwork
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(red: 0.25, green: 0.2, blue: 0.14)
                            .overlay {
                                EngravedLabel(text: "Side A", size: 10)
                            }
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("AUDIO HARBOR")
                        .font(HarborFont.panel(10))
                        .tracking(1.5)
                        .foregroundStyle(HarborColor.ivory)
                    Text("TYPE II · CHROME")
                        .font(HarborFont.mono(9))
                        .foregroundStyle(HarborColor.amber)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .offset(y: -28)

            // Window with hubs
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let spin = isPlaying ? t.truncatingRemainder(dividingBy: 2.2) / 2.2 * 360 : 0
                let p = min(max(progress, 0), 1)

                HStack(spacing: 36) {
                    CassetteHub(fill: 1 - p * 0.7, angle: -spin)
                    CassetteHub(fill: 0.25 + p * 0.7, angle: spin)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
                .frame(maxWidth: 280)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .offset(y: 28)
            }
        }
        .padding(.horizontal, 8)
    }

    private func transportKey(symbol: String, lit: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(lit ? HarborColor.amber : HarborColor.ivoryDim)
            .frame(width: 36, height: 28)
            .background(HarborColor.aluminumDark.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

private struct CassetteHub: View {
    let fill: Double
    let angle: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color(red: 0.45, green: 0.2, blue: 0.1),
                    lineWidth: 10 * CGFloat(min(max(fill, 0.2), 1))
                )
                .frame(width: 44, height: 44)
            Circle()
                .fill(HarborColor.aluminum)
                .frame(width: 18, height: 18)
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(HarborColor.faceplate)
                    .frame(width: 2, height: 7)
                    .offset(y: -6)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
        }
        .rotationEffect(.degrees(angle))
    }
}

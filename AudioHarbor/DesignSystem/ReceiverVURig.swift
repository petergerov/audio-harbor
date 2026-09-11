import SwiftUI

/// Large stereo receiver faceplate with dual bouncing VU needles.
struct ReceiverVURig: View {
    let isPlaying: Bool
    let progress: Double
    var leftLevel: Double = 0
    var rightLevel: Double = 0

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                EngravedLabel(text: "Stereo Receiver", size: 9)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(isPlaying ? HarborColor.powerLED : HarborColor.aluminumDark)
                        .frame(width: 8, height: 8)
                        .shadow(color: isPlaying ? HarborColor.powerLED.opacity(0.8) : .clear, radius: 5)
                    EngravedLabel(text: isPlaying ? "Power" : "Standby", size: 8)
                }
            }

            HStack(spacing: 16) {
                AnalogVUMeter(label: "L", level: leftLevel)
                AnalogVUMeter(label: "R", level: rightLevel)
            }

            // Tuning / mode strip
            HStack(spacing: 12) {
                modeLamp("Phono", on: true)
                modeLamp("Tuner", on: false)
                modeLamp("Tape", on: false)
                modeLamp("Aux", on: false)
                Spacer()
                Text(String(format: "%.0f%%", min(max(progress, 0), 1) * 100))
                    .font(HarborFont.mono(11))
                    .foregroundStyle(HarborColor.amber)
            }

            // Faux aluminum knobs row
            HStack(spacing: 22) {
                ReceiverKnob(label: "Bass")
                ReceiverKnob(label: "Treble")
                ReceiverKnob(label: "Balance")
                ReceiverKnob(label: "Volume", large: true)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.13, blue: 0.12),
                            Color(red: 0.06, green: 0.06, blue: 0.06),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    HarborColor.aluminum.opacity(0.5),
                                    HarborColor.aluminumDark.opacity(0.4),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        )
    }

    private func modeLamp(_ title: String, on: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(on ? HarborColor.amber : HarborColor.aluminumDark)
                .frame(width: 6, height: 6)
                .shadow(color: on ? HarborColor.amber.opacity(0.7) : .clear, radius: 4)
            EngravedLabel(text: title, size: 8)
        }
    }
}

struct AnalogVUMeter: View {
    let label: String
    let level: Double
    var compact: Bool = false

    private var clamped: Double { min(max(level, 0), 1) }
    private var over: Bool { clamped >= 20.0 / 23.0 }
    private var meterHeight: CGFloat { compact ? 64 : 88 }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                EngravedLabel(text: label, size: 9)
                Spacer()
                Circle()
                    .fill(over ? HarborColor.danger : HarborColor.aluminumDark)
                    .frame(width: 6, height: 6)
                    .shadow(color: over ? HarborColor.danger.opacity(0.85) : .clear, radius: 4)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.93, green: 0.88, blue: 0.74),
                                    Color(red: 0.84, green: 0.78, blue: 0.62),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    scale(width: w, height: h)

                    Text("VU")
                        .font(HarborFont.panel(compact ? 8 : 9))
                        .foregroundStyle(Color.black.opacity(0.32))
                        .position(x: w * 0.5, y: h * 0.30)

                    needle(width: w, height: h)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [HarborColor.brass, HarborColor.aluminumDark],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: 8
                            )
                        )
                        .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                        .position(x: w * 0.5, y: h * 0.92)

                    LinearGradient(
                        colors: [Color.white.opacity(0.28), .clear, Color.black.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .frame(height: meterHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [HarborColor.aluminum.opacity(0.7), HarborColor.aluminumDark],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private func scale(width w: CGFloat, height h: CGFloat) -> some View {
        let labels = ["−20", "−10", "−7", "−5", "−3", "0", "+3"]
        let positions: [CGFloat] = [0, 0.28, 0.42, 0.55, 0.68, 0.82, 1]
        return ZStack {
            ForEach(Array(positions.enumerated()), id: \.offset) { i, p in
                let x = w * (0.12 + 0.76 * p)
                let major = i == 0 || i == 5 || i == 6
                Path { path in
                    path.move(to: CGPoint(x: x, y: h * 0.72))
                    path.addLine(to: CGPoint(x: x, y: h * (major ? 0.46 : 0.56)))
                }
                .stroke(i >= 5 ? HarborColor.danger.opacity(0.75) : Color.black.opacity(0.4), lineWidth: major ? 1.2 : 0.8)

                if major {
                    Text(labels[i])
                        .font(.system(size: compact ? 6 : 7, weight: .semibold, design: .rounded))
                        .foregroundStyle(i >= 5 ? HarborColor.danger : Color.black.opacity(0.5))
                        .position(x: x, y: h * 0.38)
                }
            }
        }
    }

    private func needle(width w: CGFloat, height h: CGFloat) -> some View {
        let pivot = CGPoint(x: w * 0.5, y: h * 0.92)
        let degrees = -52.0 + 104.0 * clamped
        let rad = degrees * .pi / 180
        let len = w * 0.44
        return Path { path in
            path.move(to: pivot)
            path.addLine(to: CGPoint(
                x: pivot.x + CGFloat(sin(rad)) * len,
                y: pivot.y - CGFloat(cos(rad)) * len
            ))
        }
        .stroke(Color(red: 0.12, green: 0.08, blue: 0.05), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        .shadow(color: HarborColor.amber.opacity(over ? 0.5 : 0.15), radius: 2)
    }
}

private struct ReceiverKnob: View {
    let label: String
    var large: Bool = false

    var body: some View {
        VStack(spacing: 5) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [HarborColor.aluminum, HarborColor.aluminumDark],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: large ? 22 : 16
                    )
                )
                .frame(width: large ? 36 : 26, height: large ? 36 : 26)
                .overlay(
                    Capsule()
                        .fill(HarborColor.faceplate)
                        .frame(width: 2, height: large ? 11 : 8)
                        .offset(y: large ? -7 : -5)
                )
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.8))
            EngravedLabel(text: label, size: 7)
        }
    }
}

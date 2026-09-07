import SwiftUI

/// Large stereo receiver faceplate with dual bouncing VU needles.
struct ReceiverVURig: View {
    let isPlaying: Bool
    let progress: Double

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
                VUGauge(label: "L", isPlaying: isPlaying, phase: 0)
                VUGauge(label: "R", isPlaying: isPlaying, phase: 0.37)
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

private struct VUGauge: View {
    let label: String
    let isPlaying: Bool
    let phase: Double

    var body: some View {
        VStack(spacing: 6) {
            EngravedLabel(text: label, size: 9)
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let wobble = isPlaying
                    ? (0.45 + 0.4 * abs(sin(t * 3.1 + phase * .pi * 2))
                        + 0.12 * abs(sin(t * 7.4 + phase)))
                    : 0.08
                let level = min(max(wobble, 0), 1)

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.88, green: 0.84, blue: 0.74),
                                        Color(red: 0.76, green: 0.72, blue: 0.60),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // Scale
                        ForEach(0..<9, id: \.self) { i in
                            let x = w * (0.12 + 0.76 * CGFloat(i) / 8)
                            Path { path in
                                path.move(to: CGPoint(x: x, y: h * 0.7))
                                path.addLine(to: CGPoint(x: x, y: h * (i % 2 == 0 ? 0.45 : 0.55)))
                            }
                            .stroke(Color.black.opacity(0.35), lineWidth: 1)
                        }

                        Text("VU")
                            .font(HarborFont.panel(8))
                            .foregroundStyle(Color.black.opacity(0.35))
                            .position(x: w * 0.5, y: h * 0.28)

                        // Needle
                        Path { path in
                            let pivot = CGPoint(x: w * 0.5, y: h * 0.92)
                            let degrees = -55.0 + 110.0 * level
                            let rad = degrees * .pi / 180
                            let len = w * 0.42
                            path.move(to: pivot)
                            path.addLine(to: CGPoint(
                                x: pivot.x + CGFloat(sin(rad)) * len,
                                y: pivot.y - CGFloat(cos(rad)) * len
                            ))
                        }
                        .stroke(HarborColor.amber, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .shadow(color: HarborColor.amber.opacity(0.45), radius: 2)

                        Circle()
                            .fill(HarborColor.aluminumDark)
                            .frame(width: 8, height: 8)
                            .position(x: w * 0.5, y: h * 0.92)
                    }
                }
                .frame(height: 88)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(HarborColor.aluminumDark, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity)
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

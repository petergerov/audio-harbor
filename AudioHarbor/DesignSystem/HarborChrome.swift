import SwiftUI

/// Walnut + faceplate chassis that wraps every main screen.
struct ReceiverChassis<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    HarborColor.chassisLight,
                    HarborColor.chassis,
                    Color(red: 0.14, green: 0.10, blue: 0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle wood grain suggestion
            GeometryReader { geo in
                Path { path in
                    stride(from: 0.0, through: geo.size.height, by: 7).forEach { y in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y + 1.5))
                    }
                }
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            content
                .padding(12)
        }
    }
}

struct Faceplate: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(HarborColor.faceplate)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        HarborColor.aluminum.opacity(0.55),
                                        HarborColor.aluminumDark.opacity(0.35),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            )
    }
}

extension View {
    func faceplate() -> some View {
        modifier(Faceplate())
    }
}

/// Physical transport / mode button.
struct HardwareButton: View {
    let systemName: String
    var isPrimary: Bool = false
    var isLit: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                HarborColor.aluminum,
                                HarborColor.aluminumDark,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
                    .padding(1)
                Image(systemName: systemName)
                    .font(.system(size: isPrimary ? 22 : 16, weight: .bold))
                    .foregroundStyle(isLit ? HarborColor.amber : HarborColor.faceplate)
            }
            .frame(width: isPrimary ? 74 : 52, height: isPrimary ? 74 : 52)
            .shadow(color: .black.opacity(0.4), radius: 6, y: 4)
        }
        .buttonStyle(HardwarePressStyle())
    }
}

private struct HardwarePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.15 : 0.4),
                radius: configuration.isPressed ? 2 : 6,
                y: configuration.isPressed ? 1 : 4
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Conventional horizontal scrubber — tap or drag to seek.
struct SeekBar: View {
    let progress: Double
    var onSeeking: ((Double) -> Void)?
    var onSeekEnded: ((Double) -> Void)?

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(max(progress, 0), 1)
            let thumbX = clamped * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(HarborColor.aluminumDark)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(HarborColor.amber)
                    .frame(width: max(trackHeight, thumbX), height: trackHeight)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [HarborColor.aluminum, HarborColor.ivory],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Circle().stroke(HarborColor.aluminumDark, lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: min(max(thumbX, thumbSize / 2), width - thumbSize / 2), y: geo.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeeking?(ratio(at: value.location.x, width: width))
                    }
                    .onEnded { value in
                        onSeekEnded?(ratio(at: value.location.x, width: width))
                    }
            )
        }
        .frame(height: 36)
        .accessibilityLabel("Playback position")
    }

    private func ratio(at x: CGFloat, width: CGFloat) -> Double {
        min(max(Double(x / max(width, 1)), 0), 1)
    }
}

struct PowerLamp: View {
    var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? HarborColor.powerLED : HarborColor.aluminumDark)
                .frame(width: 8, height: 8)
                .shadow(color: isOn ? HarborColor.powerLED.opacity(0.8) : .clear, radius: isOn ? 6 : 0)
                .animation(.easeInOut(duration: 0.35), value: isOn)
            EngravedLabel(text: isOn ? "Power · On" : "Power · Standby", size: 9)
        }
    }
}

struct AluminumField<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(HarborColor.faceplate.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(HarborColor.aluminumDark, lineWidth: 1)
                    )
            )
    }
}

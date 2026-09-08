import SwiftUI

/// Listening-room chassis: ink field, walnut inlay, amber bloom while playing.
struct ReceiverChassis<Content: View>: View {
    @Environment(\.harborPlaying) private var playing
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            HarborColor.chassis
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    HarborColor.chassisLight.opacity(0.9),
                    HarborColor.chassis,
                    Color.black.opacity(0.55),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    HarborColor.amber.opacity(playing ? 0.14 : 0.04),
                    .clear,
                ],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: playing)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [HarborColor.walnut, HarborColor.walnut.opacity(0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 3)
                    .ignoresSafeArea(edges: .top)
                Spacer()
            }
            .allowsHitTesting(false)

            content
                .padding(16)
        }
    }
}

struct Faceplate: ViewModifier {
    var compact: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(compact ? 12 : 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HarborColor.faceplate)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        HarborColor.aluminum.opacity(0.28),
                                        HarborColor.aluminumDark.opacity(0.55),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.04), lineWidth: 1)
                            .padding(1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
            )
    }
}

extension View {
    func faceplate(compact: Bool = false) -> some View {
        modifier(Faceplate(compact: compact))
    }
}

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
                        RadialGradient(
                            colors: [
                                HarborColor.aluminum.opacity(0.95),
                                HarborColor.aluminumDark,
                            ],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: isPrimary ? 48 : 36
                        )
                    )
                Circle()
                    .stroke(Color.black.opacity(0.45), lineWidth: 1)
                    .padding(1)
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .padding(3)
                Image(systemName: systemName)
                    .font(.system(size: isPrimary ? 22 : 16, weight: .bold))
                    .foregroundStyle(isLit ? HarborColor.amber : HarborColor.faceplate)
                    .shadow(color: isLit ? HarborColor.amber.opacity(0.7) : .clear, radius: 6)
            }
            .frame(width: isPrimary ? 76 : 52, height: isPrimary ? 76 : 52)
            .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
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

struct SeekBar: View {
    let progress: Double
    var onSeeking: ((Double) -> Void)?
    var onSeekEnded: ((Double) -> Void)?

    private let trackHeight: CGFloat = 5
    private let thumbSize: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(max(progress, 0), 1)
            let thumbX = clamped * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(HarborColor.aluminumDark.opacity(0.7))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [HarborColor.amber, HarborColor.brass],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(trackHeight, thumbX), height: trackHeight)
                    .shadow(color: HarborColor.amber.opacity(0.35), radius: 4)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [HarborColor.ivory, HarborColor.aluminum],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Circle().stroke(HarborColor.brass.opacity(0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
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
                .frame(width: 7, height: 7)
                .shadow(color: isOn ? HarborColor.powerLED.opacity(0.85) : .clear, radius: isOn ? 7 : 0)
                .animation(.easeInOut(duration: 0.35), value: isOn)
            Text(isOn ? "Live" : "Standby")
                .font(HarborFont.panel(9))
                .tracking(1.2)
                .foregroundStyle(isOn ? HarborColor.powerLED : HarborColor.ivoryDim)
        }
    }
}

struct AluminumField<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(HarborColor.faceplateLift.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(HarborColor.aluminumDark.opacity(0.65), lineWidth: 1)
                    )
            )
    }
}

struct HarborSidebar: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandMark(compact: true)
                .padding(.horizontal, 6)

            VStack(spacing: 4) {
                ForEach(AppTab.allCases) { tab in
                    sidebarRow(tab)
                }
            }

            Spacer(minLength: 12)

            miniPlayer
            PowerLamp(isOn: appModel.playback.isPlaying)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HarborColor.chassis)
    }

    private func sidebarRow(_ tab: AppTab) -> some View {
        let selected = appModel.selectedTab == tab
        return Button {
            appModel.selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(selected ? HarborColor.amber : Color.clear)
                    .frame(width: 3, height: 18)
                Image(systemName: tab.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? HarborColor.amber : HarborColor.ivoryDim)
                    .frame(width: 18)
                Text(tab.title)
                    .font(HarborFont.title(13))
                    .foregroundStyle(selected ? HarborColor.ivory : HarborColor.ivoryDim)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? HarborColor.amber.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var miniPlayer: some View {
        let track = appModel.playback.currentTrack
        Button {
            appModel.selectedTab = .nowPlaying
        } label: {
            HStack(spacing: 10) {
                HarborArtwork(
                    hash: track?.artworkHash,
                    data: track?.artworkData,
                    size: 44,
                    corner: 8
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(track?.title ?? "Nothing playing")
                        .font(HarborFont.title(12))
                        .foregroundStyle(HarborColor.ivory)
                        .lineLimit(1)
                    Text(track?.artist ?? "Choose a record")
                        .font(HarborFont.body(11))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: appModel.playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HarborColor.amber)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(HarborColor.faceplate)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(HarborColor.aluminumDark.opacity(0.55), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if appModel.playback.currentTrack != nil {
                Button(appModel.playback.isPlaying ? "Pause" : "Play") {
                    appModel.playback.togglePlayPause()
                }
            }
        }
    }
}

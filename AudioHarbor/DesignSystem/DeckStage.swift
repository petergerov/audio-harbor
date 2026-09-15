import SwiftUI

enum DeckStyle: String, CaseIterable, Identifiable {
    case turntable
    case reelToReel
    case receiver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turntable: "Turntable"
        case .reelToReel: "Reel-to-Reel"
        case .receiver: "Receiver"
        }
    }

    var engraved: String {
        switch self {
        case .turntable: "Listening Desk"
        case .reelToReel: "Tape Transport"
        case .receiver: "Stereo Receiver"
        }
    }
}

struct DeckStage<Trailing: View>: View {
    @Binding var style: DeckStyle
    let artwork: Image?
    let isPlaying: Bool
    let progress: Double
    var heroHeight: CGFloat? = nil
    var meterLeft: Double = 0
    var meterRight: Double = 0
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: heroHeight == nil ? 12 : 6) {
            toolbarRow

            Group {
                switch style {
                case .turntable:
                    ListeningRig(
                        artwork: artwork,
                        isPlaying: isPlaying,
                        progress: progress,
                        stageHeight: heroHeight
                    )
                case .reelToReel:
                    ReelToReelRig(isPlaying: isPlaying, progress: progress, stageHeight: heroHeight)
                case .receiver:
                    ReceiverVURig(
                        isPlaying: isPlaying,
                        progress: progress,
                        leftLevel: meterLeft,
                        rightLevel: meterRight
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.25), value: style)
        }
    }

    private var toolbarRow: some View {
        HStack(alignment: .center, spacing: 12) {
            stylePicker
            trailing()
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DeckStyle.allCases) { option in
                    Button {
                        style = option
                    } label: {
                        Text(option.title.uppercased())
                            .font(HarborFont.panel(9))
                            .tracking(0.8)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(style == option ? HarborColor.faceplate : HarborColor.ivoryDim)
                            .background(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(style == option ? HarborColor.amber : HarborColor.faceplate.opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .stroke(HarborColor.aluminumDark, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

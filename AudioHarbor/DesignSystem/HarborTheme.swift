import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// Night listening room — ink chassis, lacquer faceplate, filament amber.
/// Warm and analog, never purple / neon / dashboard.
enum HarborColor {
    static let chassis = Color(red: 0.07, green: 0.06, blue: 0.055)
    static let chassisLight = Color(red: 0.13, green: 0.11, blue: 0.09)
    static let walnut = Color(red: 0.30, green: 0.20, blue: 0.12)
    static let faceplate = Color(red: 0.085, green: 0.078, blue: 0.072)
    static let faceplateLift = Color(red: 0.12, green: 0.11, blue: 0.10)
    static let aluminum = Color(red: 0.74, green: 0.71, blue: 0.66)
    static let aluminumDark = Color(red: 0.38, green: 0.35, blue: 0.31)
    static let brass = Color(red: 0.78, green: 0.58, blue: 0.28)
    static let ivory = Color(red: 0.94, green: 0.91, blue: 0.85)
    static let ivoryDim = Color(red: 0.62, green: 0.58, blue: 0.51)
    static let amber = Color(red: 0.98, green: 0.72, blue: 0.22)
    static let amberGlow = Color(red: 1.00, green: 0.58, blue: 0.12).opacity(0.42)
    static let powerLED = Color(red: 0.42, green: 0.92, blue: 0.52)
    static let danger = Color(red: 0.82, green: 0.32, blue: 0.26)

    static let background = chassis
    static let surface = faceplate
    static let elevated = faceplateLift
    static let textPrimary = ivory
    static let textSecondary = ivoryDim
    static let accent = amber
    static let accentSoft = amberGlow
}

private struct HarborPlayingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var harborPlaying: Bool {
        get { self[HarborPlayingKey.self] }
        set { self[HarborPlayingKey.self] = newValue }
    }
}

enum HarborFont {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func panel(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

enum Brand {
    static let name = "Audio Harbor"
    static let subtitle = "Local audiophile player"
    static let tagline = "Local. Bit-perfect. Calm."
}

struct HarborLamp: View {
    var lit: Bool = true
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(HarborColor.faceplate)
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [HarborColor.brass.opacity(0.9), HarborColor.aluminumDark],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
            Circle()
                .fill(lit ? HarborColor.amber : HarborColor.aluminumDark)
                .frame(width: size * 0.38, height: size * 0.38)
                .shadow(color: lit ? HarborColor.amber.opacity(0.85) : .clear, radius: lit ? 8 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BrandMark: View {
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 10 : 14) {
            HarborLamp(lit: true, size: compact ? 22 : 34)
            VStack(alignment: .leading, spacing: compact ? 2 : 5) {
                Text(Brand.name)
                    .font(HarborFont.display(compact ? 17 : 28))
                    .foregroundStyle(HarborColor.ivory)
                    .lineLimit(1)
                Text(Brand.subtitle)
                    .font(HarborFont.panel(compact ? 9 : 11))
                    .tracking(0.6)
                    .foregroundStyle(HarborColor.brass)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Brand.name). \(Brand.subtitle)")
    }
}

struct EngravedLabel: View {
    let text: String
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(HarborFont.panel(size))
            .tracking(1.6)
            .foregroundStyle(HarborColor.ivoryDim)
    }
}

struct ScreenHeader<Trailing: View>: View {
    let kicker: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(
        kicker: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.kicker = kicker
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                EngravedLabel(text: kicker)
                Text(title)
                    .font(HarborFont.display(30))
                    .foregroundStyle(HarborColor.ivory)
                if let subtitle {
                    Text(subtitle)
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(kicker: String, title: String, subtitle: String? = nil) {
        self.init(kicker: kicker, title: title, subtitle: subtitle) { EmptyView() }
    }
}

enum HarborButtonKind {
    case primary
    case secondary
}

struct HarborButton: View {
    let title: String
    var systemImage: String?
    var kind: HarborButtonKind = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(HarborFont.title(13))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(kind == .primary ? HarborColor.chassis : HarborColor.ivory)
            .background(kind == .primary ? HarborColor.amber : HarborColor.faceplateLift)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        kind == .primary ? HarborColor.brass.opacity(0.35) : HarborColor.aluminumDark.opacity(0.7),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct HarborIconButton: View {
    let systemName: String
    var help: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(HarborColor.chassis)
                .frame(width: 30, height: 30)
                .background(HarborColor.amber)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: HarborColor.amber.opacity(0.28), radius: 6, y: 1)
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }
}

struct HarborArtwork: View {
    var hash: String?
    var data: Data?
    var size: CGFloat = 48
    var corner: CGFloat = 7

    @State private var image: Image?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(HarborColor.faceplateLift)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "opticaldisc")
                    .font(.system(size: size * 0.32, weight: .regular))
                    .foregroundStyle(HarborColor.ivoryDim.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(HarborColor.aluminumDark.opacity(0.55), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        .task(id: "\(hash ?? "")-\(data?.count ?? 0)") {
            let payload = data ?? hash.flatMap { ArtworkCache.shared.load($0) }
            image = Self.makeImage(payload)
        }
    }

    private static func makeImage(_ data: Data?) -> Image? {
        guard let data else { return nil }
        #if os(macOS)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #else
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #endif
        return nil
    }
}

struct FormatBadge: View {
    let format: AudioFormat
    let sampleRateHz: Int?
    let bitDepth: Int?
    /// Active output path ("Shared", "Exclusive · DoP", …). Deck only — the
    /// catalogue lists files, which have no path until they play.
    var path: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(format.rawValue)
            if let rateDetail {
                Text("·")
                Text(rateDetail)
            }
            if let path, !path.isEmpty {
                Text("·")
                Text(path)
            }
        }
        .font(HarborFont.mono(10))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(HarborColor.amber)
        .background(HarborColor.amber.opacity(0.08))
        .overlay(
            Capsule(style: .continuous)
                .stroke(HarborColor.brass.opacity(0.45), lineWidth: 1)
        )
        .clipShape(Capsule(style: .continuous))
    }

    /// "16/44.1k" when the depth is known, plain "44.1k" otherwise — lossy files
    /// (MP3, AAC) carry no bit depth, and dropping the rate with it left just the format.
    private var rateDetail: String? {
        guard let sampleRateHz else { return nil }
        let rate = Self.formatRate(sampleRateHz)
        guard let bitDepth else { return rate }
        return "\(bitDepth)/\(rate)"
    }

    private static func formatRate(_ hz: Int) -> String {
        if hz >= 1000 {
            let kHz = Double(hz) / 1000
            return kHz.rounded() == kHz ? "\(Int(kHz))k" : String(format: "%.1fk", kHz)
        }
        return "\(hz)"
    }
}

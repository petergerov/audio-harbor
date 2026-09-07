import SwiftUI

/// Analog receiver palette — walnut chassis, black faceplate, amber lamps.
/// Avoids flat cream / terracotta / purple AI defaults.
enum HarborColor {
    static let chassis = Color(red: 0.22, green: 0.16, blue: 0.11)      // walnut
    static let chassisLight = Color(red: 0.32, green: 0.24, blue: 0.16)
    static let faceplate = Color(red: 0.10, green: 0.09, blue: 0.08)    // matte black panel
    static let aluminum = Color(red: 0.72, green: 0.70, blue: 0.66)
    static let aluminumDark = Color(red: 0.45, green: 0.43, blue: 0.40)
    static let ivory = Color(red: 0.91, green: 0.88, blue: 0.82)
    static let ivoryDim = Color(red: 0.70, green: 0.66, blue: 0.58)
    static let amber = Color(red: 1.00, green: 0.68, blue: 0.12)         // lamp / needle
    static let amberGlow = Color(red: 1.00, green: 0.55, blue: 0.05).opacity(0.35)
    static let powerLED = Color(red: 0.35, green: 0.95, blue: 0.45)
    static let danger = Color(red: 0.78, green: 0.28, blue: 0.22)

    // Compatibility aliases used across views
    static let background = chassis
    static let surface = faceplate
    static let elevated = aluminumDark
    static let textPrimary = ivory
    static let textSecondary = ivoryDim
    static let accent = amber
    static let accentSoft = amberGlow
}

enum HarborFont {
    /// Brand / track titles — soft serif like engraved receiver badging
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    /// Panel silk-screen labels
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

struct BrandMark: View {
    var compact: Bool = false

    var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: compact ? 3 : 8) {
            Text(Brand.name.uppercased())
                .font(HarborFont.display(compact ? 18 : 32))
                .tracking(compact ? 1.5 : 3)
                .foregroundStyle(HarborColor.ivory)
            Text(Brand.subtitle.uppercased())
                .font(HarborFont.panel(compact ? 9 : 11))
                .tracking(1.6)
                .foregroundStyle(HarborColor.amber)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
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
            .tracking(1.8)
            .foregroundStyle(HarborColor.ivoryDim)
    }
}

struct FormatBadge: View {
    let format: AudioFormat
    let sampleRateHz: Int?
    let bitDepth: Int?

    var body: some View {
        HStack(spacing: 5) {
            Text(format.rawValue)
                .font(HarborFont.mono(10))
            if let bitDepth, let sampleRateHz {
                Text("·")
                Text("\(bitDepth)/\(Self.formatRate(sampleRateHz))")
                    .font(HarborFont.mono(10))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(HarborColor.amber)
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(HarborColor.aluminumDark, lineWidth: 1)
        )
    }

    private static func formatRate(_ hz: Int) -> String {
        if hz >= 1000 {
            let kHz = Double(hz) / 1000
            return kHz.rounded() == kHz ? "\(Int(kHz))k" : String(format: "%.1fk", kHz)
        }
        return "\(hz)"
    }
}

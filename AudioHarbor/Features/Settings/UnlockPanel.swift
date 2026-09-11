import SwiftUI

struct UnlockPanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let license = appModel.license

        VStack(alignment: .leading, spacing: 12) {
            Text("Free to install for everyone. Full playback for seven days, then a one-time unlock. No subscription.")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(license.statusHeadline)
                    .font(HarborFont.title(14))
                    .foregroundStyle(statusColor)
                if case .unlocked = license.status {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(HarborColor.amber)
                }
                Spacer(minLength: 0)
            }

            Text(license.statusDetail)
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)

            if case .unlocked = license.status {
                EmptyView()
            } else {
                HarborButton(
                    title: license.isPurchasing ? "Purchasing…" : "Unlock · \(license.priceText)",
                    systemImage: "key.fill"
                ) {
                    Task { await license.purchase() }
                }
                .disabled(license.isPurchasing || license.isRestoring)

                HarborButton(
                    title: license.isRestoring ? "Restoring…" : "Restore Purchase",
                    systemImage: "arrow.clockwise",
                    kind: .secondary
                ) {
                    Task { await license.restore() }
                }
                .disabled(license.isPurchasing || license.isRestoring)
            }

            if let message = license.message, !message.isEmpty {
                Text(message)
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.ivoryDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if DEBUG
            HStack(spacing: 8) {
                Button("Debug: expire trial") {
                    license.debugExpireTrial()
                }
                Button("Debug: reset trial") {
                    license.debugResetTrial()
                }
            }
            .font(HarborFont.panel(10))
            .foregroundStyle(HarborColor.ivoryDim)
            .buttonStyle(.plain)
            #endif
        }
    }

    private var statusColor: Color {
        switch appModel.license.status {
        case .unlocked: HarborColor.amber
        case .trial: HarborColor.ivory
        case .expired: HarborColor.danger
        }
    }
}

struct UnlockSheet: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                kicker: "License",
                title: "Unlock Audio Harbor",
                subtitle: "The trial has ended. Catalogue stays; playback needs a one-time purchase."
            )
            UnlockPanel()
            HStack {
                Spacer()
                Button("Close") {
                    appModel.license.isUnlockPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(HarborColor.ivoryDim)
                .font(HarborFont.panel(12))
            }
        }
        .padding(22)
        .frame(minWidth: 360, maxWidth: 440)
        .background(HarborColor.chassis)
    }
}

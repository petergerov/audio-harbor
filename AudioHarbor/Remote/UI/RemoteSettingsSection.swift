import SwiftUI

/// Settings panel: enable LAN remote, show pairing code, manage paired devices.
struct RemoteSettingsSection: View {
    @Bindable var remote: RemoteControlService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Control this Mac from another Audio Harbor on the same network. Music still plays here on the DAC.")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(
                get: { remote.isEnabled },
                set: { remote.setEnabled($0) }
            )) {
                Text("Allow Remote Control")
                    .font(HarborFont.title(14))
                    .foregroundStyle(HarborColor.ivory)
            }
            .toggleStyle(.switch)
            .tint(HarborColor.amber)

            Text(remote.statusText)
                .font(HarborFont.mono(11))
                .foregroundStyle(HarborColor.ivoryDim)

            if remote.isEnabled {
                pairingBlock
                pairedDevicesBlock
            }

            Text("LAN only for now. Pairing uses a one-time code; transport encryption comes next.")
                .font(HarborFont.body(12))
                .foregroundStyle(HarborColor.ivoryDim)
        }
    }

    @ViewBuilder
    private var pairingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pairing code")
                    .font(HarborFont.title(14))
                    .foregroundStyle(HarborColor.ivory)
                Spacer()
                Button("New Code") {
                    remote.refreshPairingCode()
                }
                .buttonStyle(.plain)
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.amber)
            }

            if let code = remote.pairingCode {
                Text(code)
                    .font(HarborFont.mono(28))
                    .foregroundStyle(HarborColor.amber)
                    .tracking(6)
                if let expires = remote.pairingExpiresAt {
                    Text("Expires \(expires, style: .time)")
                        .font(HarborFont.body(12))
                        .foregroundStyle(HarborColor.ivoryDim)
                }
            } else {
                Text("Generate a code, then enter it on the remote device.")
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.ivoryDim)
            }

            if remote.connectedClientCount > 0 {
                Text("\(remote.connectedClientCount) connected")
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.amber)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var pairedDevicesBlock: some View {
        if !remote.pairedDevices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Paired devices")
                        .font(HarborFont.title(14))
                        .foregroundStyle(HarborColor.ivory)
                    Spacer()
                    Button("Revoke All") {
                        remote.revokeAll()
                    }
                    .buttonStyle(.plain)
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.ivoryDim)
                }

                ForEach(remote.pairedDevices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(HarborFont.body(13))
                                .foregroundStyle(HarborColor.ivory)
                            Text(device.platform)
                                .font(HarborFont.body(11))
                                .foregroundStyle(HarborColor.ivoryDim)
                        }
                        Spacer()
                        Button("Revoke") {
                            remote.revoke(device)
                        }
                        .buttonStyle(.plain)
                        .font(HarborFont.body(12))
                        .foregroundStyle(HarborColor.amber)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 4)
        }
    }
}

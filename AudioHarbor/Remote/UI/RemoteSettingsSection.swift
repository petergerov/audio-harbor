import SwiftUI

/// Settings panel: enable LAN remote (Mac), discover & control other Harbors (all platforms).
struct RemoteSettingsSection: View {
    @Bindable var remote: RemoteControlService
    @Bindable var browser: RemoteBrowser
    @Bindable var controller: RemoteController
    @State private var isControllerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            serverBlock
            Divider().overlay(HarborColor.aluminumDark.opacity(0.45))
            #endif

            controlNearbyBlock

            Text(footerText)
                .font(HarborFont.body(12))
                .foregroundStyle(HarborColor.ivoryDim)
        }
        .onAppear { browser.start() }
        .onDisappear {
            if !isControllerPresented {
                browser.stop()
            }
        }
        .sheet(isPresented: $isControllerPresented) {
            RemoteControllerView(controller: controller)
                #if os(macOS)
                .frame(minWidth: 440, minHeight: 640)
                #endif
        }
    }

    private var footerText: String {
        #if os(macOS)
        "LAN only for now. Pairing uses a one-time code; transport encryption comes next."
        #else
        "Find a Mac running Audio Harbor with Remote enabled. Music plays on the Mac DAC — this phone steers."
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var serverBlock: some View {
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
    #endif

    @ViewBuilder
    private var controlNearbyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Control nearby")
                    .font(HarborFont.title(14))
                    .foregroundStyle(HarborColor.ivory)
                Spacer()
                if controller.phase == .connected || controller.phase == .needsPairing {
                    Button("Open Remote") {
                        isControllerPresented = true
                    }
                    .buttonStyle(.plain)
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.amber)
                }
            }

            Text(browser.statusText)
                .font(HarborFont.mono(11))
                .foregroundStyle(HarborColor.ivoryDim)

            if browser.servers.isEmpty {
                Text("Turn on Allow Remote Control on the Mac you want to steer.")
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.ivoryDim)
            } else {
                ForEach(browser.servers) { server in
                    Button {
                        controller.connect(to: server)
                        isControllerPresented = true
                    } label: {
                        HStack {
                            Image(systemName: "hifispeaker.fill")
                                .foregroundStyle(HarborColor.amber)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(HarborFont.body(13))
                                    .foregroundStyle(HarborColor.ivory)
                                Text(subtitle(for: server))
                                    .font(HarborFont.body(11))
                                    .foregroundStyle(HarborColor.ivoryDim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(HarborColor.aluminumDark)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func subtitle(for server: RemoteServerEndpoint) -> String {
        if RemoteClientStore.isPaired(with: server) {
            return "Paired · tap to control"
        }
        return "Tap to pair"
    }
}

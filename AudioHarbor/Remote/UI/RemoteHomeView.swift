import SwiftUI

/// iPhone home: discover a Mac Harbor and steer it. Not a second local library.
struct RemoteHomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isSettingsPresented = false

    var body: some View {
        @Bindable var controller = appModel.remoteController
        @Bindable var browser = appModel.remoteBrowser

        Group {
            switch controller.phase {
            case .connected, .needsPairing, .connecting:
                RemoteControllerView(controller: controller)
            case .idle, .failed:
                discovery(browser: browser, controller: controller)
            }
        }
        .onAppear { browser.start() }
        .onChange(of: controller.phase) { _, phase in
            switch phase {
            case .idle, .failed:
                browser.start()
            case .connected, .needsPairing, .connecting:
                break
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                iosSettings
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isSettingsPresented = false }
                        }
                    }
            }
        }
    }

    private var iosSettings: some View {
        ReceiverChassis {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Settings", trailingAlignment: .center) {
                        EmptyView()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        EngravedLabel(text: "About")
                        LabeledContent("App", value: Brand.name)
                            .foregroundStyle(HarborColor.ivory)
                        LabeledContent("Role", value: "Remote")
                            .foregroundStyle(HarborColor.ivory)
                        LabeledContent("Version", value: Brand.versionLabel)
                            .foregroundStyle(HarborColor.ivory)
                        Text("This iPhone steers Audio Harbor on your Mac. Playback stays on the Mac DAC.")
                            .font(HarborFont.body(13))
                            .foregroundStyle(HarborColor.ivoryDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .faceplate()

                    VStack(alignment: .leading, spacing: 12) {
                        EngravedLabel(text: "License")
                        UnlockPanel()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .faceplate()
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .environment(appModel)
    }

    @ViewBuilder
    private func discovery(browser: RemoteBrowser, controller: RemoteController) -> some View {
        ReceiverChassis {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Audio Harbor")
                            .font(HarborFont.display(28))
                            .foregroundStyle(HarborColor.ivory)
                        Text("Remote")
                            .font(HarborFont.title(16))
                            .foregroundStyle(HarborColor.amber)
                        Text("Music plays on your Mac. This phone steers.")
                            .font(HarborFont.body(14))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .frame(width: 40, height: 40)
                            .background(HarborColor.faceplateLift)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }

                if case .failed(let message) = controller.phase {
                    Text(message)
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.amber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HarborColor.faceplateLift)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nearby")
                        .font(HarborFont.title(14))
                        .foregroundStyle(HarborColor.ivory)
                    Text(browser.statusText)
                        .font(HarborFont.mono(11))
                        .foregroundStyle(HarborColor.ivoryDim)

                    if browser.servers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No Mac found yet.")
                                .font(HarborFont.body(14))
                                .foregroundStyle(HarborColor.ivory)
                            Text("On the Mac: open Audio Harbor → Settings → Remote → Allow Remote Control.")
                                .font(HarborFont.body(13))
                                .foregroundStyle(HarborColor.ivoryDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HarborColor.faceplateLift)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        ForEach(browser.servers) { server in
                            Button {
                                controller.connect(to: server)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "hifispeaker.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(HarborColor.amber)
                                        .frame(width: 44, height: 44)
                                        .background(HarborColor.amber.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(HarborFont.title(15))
                                            .foregroundStyle(HarborColor.ivory)
                                        Text(subtitle(for: server))
                                            .font(HarborFont.body(12))
                                            .foregroundStyle(HarborColor.ivoryDim)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(HarborColor.aluminumDark)
                                }
                                .padding(14)
                                .background(HarborColor.faceplateLift)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func subtitle(for server: RemoteServerEndpoint) -> String {
        if let id = server.serverID, RemoteClientStore.token(forServerID: id) != nil {
            return "Paired · tap to control"
        }
        return "Tap to pair with a code"
    }
}

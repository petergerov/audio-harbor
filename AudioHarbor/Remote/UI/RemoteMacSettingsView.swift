import SwiftUI

/// Mac Settings controlled from the remote — Output, Sharing, Directories, About.
struct RemoteMacSettingsView: View {
    @Bindable var controller: RemoteController
    /// Sheet presentation shows Done; the Settings tab embeds this without it.
    var showsDismissButton: Bool = true
    var onDisconnect: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showDevicePicker = false

    var body: some View {
        NavigationStack {
            ReceiverChassis(contentPadding: settingsChassisPadding) {
                Group {
                    if !controller.canEditSettings {
                        Text("This Mac’s Audio Harbor is too old for remote Settings. Update it to change Output, Sharing, and Directories from here.")
                            .font(HarborFont.body(13))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.top, 8)
                    } else if let settings = controller.settings {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                outputPanel(settings.output)
                                sharingPanel(settings.sharing)
                                directoriesPanel(settings)
                                aboutPanel(settings.about)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView()
                            .tint(HarborColor.amber)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Chassis already pads; a second band pinches the phone.
                #if os(macOS)
                .padding(.horizontal, 16)
                #endif
                .padding(.top, 8)
            }
            .navigationTitle(showsDismissButton ? "Mac Settings" : "Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(HarborColor.amber)
                    }
                } else if let onDisconnect {
                    ToolbarItem(placement: .automatic) {
                        Button("Disconnect", action: onDisconnect)
                            .foregroundStyle(HarborColor.amber)
                    }
                }
            }
            .sheet(isPresented: $showDevicePicker) {
                if let output = controller.settings?.output {
                    RemoteOutputDevicePicker(
                        output: output,
                        onSelect: { uid in
                            controller.applySettings(.outputDevice(uid: uid))
                            showDevicePicker = false
                        },
                        onDismiss: { showDevicePicker = false }
                    )
                }
            }
            .onAppear { controller.refreshSettings() }
        }
    }

    /// Phone Settings spans nearly the full width; the Mac sheet keeps the usual inset.
    private var settingsChassisPadding: CGFloat {
        #if os(iOS)
        8
        #else
        16
        #endif
    }

    // MARK: - Output

    @ViewBuilder
    private func outputPanel(_ output: RemoteOutputSettingsDTO) -> some View {
        panel(title: "Output") {
            Text(output.isNetworkSelected
                ? "How Audio Harbor prepares audio for the network player."
                : "How sound leaves the Mac.")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)

            deviceMenu(output)

            if output.isNetworkSelected {
                networkRadios(output)
            } else {
                localRadios(output)
            }

            dsdLevelPicker(output.dsdPCMLevel)
        }
    }

    private func deviceMenu(_ output: RemoteOutputSettingsDTO) -> some View {
        let title: String = {
            if output.selectedUID == nil { return "System Output" }
            if let device = output.devices.first(where: { $0.uid == output.selectedUID }) {
                return Self.deviceDisplayName(device)
            }
            return output.selectedName ?? output.selectedUID ?? "Device"
        }()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Device")
                .font(HarborFont.title(14))
                .foregroundStyle(HarborColor.ivory)

            Button {
                showDevicePicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hifispeaker.fill")
                        .foregroundStyle(HarborColor.amber)
                        .frame(width: 22)
                    Text(title)
                        .font(HarborFont.body(14))
                        .foregroundStyle(HarborColor.ivory)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HarborColor.amber)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(HarborColor.faceplateLift)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Output device, \(title)")

            if output.isDeviceMissing {
                Text(output.isNetworkSelected
                    ? "Not on the network right now."
                    : "Not connected right now.")
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.amber)
            }
        }
    }

    static func deviceDisplayName(_ device: RemoteOutputDeviceDTO) -> String {
        if device.kind == "network" {
            return "\(device.name) (Network player)"
        }
        return device.supportsExclusive ? "\(device.name) · DAC" : device.name
    }

    @ViewBuilder
    private func localRadios(_ output: RemoteOutputSettingsDTO) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(OutputMode.allCases.enumerated()), id: \.element.id) { index, mode in
                if index > 0 {
                    Divider().overlay(HarborColor.aluminumDark.opacity(0.45))
                }
                let available: Bool = {
                    switch mode {
                    case .shared: true
                    case .exclusive: output.canExclusive
                    case .dop: output.canDoP
                    }
                }()
                let selected = output.effectiveOutputMode == mode.rawValue
                radioRow(
                    title: mode.title,
                    blurb: mode.blurb,
                    detail: selected ? mode.detail : nil,
                    selected: selected,
                    available: available
                ) {
                    controller.applySettings(.outputMode(mode.rawValue))
                }
            }
        }
    }

    @ViewBuilder
    private func networkRadios(_ output: RemoteOutputSettingsDTO) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(NetworkOutputChoice.allCases.enumerated()), id: \.element.id) { index, choice in
                if index > 0 {
                    Divider().overlay(HarborColor.aluminumDark.opacity(0.45))
                }
                let available = choice != .dsd || output.supportsNativeDSD
                let selected = output.networkChoice == choice.rawValue
                radioRow(
                    title: choice.title,
                    blurb: choice.blurb,
                    detail: selected ? choice.detail : nil,
                    selected: selected,
                    available: available
                ) {
                    controller.applySettings(.networkChoice(choice.rawValue))
                }
            }
        }
    }

    private func dsdLevelPicker(_ level: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dial.medium.fill")
                .foregroundStyle(HarborColor.amber)
                .frame(width: 22)
            Text("DSD as PCM")
                .font(HarborFont.title(14))
                .foregroundStyle(HarborColor.ivory)
            Spacer()
            Picker("DSD as PCM", selection: Binding(
                get: { level },
                set: { controller.applySettings(.dsdPCMLevel($0)) }
            )) {
                ForEach(DSDPCMLevel.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sharing / Directories / About

    @ViewBuilder
    private func sharingPanel(_ sharing: RemoteSharingSettingsDTO) -> some View {
        panel(title: "Sharing") {
            Text("Players on the Mac's network can browse the library and play the files themselves.")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)

            Toggle(isOn: Binding(
                get: { sharing.enabled },
                set: { controller.applySettings(.sharingEnabled($0)) }
            )) {
                Text("Share Library on the Network")
                    .font(HarborFont.title(14))
                    .foregroundStyle(HarborColor.ivory)
            }
            .tint(HarborColor.amber)

            Text(sharing.statusText)
                .font(HarborFont.mono(11))
                .foregroundStyle(HarborColor.ivoryDim)

            if sharing.blockedByLicense {
                Text("The trial has ended — players can browse, but not play, until Audio Harbor is unlocked.")
                    .font(HarborFont.body(12))
                    .foregroundStyle(HarborColor.amber)
            }
        }
    }

    @ViewBuilder
    private func directoriesPanel(_ settings: SettingsSnapshot) -> some View {
        panel(title: "Directories") {
            Text("Folders connected on the Mac. Add or remove them in Settings on the Mac.")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)

            if settings.directories.isEmpty {
                Text("No directories connected yet.")
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.ivoryDim)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(settings.directories.enumerated()), id: \.element.id) { index, folder in
                        if index > 0 {
                            Divider().overlay(HarborColor.aluminumDark.opacity(0.45))
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(HarborColor.amber)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(folder.name)
                                    .font(HarborFont.title(14))
                                    .foregroundStyle(HarborColor.ivory)
                                Text(folder.displayPath)
                                    .font(HarborFont.mono(11))
                                    .foregroundStyle(HarborColor.ivoryDim)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                    }
                }
            }

            Button {
                controller.applySettings(.rebuildIndex)
            } label: {
                Label(
                    settings.isScanning ? "Rebuilding…" : "Rebuild Index",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(HarborFont.title(14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(HarborColor.ivory)
                .background(HarborColor.faceplateLift)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(settings.isScanning || settings.directories.isEmpty)
        }
    }

    @ViewBuilder
    private func aboutPanel(_ about: RemoteAboutDTO) -> some View {
        panel(title: "About") {
            LabeledContent("App", value: about.appName)
                .foregroundStyle(HarborColor.ivory)
            LabeledContent("Version", value: about.versionLabel)
                .foregroundStyle(HarborColor.ivory)
            Text(about.tagline)
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
            Text(about.licenseHeadline)
                .font(HarborFont.title(14))
                .foregroundStyle(HarborColor.ivory)
                .padding(.top, 4)
            Text(about.licenseDetail)
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func radioRow(
        title: String,
        blurb: String,
        detail: String?,
        selected: Bool,
        available: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !selected, available else { return }
            action()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? HarborColor.amber : HarborColor.aluminumDark)
                    .padding(.top, 2)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(HarborFont.title(14))
                        .foregroundStyle(HarborColor.ivory)
                    Text(blurb)
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                    if let detail {
                        Text(detail)
                            .font(HarborFont.body(13))
                            .foregroundStyle(HarborColor.ivoryDim)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .opacity(available ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EngravedLabel(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
        .faceplate(compact: true)
        #else
        .faceplate()
        #endif
    }
}

/// Scrollable full-width picker for Mac outputs — menus on iOS clip long lists and names.
private struct RemoteOutputDevicePicker: View {
    let output: RemoteOutputSettingsDTO
    let onSelect: (String?) -> Void
    let onDismiss: () -> Void

    private var local: [RemoteOutputDeviceDTO] {
        output.devices.filter { $0.kind == "local" }
    }

    private var network: [RemoteOutputDeviceDTO] {
        output.devices.filter { $0.kind == "network" }
    }

    var body: some View {
        NavigationStack {
            ReceiverChassis {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        group(title: nil) {
                            row(
                                title: "System Output",
                                selected: output.selectedUID == nil
                            ) {
                                onSelect(nil)
                            }
                        }
                        if !local.isEmpty {
                            group(title: "This Host") {
                                ForEach(Array(local.enumerated()), id: \.element.id) { index, device in
                                    if index > 0 {
                                        Divider().overlay(HarborColor.aluminumDark.opacity(0.45))
                                    }
                                    row(
                                        title: RemoteMacSettingsView.deviceDisplayName(device),
                                        selected: output.selectedUID == device.uid
                                    ) {
                                        onSelect(device.uid)
                                    }
                                }
                            }
                        }
                        if !network.isEmpty {
                            group(title: "Network Players") {
                                ForEach(Array(network.enumerated()), id: \.element.id) { index, device in
                                    if index > 0 {
                                        Divider().overlay(HarborColor.aluminumDark.opacity(0.45))
                                    }
                                    row(
                                        title: RemoteMacSettingsView.deviceDisplayName(device),
                                        selected: output.selectedUID == device.uid
                                    ) {
                                        onSelect(device.uid)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Output Device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .foregroundStyle(HarborColor.amber)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func group<Content: View>(
        title: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                EngravedLabel(text: title)
            }
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .faceplate()
        }
    }

    private func row(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? HarborColor.amber : HarborColor.aluminumDark)
                    .frame(width: 24)
                Text(title)
                    .font(HarborFont.body(15))
                    .foregroundStyle(HarborColor.ivory)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

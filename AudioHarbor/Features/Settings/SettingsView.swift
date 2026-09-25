import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isImporterPresented = false

    var body: some View {
        @Bindable var playback = appModel.playback

        ReceiverChassis {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        ScreenHeader(
                            title: "Settings",
                            subtitle: "How music plays, your folders, and the 7-day trial."
                        )
                    }

                    panel(title: "Output") {
                        Text("How sound leaves the app. If you are unsure, leave Shared on.")
                            .font(HarborFont.body(13))
                            .foregroundStyle(HarborColor.ivoryDim)

                        #if os(macOS)
                        outputDevicePicker
                        #endif

                        VStack(spacing: 0) {
                            ForEach(Array(OutputMode.allCases.enumerated()), id: \.element.id) { index, mode in
                                if index > 0 {
                                    Divider().overlay(HarborColor.aluminumDark.opacity(0.45))
                                }
                                outputChoice(mode)
                            }
                        }

                        #if os(macOS)
                        Text(outputFootnote)
                            .font(HarborFont.body(12))
                            .foregroundStyle(HarborColor.ivoryDim)
                        #else
                        Text("On iPhone, playback always uses Shared. Exclusive and DoP are Mac-only.")
                            .font(HarborFont.body(12))
                            .foregroundStyle(HarborColor.ivoryDim)
                        #endif

                        Text("With effects in the rack, Exclusive and DoP keep the DAC but send processed PCM — not bit-perfect, and DSD as PCM. Clear the rack for bit-perfect and DoP.")
                            .font(HarborFont.body(12))
                            .foregroundStyle(HarborColor.ivoryDim)
                    }

                    panel(title: "License") {
                        UnlockPanel()
                    }

                    panel(title: "Directories") {
                        directoriesSection
                    }

                    panel(title: "About") {
                        LabeledContent("App", value: Brand.name)
                            .foregroundStyle(HarborColor.ivory)
                        LabeledContent("Version", value: Brand.versionLabel)
                            .foregroundStyle(HarborColor.ivory)
                        Text(Brand.tagline)
                            .font(HarborFont.body(13))
                            .foregroundStyle(HarborColor.ivoryDim)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appModel.library.addFolders(urls: urls)
            }
        }
        #if os(iOS)
        .navigationTitle("Settings")
        #endif
    }

    private var outputFootnote: String {
        let playback = appModel.playback
        let status = playback.outputStatus
        let name = status.activeDevice?.name ?? "This output"
        if status.canDoP {
            return "\(name) takes Exclusive and DoP."
        }
        if status.canExclusive {
            if playback.outputMode == .dop {
                return "\(name) cannot run 176.4 kHz, the rate DoP needs — playing Exclusive, DSD as PCM. DoP is selected again on a DSD DAC."
            }
            return "\(name) takes Exclusive. DoP is off: it cannot run 176.4 kHz, the rate DoP needs."
        }
        if playback.outputMode != .shared {
            return "\(name) is not an external DAC — playing Shared. \(playback.outputMode.title) is selected again when a DAC is the output."
        }
        return "Exclusive and DoP need an external DAC (USB). Built-in speakers, headphones, Bluetooth, and AirPlay stay on Shared."
    }

    #if os(macOS)
    /// Which device Audio Harbor plays to — independent of the macOS system output, so alerts
    /// and other apps can stay on the speakers while music goes to the DAC.
    @ViewBuilder
    private var outputDevicePicker: some View {
        let playback = appModel.playback
        let status = playback.outputStatus

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "hifispeaker.fill")
                    .foregroundStyle(HarborColor.amber)
                    .frame(width: 22)
                Text("Device")
                    .font(HarborFont.title(14))
                    .foregroundStyle(HarborColor.ivory)
                Spacer(minLength: 8)
                Menu {
                    Button {
                        playback.outputDeviceUID = nil
                    } label: {
                        deviceMenuLabel("System Output", selected: playback.outputDeviceUID == nil)
                    }
                    if !status.devices.isEmpty {
                        Divider()
                    }
                    ForEach(sortedDevices(status.devices)) { device in
                        Button {
                            playback.outputDeviceUID = device.uid
                        } label: {
                            deviceMenuLabel(
                                "\(device.name) — \(device.capabilityLabel)",
                                selected: playback.outputDeviceUID == device.uid
                            )
                        }
                    }
                    if playback.isOutputDeviceMissing, let uid = playback.outputDeviceUID {
                        Divider()
                        Button {} label: {
                            deviceMenuLabel(
                                "\(playback.outputDeviceName ?? uid) — not connected",
                                selected: true
                            )
                        }
                        .disabled(true)
                    }
                } label: {
                    Text(deviceTitle)
                        .font(HarborFont.body(13))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("The device Audio Harbor plays to. System Output follows macOS.")
            }

            Text(deviceCaption)
                .font(HarborFont.body(12))
                .foregroundStyle(playback.isOutputDeviceMissing ? HarborColor.amber : HarborColor.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var deviceTitle: String {
        let playback = appModel.playback
        guard let uid = playback.outputDeviceUID else { return "System Output" }
        return playback.outputDeviceName ?? uid
    }

    private var deviceCaption: String {
        let playback = appModel.playback
        let active = playback.outputStatus.activeDevice
        let activeText = active.map { "\($0.name) · \($0.capabilityLabel)" } ?? "No output"
        if playback.isOutputDeviceMissing {
            let picked = playback.outputDeviceName ?? "The picked device"
            return "\(picked) is not connected — playing on \(activeText). Plug it in and it is used from the next track."
        }
        if playback.outputDeviceUID == nil {
            return "Follows macOS: \(activeText)."
        }
        return activeText
    }

    /// External DACs first — they are why the picker exists — then the rest, by name.
    private func sortedDevices(_ devices: [OutputDevice]) -> [OutputDevice] {
        devices.sorted {
            if $0.supportsExclusive != $1.supportsExclusive { return $0.supportsExclusive }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private func deviceMenuLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
    #endif

    @ViewBuilder
    private func outputChoice(_ mode: OutputMode) -> some View {
        let selected = appModel.playback.effectiveOutputMode == mode
        // Exclusive needs an external DAC as the output, DoP one that runs 176.4 kHz (never on iOS).
        let available = appModel.playback.isAvailable(mode)

        Button {
            // Tapping the Shared that stands in for an unplugged DAC must not forget Exclusive / DoP.
            guard !selected else { return }
            appModel.playback.outputMode = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? HarborColor.amber : HarborColor.aluminumDark)
                    .padding(.top, 2)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(mode.title)
                            .font(HarborFont.title(14))
                            .foregroundStyle(HarborColor.ivory)
                        if mode == .shared {
                            Text("Recommended")
                                .font(HarborFont.panel(10))
                                .foregroundStyle(HarborColor.amber)
                        }
                        if mode.isMacOnly {
                            Text("Mac")
                                .font(HarborFont.panel(10))
                                .foregroundStyle(HarborColor.ivoryDim)
                        }
                    }
                    Text(mode.blurb)
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                    if selected {
                        Text(mode.detail)
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
        .accessibilityLabel("\(mode.title). \(mode.blurb)")
        .accessibilityHint(mode.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var directoriesSection: some View {
        Text("Music directories connected to the catalogue.")
            .font(HarborFont.body(13))
            .foregroundStyle(HarborColor.ivoryDim)

        if appModel.library.isScanning {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(HarborColor.amber)
                if let progress = appModel.library.scanProgressText {
                    Text(progress)
                        .font(HarborFont.mono(11))
                        .foregroundStyle(HarborColor.amber)
                }
            }
        }

        if appModel.library.folders.isEmpty {
            Text("No directories connected yet.")
                .font(HarborFont.body(13))
                .foregroundStyle(HarborColor.ivoryDim)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(appModel.library.folders.enumerated()), id: \.element.id) { index, folder in
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
                        Spacer(minLength: 8)
                        Button("Remove", role: .destructive) {
                            appModel.library.removeFolder(folder)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(HarborColor.danger)
                        .font(HarborFont.panel(11))
                    }
                    .padding(.vertical, 10)
                }
            }
        }

        Button(action: presentAddDirectory) {
            Label("Add Directory", systemImage: "folder.badge.plus")
                .font(HarborFont.title(14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(HarborColor.chassis)
                .background(HarborColor.amber)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(appModel.library.isScanning)

        if let status = appModel.library.indexStatusText {
            Text(status)
                .font(HarborFont.mono(11))
                .foregroundStyle(HarborColor.ivoryDim)
        }

        Button {
            appModel.requestIndexRebuild()
        } label: {
            Label("Rebuild Index", systemImage: "arrow.triangle.2.circlepath")
                .font(HarborFont.title(14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(HarborColor.ivory)
                .background(HarborColor.faceplateLift)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(appModel.library.isScanning || appModel.library.folders.isEmpty)
        .help("Re-read every file and rebuild the catalogue index")
    }

    private func presentAddDirectory() {
        #if os(macOS)
        appModel.library.addFolder()
        #else
        isImporterPresented = true
        #endif
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EngravedLabel(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .faceplate()
    }
}

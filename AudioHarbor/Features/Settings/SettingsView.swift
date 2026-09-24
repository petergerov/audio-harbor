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

                        Text("Effects on the Deck switch you back to Shared until you clear the rack.")
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
        if appModel.playback.externalDACAvailable {
            return "External DAC connected — Exclusive and DoP are available."
        }
        if appModel.playback.outputMode != .shared {
            return "No external DAC connected — playing Shared. \(appModel.playback.outputMode.title) is selected again when you plug the DAC in."
        }
        return "Exclusive and DoP need an external DAC (USB). Built-in speakers, headphones, Bluetooth, and AirPlay stay on Shared."
    }

    @ViewBuilder
    private func outputChoice(_ mode: OutputMode) -> some View {
        let selected = appModel.playback.effectiveOutputMode == mode
        // Exclusive / DoP only when an external DAC is the output (never on iOS).
        let available = !mode.isMacOnly || appModel.playback.externalDACAvailable

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

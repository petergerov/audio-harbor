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
                            kicker: "House",
                            title: "Settings",
                            subtitle: "Output path, DSD strategy, and connected directories."
                        )
                    }

                    panel(title: "Output") {
                        Picker("Mode", selection: $playback.outputMode) {
                            ForEach(OutputMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(HarborColor.amber)

                        Text(playback.outputMode.detail)
                            .font(HarborFont.body(13))
                            .foregroundStyle(HarborColor.ivoryDim)

                        #if os(macOS)
                        Text("Start with Shared. Exclusive hog-locks the DAC — use with a known-good device.")
                            .font(HarborFont.body(12))
                            .foregroundStyle(HarborColor.ivoryDim)
                        #else
                        Text("On iOS, playback uses the shared session. Exclusive/DoP are Mac strengths.")
                            .font(HarborFont.body(12))
                            .foregroundStyle(HarborColor.ivoryDim)
                        #endif

                        Text("Inserts on the Deck rack force Shared · FX and disable Exclusive/DoP while they are loaded.")
                            .font(HarborFont.body(12))
                            .foregroundStyle(HarborColor.ivoryDim)
                    }

                    panel(title: "DSD") {
                        Picker("Strategy", selection: $playback.dsdStrategy) {
                            ForEach(DSDStrategy.allCases) { strategy in
                                Text(strategy.title).tag(strategy)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(HarborColor.amber)

                        Text("DoP keeps 1-bit streams for capable DACs. PCM conversion is the compatibility path.")
                            .font(HarborFont.body(13))
                            .foregroundStyle(HarborColor.ivoryDim)
                    }

                    panel(title: "Directories") {
                        directoriesSection
                    }

                    panel(title: "About") {
                        LabeledContent("App", value: Brand.name)
                            .foregroundStyle(HarborColor.ivory)
                        LabeledContent("Version", value: "0.2.0")
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

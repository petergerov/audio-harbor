import SwiftUI

#if os(iOS)
import UIKit
#endif

struct DeckRackPanel: View {
    @Environment(AppModel.self) private var appModel
    @State private var showBrowser = false
    #if os(iOS)
    @State private var editorSlotID: UUID?
    #endif
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    EngravedLabel(text: "Rack")
                    Text(appModel.effects.hasActiveEffects ? "Shared · FX" : "Exclusive / DoP available")
                        .font(HarborFont.mono(11))
                        .foregroundStyle(appModel.effects.hasActiveEffects ? HarborColor.amber : HarborColor.ivoryDim)
                }
                Spacer(minLength: 8)
                HarborButton(
                    title: "Add",
                    systemImage: "plus",
                    kind: .primary,
                    action: { showBrowser = true }
                )
            }

            if let message = appModel.effects.statusMessage {
                Text(message)
                    .font(HarborFont.mono(11))
                    .foregroundStyle(HarborColor.amber)
            }

            if appModel.effects.chain.isEmpty {
                Text("No inserts.")
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.ivoryDim)
                #if os(macOS)
                Text("Add an AUv3 or AU if you want to process the output.")
                    .font(HarborFont.body(13))
                    .foregroundStyle(HarborColor.ivoryDim)
                #endif
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appModel.effects.chain.enumerated()), id: \.element.id) { index, slot in
                        if index > 0 {
                            Divider().overlay(HarborColor.aluminumDark.opacity(0.45))
                        }
                        EffectSlotRow(
                            slot: slot,
                            onBypass: { appModel.effects.setBypass(slot.id, bypassed: $0) },
                            onEdit: {
                                #if os(macOS)
                                Task { await appModel.effects.openEditor(for: slot.id) }
                                #else
                                editorSlotID = slot.id
                                #endif
                            },
                            onRemove: { appModel.effects.remove(slot.id) }
                        )
                    }
                }
            }
        }
        .faceplate()
        .sheet(isPresented: $showBrowser) {
            pluginBrowser
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 420)
                #endif
        }
        #if os(iOS)
        .sheet(isPresented: Binding(
            get: { editorSlotID != nil },
            set: { if !$0 { editorSlotID = nil } }
        )) {
            if let editorSlotID {
                PluginEditorSheet(slotID: editorSlotID)
            }
        }
        #endif
        .task {
            await appModel.effects.refreshCatalog()
        }
    }

    private var pluginBrowser: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AluminumField {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(HarborColor.ivoryDim)
                        TextField("Search plugins", text: $search)
                            .textFieldStyle(.plain)
                            .foregroundStyle(HarborColor.ivory)
                    }
                }
                .padding()

                if appModel.effects.isLoadingCatalog {
                    ProgressView("Scanning Audio Units…")
                        .tint(HarborColor.amber)
                        .padding()
                } else if filteredPlugins.isEmpty {
                    Text(search.isEmpty
                         ? "No Audio Units found. Install an AUv3 app, then tap Refresh."
                         : "No plugins match that search.")
                        .font(HarborFont.body(13))
                        .foregroundStyle(HarborColor.ivoryDim)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                List(filteredPlugins) { plugin in
                    Button {
                        Task {
                            await appModel.effects.add(plugin)
                            showBrowser = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plugin.name)
                                .font(HarborFont.title(14))
                                .foregroundStyle(HarborColor.ivory)
                            Text("\(plugin.manufacturer) · \(plugin.platformNote) · \(plugin.typeName)")
                                .font(HarborFont.body(12))
                                .foregroundStyle(HarborColor.ivoryDim)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(HarborColor.faceplate)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(HarborColor.chassis)
            .navigationTitle("Add Plugin")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showBrowser = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        Task { await appModel.effects.refreshCatalog() }
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem {
                    Button("Close") { showBrowser = false }
                }
                ToolbarItem {
                    Button("Refresh") {
                        Task { await appModel.effects.refreshCatalog() }
                    }
                }
            }
            #endif
        }
    }

    private var filteredPlugins: [PluginDescriptor] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = appModel.effects.available
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.manufacturer.localizedCaseInsensitiveContains(q)
        }
    }
}

private struct EffectSlotRow: View {
    let slot: EffectSlotState
    let onBypass: (Bool) -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.name)
                    .font(HarborFont.title(14))
                    .foregroundStyle(slot.bypassed ? HarborColor.ivoryDim : HarborColor.ivory)
                Text(slot.bypassed ? "Bypassed" : "In circuit")
                    .font(HarborFont.panel(10))
                    .foregroundStyle(slot.bypassed ? HarborColor.ivoryDim : HarborColor.amber)
            }
            Spacer()
            Toggle("In circuit", isOn: Binding(
                get: { !slot.bypassed },
                set: { onBypass(!$0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(HarborColor.amber)
            .help(slot.bypassed ? "Bypassed — turn on to put in circuit" : "In circuit — turn off to bypass")

            Button("Edit", action: onEdit)
                .buttonStyle(.plain)
                .foregroundStyle(HarborColor.amber)
                .font(HarborFont.panel(11))

            Button("Remove", role: .destructive, action: onRemove)
                .buttonStyle(.plain)
                .foregroundStyle(HarborColor.danger)
                .font(HarborFont.panel(11))
        }
        .padding(.vertical, 4)
    }
}

#if os(iOS)
private struct PluginEditorSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let slotID: UUID
    @State private var title = "Plugin"
    @State private var preferredSize: CGSize = CGSize(width: 480, height: 360)

    var body: some View {
        NavigationStack {
            Group {
                if let slot = appModel.effects.chain.first(where: { $0.id == slotID }) {
                    PluginAUView(slotID: slotID, preferredSize: $preferredSize)
                        .onAppear { title = slot.name }
                } else {
                    Text("Plugin unloaded")
                        .foregroundStyle(HarborColor.ivoryDim)
                }
            }
            .frame(
                minWidth: max(320, preferredSize.width),
                minHeight: max(240, preferredSize.height)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HarborColor.chassis)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear {
            appModel.effects.saveSettings()
        }
    }
}

private struct PluginAUView: UIViewControllerRepresentable {
    @Environment(AppModel.self) private var appModel
    let slotID: UUID
    @Binding var preferredSize: CGSize

    func makeUIViewController(context: Context) -> UIViewController {
        let placeholder = UIViewController()
        Task { @MainActor in
            if let vc = await appModel.effects.makeViewController(for: slotID) {
                context.coordinator.host(vc, in: placeholder)
                let size = vc.preferredContentSize
                if size.width >= 80, size.height >= 80 {
                    preferredSize = size
                }
            }
        }
        return placeholder
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        func host(_ child: UIViewController, in parent: UIViewController) {
            parent.addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            parent.view.addSubview(child.view)
            NSLayoutConstraint.activate([
                child.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: parent.view.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
            ])
            child.didMove(toParent: parent)
        }
    }
}
#endif

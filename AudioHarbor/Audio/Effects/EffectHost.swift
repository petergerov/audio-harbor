import AVFoundation
import CoreAudioKit
import Foundation
import Observation

#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// Hosts user AUv3 (and on Mac, classic AU) inserts on the Shared AVAudioEngine path.
/// Exclusive / DoP stay bit-perfect and cannot run with an active effect chain.
@Observable
@MainActor
final class EffectHost {
    private(set) var available: [PluginDescriptor] = []
    private(set) var chain: [EffectSlotState] = []
    private(set) var statusMessage: String?
    private(set) var isLoadingCatalog = false

    /// Loaded units keyed by slot id — engine attaches these nodes.
    private(set) var loadedUnits: [UUID: AVAudioUnit] = [:]

    /// Called after the chain graph must be rebuilt (add/remove/reorder/load).
    var onChainChanged: (() -> Void)?

    #if os(macOS)
    let pluginEditors = PluginEditorPresenter()
    #endif

    private let defaultsKey = "audioharbor.effectChain"
    private var parameterTokens: [UUID: AUParameterObserverToken] = [:]
    private var persistTask: Task<Void, Never>?

    private var chainFileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioHarbor", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("effect-chain.json")
    }

    /// True when any insert is present and not bypassed — forces Shared output.
    var hasActiveEffects: Bool {
        chain.contains { !$0.bypassed && loadedUnits[$0.id] != nil }
    }

    var hasChain: Bool { !chain.isEmpty }

    private var registrationsObserver: NSObjectProtocol?

    init() {
        loadPersistedChain()
        #if os(macOS)
        pluginEditors.onEditorWillHide = { [weak self] in
            self?.saveSettings()
        }
        #endif
        registrationsObserver = NotificationCenter.default.addObserver(
            forName: AVAudioUnitComponentManager.registrationsChangedNotification,
            object: AVAudioUnitComponentManager.shared(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshCatalog() }
        }
        Task { await refreshCatalog() }
    }

    func refreshCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }

        // Playback rack is stereo-only: hide mono / multi / MIDI-only units.
        let effects = discoverEffectComponents()

        available = effects
            .map { component in
                let desc = component.audioComponentDescription
                return PluginDescriptor(
                    id: "\(desc.componentType)-\(desc.componentSubType)-\(desc.componentManufacturer)",
                    name: component.name,
                    manufacturer: component.manufacturerName,
                    typeName: component.typeName,
                    versionString: component.versionString,
                    audioComponentDescription: desc,
                    isAUv3: Self.isAUv3(desc)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var restored = false
        for slot in chain where loadedUnits[slot.id] == nil {
            do {
                try await loadUnit(for: slot)
                restored = true
            } catch {
                statusMessage = error.localizedDescription
            }
        }
        if restored {
            notifyChainChanged()
        }
    }

    func add(_ descriptor: PluginDescriptor) async {
        guard isStereoCapable(descriptor) else {
            statusMessage = "Only stereo (2-in / 2-out) plugins are supported."
            return
        }
        let slot = EffectSlotState(
            type: descriptor.audioComponentDescription.componentType,
            subType: descriptor.audioComponentDescription.componentSubType,
            manufacturer: descriptor.audioComponentDescription.componentManufacturer,
            name: descriptor.name
        )
        chain.append(slot)
        do {
            try await loadUnit(for: slot)
            statusMessage = "Loaded \(descriptor.name)"
            persist()
            notifyChainChanged()
        } catch {
            chain.removeAll { $0.id == slot.id }
            statusMessage = error.localizedDescription
        }
    }

    func remove(_ id: UUID) {
        remove(id, notify: true)
    }

    /// Drops incompatible units after a failed graph wire without re-entering the engine callback.
    func dropFailedUnits(_ units: [AVAudioUnit], message: String) {
        let ids = units.compactMap { unit in
            loadedUnits.first(where: { $0.value === unit })?.key
        }
        guard !ids.isEmpty else {
            statusMessage = message
            return
        }
        for id in ids {
            remove(id, notify: false)
        }
        statusMessage = message
    }

    private func remove(_ id: UUID, notify: Bool) {
        #if os(macOS)
        pluginEditors.close(slotID: id)
        #endif
        stopObserving(id)
        loadedUnits.removeValue(forKey: id)
        chain.removeAll { $0.id == id }
        persist()
        if notify {
            notifyChainChanged()
        }
    }

    #if os(macOS)
    func openEditor(for id: UUID) async {
        guard let slot = chain.first(where: { $0.id == id }) else { return }
        // AU UIs are usually cached once — re-show the hidden panel instead of requesting again.
        if pluginEditors.showExisting(slotID: id) {
            return
        }
        guard let vc = await makeViewController(for: id) else {
            statusMessage = "No editor UI for \(slot.name)"
            return
        }
        pluginEditors.present(slotID: id, title: slot.name, viewController: vc)
    }
    #endif

    func move(from source: IndexSet, to destination: Int) {
        chain.move(fromOffsets: source, toOffset: destination)
        persist()
        notifyChainChanged()
    }

    func setBypass(_ id: UUID, bypassed: Bool) {
        guard let idx = chain.firstIndex(where: { $0.id == id }) else { return }
        chain[idx].bypassed = bypassed
        if let unit = loadedUnits[id] {
            unit.auAudioUnit.shouldBypassEffect = bypassed
        }
        persist()
        notifyChainChanged()
    }

    /// Snapshot live AU parameters to disk (quit, background, editor close).
    func saveSettings() {
        persist()
    }

    /// Ordered engine nodes for active (loaded) inserts, skipping fully missing loads.
    func engineNodes(includeBypassed: Bool = true) -> [AVAudioUnit] {
        chain.compactMap { slot in
            guard let unit = loadedUnits[slot.id] else { return nil }
            if !includeBypassed, slot.bypassed { return nil }
            // Bypassed units stay in graph with shouldBypassEffect — keeps latency stable.
            unit.auAudioUnit.shouldBypassEffect = slot.bypassed
            return unit
        }
    }

    func displayName(for unit: AVAudioUnit) -> String {
        if let id = loadedUnits.first(where: { $0.value === unit })?.key,
           let slot = chain.first(where: { $0.id == id }) {
            return slot.name
        }
        return unit.name.isEmpty ? "Plugin" : unit.name
    }

    #if os(macOS)
    func makeViewController(for id: UUID) async -> NSViewController? {
        guard let unit = loadedUnits[id] else { return nil }
        return await withCheckedContinuation { continuation in
            unit.auAudioUnit.requestViewController { vc in
                continuation.resume(returning: vc)
            }
        }
    }
    #endif

    #if os(iOS)
    func makeViewController(for id: UUID) async -> UIViewController? {
        guard let unit = loadedUnits[id] else { return nil }
        return await withCheckedContinuation { continuation in
            unit.auAudioUnit.requestViewController { vc in
                continuation.resume(returning: vc)
            }
        }
    }
    #endif

    // MARK: - Private

    private static func isAUv3(_ desc: AudioComponentDescription) -> Bool {
        #if os(iOS)
        true
        #else
        AudioComponentFlags(rawValue: desc.componentFlags).contains(.isV3AudioUnit)
        #endif
    }

    private func discoverEffectComponents() -> [AVAudioUnitComponent] {
        let types: [OSType] = [
            kAudioUnitType_Effect,
            kAudioUnitType_MusicEffect,
            kAudioUnitType_Panner,
            kAudioUnitType_Mixer
        ]
        let manager = AVAudioUnitComponentManager.shared()
        var seen = Set<String>()
        var found: [AVAudioUnitComponent] = []
        for type in types {
            let desc = AudioComponentDescription(
                componentType: type,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            for component in manager.components(matching: desc) {
                #if os(macOS)
                guard component.supportsNumberInputChannels(2, outputChannels: 2) else { continue }
                #endif
                let id = "\(component.audioComponentDescription.componentType)-\(component.audioComponentDescription.componentSubType)-\(component.audioComponentDescription.componentManufacturer)"
                if seen.insert(id).inserted {
                    found.append(component)
                }
            }
        }
        return found
    }

    private func isStereoCapable(_ descriptor: PluginDescriptor) -> Bool {
        #if os(macOS)
        let desc = descriptor.audioComponentDescription
        let matches = AVAudioUnitComponentManager.shared().components(matching: desc)
        guard let component = matches.first else { return false }
        return component.supportsNumberInputChannels(2, outputChannels: 2)
        #else
        // iOS does not expose supportsNumberInputChannels API.
        // Assume AUv3 plugins are filtered elsewhere and are stereo-capable.
        return true
        #endif
    }

    private func loadUnit(for slot: EffectSlotState) async throws {
        let desc = slot.audioComponentDescription
        let unit: AVAudioUnit = try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: desc, options: []) { avAudioUnit, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let avAudioUnit {
                    continuation.resume(returning: avAudioUnit)
                } else {
                    continuation.resume(throwing: EffectHostError.instantiateFailed(slot.name))
                }
            }
        }
        unit.auAudioUnit.shouldBypassEffect = slot.bypassed
        if let data = slot.parameterState {
            Self.applyAUState(data, to: unit.auAudioUnit)
        }
        loadedUnits[slot.id] = unit
        observeParameters(slot.id, unit: unit)
    }

    private func notifyChainChanged() {
        snapshotParameterStates()
        onChainChanged?()
        applyStoredParameterStates()
    }

    private func persist() {
        snapshotParameterStates()
        guard let data = try? JSONEncoder().encode(chain) else { return }
        try? data.write(to: chainFileURL, options: [.atomic])
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func loadPersistedChain() {
        let data = (try? Data(contentsOf: chainFileURL))
            ?? UserDefaults.standard.data(forKey: defaultsKey)
        guard let data,
              let decoded = try? JSONDecoder().decode([EffectSlotState].self, from: data)
        else { return }
        chain = decoded
    }

    private func snapshotParameterStates() {
        for i in chain.indices {
            guard let unit = loadedUnits[chain[i].id] else { continue }
            if let data = Self.encodeAUState(unit.auAudioUnit) {
                chain[i].parameterState = data
            }
        }
    }

    private func applyStoredParameterStates() {
        for slot in chain {
            guard let data = slot.parameterState, let unit = loadedUnits[slot.id] else { continue }
            Self.applyAUState(data, to: unit.auAudioUnit)
        }
    }

    private func observeParameters(_ id: UUID, unit: AVAudioUnit) {
        stopObserving(id)
        guard let tree = unit.auAudioUnit.parameterTree else { return }
        let token = tree.token(byAddingParameterObserver: { [weak self] _, _ in
            Task { @MainActor in
                self?.schedulePersist()
            }
        })
        parameterTokens[id] = token
    }

    private func stopObserving(_ id: UUID) {
        guard let token = parameterTokens.removeValue(forKey: id) else { return }
        if let unit = loadedUnits[id], let tree = unit.auAudioUnit.parameterTree {
            tree.removeParameterObserver(token)
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private static func encodeAUState(_ au: AUAudioUnit) -> Data? {
        let dict = au.fullStateForDocument ?? au.fullState
        guard let dict else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    private static func applyAUState(_ data: Data, to au: AUAudioUnit) {
        let dict: [String: Any]?
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            dict = plist
        } else {
            dict = nil
        }
        guard let dict else { return }
        var nsError: NSError?
        _ = AHPerformWithExceptionHandling({
            au.fullStateForDocument = dict
            au.fullState = dict
        }, &nsError)
        _ = nsError
    }
}

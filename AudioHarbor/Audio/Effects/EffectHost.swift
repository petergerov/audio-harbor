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

    /// True when any insert is present and not bypassed — forces Shared output.
    var hasActiveEffects: Bool {
        chain.contains { !$0.bypassed && loadedUnits[$0.id] != nil }
    }

    var hasChain: Bool { !chain.isEmpty }

    init() {
        loadPersistedChain()
        Task { await refreshCatalog() }
    }

    func refreshCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }

        // Playback rack is stereo-only: hide mono / multi / MIDI-only units.
        let effects = AVAudioUnitComponentManager.shared().components(passingTest: { component, _ in
            let type = component.audioComponentDescription.componentType
            let isEffectType = type == kAudioUnitType_Effect
                || type == kAudioUnitType_MusicEffect
                || type == kAudioUnitType_Panner
                || type == kAudioUnitType_Mixer
            guard isEffectType else { return false }
            #if os(macOS)
            return component.supportsNumberInputChannels(2, outputChannels: 2)
            #else
            // iOS does not support supportsNumberInputChannels API.
            // Assume AUv3 plugins are properly filtered elsewhere.
            return true
            #endif
        })

        available = effects
            .map { component in
                let desc = component.audioComponentDescription
                // AUv3 components set IsV3AudioUnit; classic AU remain Mac-only catalog entries.
                let isV3 = (desc.componentFlags & 1) != 0 // kAudioComponentFlag_IsV3AudioUnit
                return PluginDescriptor(
                    id: "\(desc.componentType)-\(desc.componentSubType)-\(desc.componentManufacturer)",
                    name: component.name,
                    manufacturer: component.manufacturerName,
                    typeName: component.typeName,
                    versionString: component.versionString,
                    audioComponentDescription: desc,
                    isAUv3: isV3
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Restore units for persisted chain.
        for slot in chain where loadedUnits[slot.id] == nil {
            do {
                try await loadUnit(for: slot)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
        onChainChanged?()
    }

    func add(_ descriptor: PluginDescriptor) async {
        #if !os(macOS)
        if !descriptor.isAUv3 {
            // On iOS only AUv3 should appear; still allow instantiate attempts.
        }
        #endif
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
            onChainChanged?()
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
        loadedUnits.removeValue(forKey: id)
        chain.removeAll { $0.id == id }
        persist()
        if notify {
            onChainChanged?()
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
        onChainChanged?()
    }

    func setBypass(_ id: UUID, bypassed: Bool) {
        guard let idx = chain.firstIndex(where: { $0.id == id }) else { return }
        chain[idx].bypassed = bypassed
        if let unit = loadedUnits[id] {
            unit.auAudioUnit.shouldBypassEffect = bypassed
        }
        persist()
        onChainChanged?()
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
        loadedUnits[slot.id] = unit
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(chain) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func loadPersistedChain() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([EffectSlotState].self, from: data)
        else { return }
        chain = decoded
    }
}

import AVFoundation
import Foundation

/// Identifies an Audio Unit / AUv3 that can be inserted on the Shared output path.
struct PluginDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let manufacturer: String
    let typeName: String
    let versionString: String
    let audioComponentDescription: AudioComponentDescription
    /// true when the component is an AUv3 (app-extension style). Classic AU are macOS-only.
    let isAUv3: Bool

    var platformNote: String {
        if isAUv3 { return "AUv3" }
        #if os(macOS)
        return "AU"
        #else
        return "AU (Mac)"
        #endif
    }

    static func == (lhs: PluginDescriptor, rhs: PluginDescriptor) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct EffectSlotState: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var type: OSType
    var subType: OSType
    var manufacturer: OSType
    var name: String
    var bypassed: Bool

    init(
        id: UUID = UUID(),
        type: OSType,
        subType: OSType,
        manufacturer: OSType,
        name: String,
        bypassed: Bool = false
    ) {
        self.id = id
        self.type = type
        self.subType = subType
        self.manufacturer = manufacturer
        self.name = name
        self.bypassed = bypassed
    }

    var audioComponentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: type,
            componentSubType: subType,
            componentManufacturer: manufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
}

enum EffectHostError: LocalizedError {
    case instantiateFailed(String)
    case notAvailableOnPlatform
    case incompatibleGraph(String)

    var errorDescription: String? {
        switch self {
        case .instantiateFailed(let name):
            "Could not load plugin “\(name)”."
        case .notAvailableOnPlatform:
            "This plugin type is only available on Mac."
        case .incompatibleGraph(let name):
            "“\(name)” rejected the Shared audio format (host-incompatible or unsupported sample rate)."
        }
    }
}

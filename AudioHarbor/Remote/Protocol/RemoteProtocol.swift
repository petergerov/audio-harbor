import Foundation

/// Wire format constants for Audio Harbor LAN remote.
/// Keep this file Foundation-only — it will be shared with the iOS destination.
enum RemoteProtocol {
    /// 3: Mac Settings from the remote (output, sharing, directories, about).
    static let version = 3
    static let minimumSupported = 1
    /// First version whose Mac answers `trackOptions` and `editTrack`. Gated on the version, not a
    /// capability: remotes on version 1 reject a capability list with a case they do not know.
    static let trackEditsVersion = 2
    /// First version whose Mac filters `browse` by `BrowseRequest.query`. A version-1 Mac ignores it.
    static let browseSearchVersion = 2
    /// First version whose Mac answers `getSettings` / `setSettings`.
    static let settingsVersion = 3
    /// Bonjour service type. Must also appear in Info.plist `NSBonjourServices`.
    static let serviceType = "_audioharbor._tcp"
    static let maxFrameBytes = 4 << 20 // 4 MiB
    /// TXT / hello capability strings.
    static let capabilityTransport = "transport"
    static let capabilityQueueJump = "queueJump"
    static let capabilityBrowse = "browse"
    static let capabilitySearch = "search"
    static let capabilityArtwork = "artwork"
}

enum RemoteCapability: String, Codable, Sendable, CaseIterable {
    case transport
    case queueJump
    case browse
    case search
    case artwork
}

enum RemoteTopic: String, Codable, Sendable {
    case nowPlaying
    case queue
    case settings
}

enum RemoteErrorCode: String, Codable, Sendable {
    case unauthorized
    case badRequest
    case notFound
    case unsupported
    case busy
    case internalError
}

/// Authentication material carried in `hello`.
enum RemoteAuth: Codable, Sendable, Equatable {
    case pairingCode(String)
    case token(Data)

    enum CodingKeys: String, CodingKey {
        case pairingCode, token
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let code = try container.decodeIfPresent(String.self, forKey: .pairingCode) {
            self = .pairingCode(code)
            return
        }
        if let token = try container.decodeIfPresent(Data.self, forKey: .token) {
            self = .token(token)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "RemoteAuth needs pairingCode or token")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pairingCode(let code):
            try container.encode(code, forKey: .pairingCode)
        case .token(let token):
            try container.encode(token, forKey: .token)
        }
    }
}

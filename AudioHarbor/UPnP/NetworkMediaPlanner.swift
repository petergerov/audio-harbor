#if os(macOS)
import Foundation

/// What to send the renderer for one track — file bytes or a generated WAV.
enum NetworkMediaPlan: Sendable {
    /// File untouched; `dsd` means a DSF / DFF (SACD as its cached DFF).
    case passthrough(url: URL, mime: String, dsd: Bool)
    case wav(WAVPCMBodySource)
}

enum NetworkMediaPlanner {
    /// MIME types we will send untouched when the sink lists them.
    private static let passthroughFormats: [AudioFormat: String] = [
        .flac: "audio/flac",
        .wav: "audio/wav",
        .aiff: "audio/aiff",
        .alac: "audio/mp4",
        .aac: "audio/mp4",
        .mp3: "audio/mpeg",
    ]

    /// DSD types a player may list, best first: the container by name, then the generic DSD types.
    private static let dsdTypes: [NetworkDsdContainer: [String]] = [
        .dsf: ["audio/x-dsf", "audio/dsf", "audio/x-dsd", "audio/dsd"],
        .dff: ["audio/x-dff", "audio/dff", "audio/x-dsd", "audio/dsd"],
    ]

    private static var allDsdTypes: Set<String> {
        Set(dsdTypes.values.flatMap { $0 })
    }

    /// Decides passthrough vs WAV from the track, stream quality, DSD mode, and the sink list.
    static func plan(
        track: Track,
        sinkProtocolInfo: String,
        quality: NetworkStreamQuality = .full,
        dsdMode: NetworkDsdMode = .pcm
    ) throws -> NetworkMediaPlan {
        if isDsdTrack(track) {
            if quality == .wifi {
                return .wav(try WAVPCMBodySource.wifiLive(track: track))
            }
            if dsdMode == .dop {
                return .wav(try WAVPCMBodySource.dop(track: track))
            }
            if dsdMode == .auto,
               canPassthroughDSD(track),
               let mime = nativeDsdType(container(for: track), sink: sinkProtocolInfo) {
                let url = try playbackFileURL(for: track)
                return .passthrough(url: url, mime: mime, dsd: true)
            }
            return .wav(try WAVPCMBodySource.dsd(track: track))
        }
        guard let mime = passthroughFormats[track.format] else {
            return .wav(try WAVPCMBodySource.decodedPCM(url: track.url))
        }
        if sinkAccepts(mime, sink: sinkProtocolInfo) {
            return .passthrough(url: track.url, mime: mime, dsd: false)
        }
        return .wav(try WAVPCMBodySource.decodedPCM(url: track.url))
    }

    /// DSD and virtual SACD / DFF chapter tracks (chapters cannot go out as the whole file).
    static func needsTranscode(_ track: Track) -> Bool {
        isDsdTrack(track)
    }

    static func isDsdTrack(_ track: Track) -> Bool {
        if track.format.isDSD { return true }
        if VirtualTrackPath.isVirtual(track.cataloguePath) { return true }
        return false
    }

    /// Path label for the Deck / remote.
    static func pathLabel(for plan: NetworkMediaPlan, quality: NetworkStreamQuality, track: Track) -> String {
        switch plan {
        case .passthrough(_, _, let dsd):
            return dsd ? "DSD · Network" : "Network"
        case .wav(let source):
            if source.label.hasPrefix("dop·") { return "DoP · Network" }
            if quality == .wifi { return "Wi‑Fi PCM · Network" }
            if isDsdTrack(track) { return "DSD→PCM · Network" }
            return "PCM · Network"
        }
    }

    /// The DSD types in a sink list, spelled as the player lists them.
    static func sinkDsdTypes(_ sink: String) -> [String] {
        var found: [String] = []
        for entry in sink.split(separator: ",") {
            let parts = entry.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let listed = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let key = listed.lowercased()
            if allDsdTypes.contains(key), !found.contains(where: { $0.caseInsensitiveCompare(listed) == .orderedSame }) {
                found.append(listed)
            }
        }
        return found
    }

    /// Containers that go to the player untouched in Auto mode (SACD goes as DFF).
    static func nativeDsdContainers(sink: String) -> [NetworkDsdContainer] {
        ([NetworkDsdContainer.dsf, .dff]).filter { nativeDsdType($0, sink: sink) != nil }
    }

    /// `http-get:*:audio/flac:…` entries — match on the MIME slot.
    static func sinkAccepts(_ mime: String, sink: String) -> Bool {
        let wanted = mime.lowercased()
        let aliases: [String: [String]] = [
            "audio/flac": ["audio/flac", "audio/x-flac"],
            "audio/wav": ["audio/wav", "audio/x-wav", "audio/wave"],
            "audio/aiff": ["audio/aiff", "audio/x-aiff"],
            "audio/mp4": ["audio/mp4", "audio/x-m4a", "audio/aac"],
            "audio/mpeg": ["audio/mpeg", "audio/mp3"],
        ]
        let names = aliases[wanted] ?? [wanted]
        let entries = sink.split(separator: ",")
        for entry in entries {
            let parts = entry.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let listed = parts[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if names.contains(listed) { return true }
        }
        // Empty sink (GetProtocolInfo failed): assume common PCM containers work.
        if sink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ["audio/flac", "audio/wav", "audio/aiff", "audio/mp4", "audio/mpeg"].contains(wanted)
        }
        return false
    }

    static func mimeTypes(in sink: String) -> Set<String> {
        var result = Set<String>()
        for entry in sink.split(separator: ",") {
            let parts = entry.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            result.insert(parts[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        return result
    }

    // MARK: - DSD helpers

    private static func container(for track: Track) -> NetworkDsdContainer {
        track.format == .dsf ? .dsf : .dff
    }

    private static func nativeDsdType(_ container: NetworkDsdContainer, sink: String) -> String? {
        let listed = sinkDsdTypes(sink)
        for wanted in dsdTypes[container] ?? [] {
            if let hit = listed.first(where: { $0.lowercased() == wanted }) {
                return hit
            }
        }
        return nil
    }

    /// Whole-file DSD only — a DFF chapter cannot be sent as the container file.
    private static func canPassthroughDSD(_ track: Track) -> Bool {
        VirtualTrackPath.dffTrack(from: track.cataloguePath) == nil
    }

    /// File bytes for native DSD: SACD / DST → cached DFF; else the track URL.
    private static func playbackFileURL(for track: Track) throws -> URL {
        if track.format == .sacd || VirtualTrackPath.sacdTrack(from: track.cataloguePath) != nil {
            return try SACDISO.playbackURL(for: track)
        }
        let fileURL = track.url
        if fileURL.pathExtension.lowercased() == "dff", DFFDST.isCompressed(url: fileURL) {
            return try DFFDST.playbackURL(for: track)
        }
        return fileURL
    }
}
#endif

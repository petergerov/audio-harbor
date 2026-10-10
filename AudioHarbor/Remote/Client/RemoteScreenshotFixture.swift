#if DEBUG && os(iOS)
import Network
import UIKit

/// Made-up library for App Store screenshots of the remote. Debug builds only.
///
/// Launch with `-remoteScreenshot <scene>` (`now`, `browse`, `queue`, `nearby`, `pairing`);
/// the remote then shows this data instead of talking to a Mac.
/// Rendered by `marketing/app-store/build-ios.sh`.
struct RemoteScreenshotFixture {
    enum Scene: String {
        case now, browse, queue, nearby, pairing
    }

    static let defaultsKey = "remoteScreenshot"
    static let serverName = "Studio Mac"

    let scene: Scene

    static func fromLaunchArguments() -> RemoteScreenshotFixture? {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let scene = Scene(rawValue: raw) else { return nil }
        return RemoteScreenshotFixture(scene: scene)
    }

    // MARK: - Library

    private struct Album {
        var id: UUID
        var title: String
        var artist: String
        var year: Int
        var format: String
        var sampleRateHz: Int
        var bitDepth: Int
        var tracks: [(String, TimeInterval)]
        var colors: (UIColor, UIColor)
    }

    private static let albums: [Album] = [
        Album(
            id: UUID(uuidString: "6E0A4C1E-0000-4000-8000-000000000001")!,
            title: "Quiet Hours", artist: "North Room", year: 2024, format: "FLAC",
            sampleRateHz: 96_000, bitDepth: 24,
            tracks: [("Amber Signal", 243), ("Glass Corridor", 318), ("Low Tide Radio", 274),
                     ("Slow Lantern", 291), ("Copper Rain", 236), ("The Last Ferry", 352),
                     ("Window Light", 205), ("Harbor Wall", 389)],
            colors: (UIColor(red: 0.85, green: 0.52, blue: 0.18, alpha: 1), UIColor(red: 0.25, green: 0.10, blue: 0.05, alpha: 1))
        ),
        Album(
            id: UUID(uuidString: "6E0A4C1E-0000-4000-8000-000000000002")!,
            title: "DSD Sampler", artist: "Field Tape", year: 2023, format: "DSF",
            sampleRateHz: 2_822_400, bitDepth: 1,
            tracks: [("Night Wire", 401), ("Reed and Brass", 288), ("Open Room", 333)],
            colors: (UIColor(red: 0.20, green: 0.42, blue: 0.48, alpha: 1), UIColor(red: 0.04, green: 0.08, blue: 0.10, alpha: 1))
        ),
        Album(
            id: UUID(uuidString: "6E0A4C1E-0000-4000-8000-000000000003")!,
            title: "Analog Sketches", artist: "Field Tape", year: 2022, format: "ALAC",
            sampleRateHz: 48_000, bitDepth: 24,
            tracks: [("Harbor Light", 276), ("Tape Hiss Lullaby", 248)],
            colors: (UIColor(red: 0.62, green: 0.58, blue: 0.48, alpha: 1), UIColor(red: 0.18, green: 0.16, blue: 0.12, alpha: 1))
        ),
        Album(
            id: UUID(uuidString: "6E0A4C1E-0000-4000-8000-000000000004")!,
            title: "Midnight Pressing", artist: "The Velvet Gauge", year: 2021, format: "FLAC",
            sampleRateHz: 192_000, bitDepth: 24,
            tracks: [("Needle Drop", 262), ("Groove Wax", 301)],
            colors: (UIColor(red: 0.55, green: 0.12, blue: 0.16, alpha: 1), UIColor(red: 0.10, green: 0.03, blue: 0.05, alpha: 1))
        ),
        Album(
            id: UUID(uuidString: "6E0A4C1E-0000-4000-8000-000000000005")!,
            title: "Blue Room Sessions", artist: "Ada Lindqvist Trio", year: 2019, format: "WAV",
            sampleRateHz: 96_000, bitDepth: 24,
            tracks: [("Brushes", 318), ("Upright", 402)],
            colors: (UIColor(red: 0.16, green: 0.24, blue: 0.55, alpha: 1), UIColor(red: 0.03, green: 0.05, blue: 0.14, alpha: 1))
        ),
        Album(
            id: UUID(uuidString: "6E0A4C1E-0000-4000-8000-000000000006")!,
            title: "Salt and Cedar", artist: "Marrow Coast", year: 2020, format: "FLAC",
            sampleRateHz: 44_100, bitDepth: 16,
            tracks: [("Driftwood", 233), ("Cedar Smoke", 287)],
            colors: (UIColor(red: 0.36, green: 0.46, blue: 0.28, alpha: 1), UIColor(red: 0.07, green: 0.10, blue: 0.05, alpha: 1))
        ),
        Album(
            id: UUID(uuidString: "6E0A4C1E-0000-4000-8000-000000000007")!,
            title: "Cathedral Air", artist: "Halden Consort", year: 2018, format: "DSF",
            sampleRateHz: 5_644_800, bitDepth: 1,
            tracks: [("Nave", 512), ("Clerestory", 447)],
            colors: (UIColor(red: 0.78, green: 0.70, blue: 0.52, alpha: 1), UIColor(red: 0.20, green: 0.15, blue: 0.08, alpha: 1))
        ),
        Album(
            id: UUID(uuidString: "6E0A4C1E-0000-4000-8000-000000000008")!,
            title: "Signal Fires", artist: "Oona Reyes", year: 2025, format: "FLAC",
            sampleRateHz: 88_200, bitDepth: 24,
            tracks: [("First Light", 244), ("Ember", 296)],
            colors: (UIColor(red: 0.90, green: 0.36, blue: 0.20, alpha: 1), UIColor(red: 0.22, green: 0.05, blue: 0.08, alpha: 1))
        ),
        Album(
            id: UUID(uuidString: "6E0A4C1E-0000-4000-8000-000000000009")!,
            title: "Long Exposure", artist: "Kite Theory", year: 2017, format: "ALAC",
            sampleRateHz: 44_100, bitDepth: 16,
            tracks: [("Shutter", 221), ("Grain", 265)],
            colors: (UIColor(red: 0.42, green: 0.32, blue: 0.58, alpha: 1), UIColor(red: 0.08, green: 0.05, blue: 0.14, alpha: 1))
        ),
    ]

    private static func artworkHash(_ album: Album) -> String {
        "fixture-\(album.id.uuidString)"
    }

    private static func tracks(of album: Album) -> [TrackDTO] {
        album.tracks.enumerated().map { index, entry in
            var track = Track(
                title: entry.0,
                artist: album.artist,
                album: album.title,
                trackNumber: index + 1,
                year: album.year,
                duration: entry.1,
                format: AudioFormat(rawValue: album.format) ?? .flac,
                sampleRateHz: album.sampleRateHz,
                bitDepth: album.bitDepth,
                url: URL(fileURLWithPath: "/fixture/\(album.title)/\(index + 1)")
            )
            track.artworkHash = artworkHash(album)
            var dto = TrackDTO(track: track)
            dto.cataloguePath = "fixture/\(album.title)/\(index + 1)"
            dto.channelCount = 2
            return dto
        }
    }

    private static var playingAlbum: Album { albums[0] }
    private static let playingIndex = 1

    // MARK: - What the remote shows

    var nowPlaying: NowPlayingSnapshot {
        let queue = Self.tracks(of: Self.playingAlbum)
        let track = queue[Self.playingIndex]
        return NowPlayingSnapshot(
            generation: 1,
            track: track,
            state: "playing",
            position: 127,
            duration: track.duration,
            positionTimestamp: Date(),
            rate: 0,
            queueIndex: Self.playingIndex,
            queueCount: queue.count,
            queueSourceKind: "Album",
            queueSourceName: Self.playingAlbum.title,
            repeatMode: "off",
            isShuffled: false,
            activeFormatLabel: "FLAC 24/96",
            pathLabel: "Exclusive · Bit-perfect",
            outputVolume: 0.62,
            outputName: "USB DAC",
            playbackLocked: false
        )
    }

    var queue: QueueSnapshot {
        QueueSnapshot(
            generation: 1,
            index: Self.playingIndex,
            tracks: Self.tracks(of: Self.playingAlbum),
            sourceKind: "Album",
            sourceName: Self.playingAlbum.title
        )
    }

    var searchQuery: String? {
        scene == .now ? "North Room" : nil
    }

    var searchResults: [TrackDTO] {
        guard let query = searchQuery else { return [] }
        return Self.albums.flatMap(Self.tracks(of:)).filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    func browseItems(scope: BrowseScope, parentID: String?) -> [BrowseItem] {
        switch scope {
        case .albums:
            return Self.albums.map {
                .album(id: $0.id, title: $0.title, artist: $0.artist, trackCount: $0.tracks.count, artworkHash: Self.artworkHash($0))
            }
        case .artists:
            let names = Array(Set(Self.albums.map(\.artist))).sorted()
            return names.map { name in
                .artist(name: name, trackCount: Self.albums.filter { $0.artist == name }.reduce(0) { $0 + $1.tracks.count })
            }
        case .albumTracks:
            guard let album = Self.albums.first(where: { $0.id.uuidString == parentID }) else { return [] }
            return Self.tracks(of: album).map(BrowseItem.track)
        default:
            return []
        }
    }

    var pane: String? {
        switch scene {
        case .browse: "catalogue"
        case .queue: "deck"
        case .now: "deck"
        default: nil
        }
    }

    /// Open the Deck queue sheet for the `queue` screenshot scene.
    var showQueue: Bool { scene == .queue }

    var pairingCode: String { scene == .pairing ? "482193" : "" }

    var nearbyServers: [RemoteServerEndpoint] {
        [
            RemoteServerEndpoint(
                name: Self.serverName,
                serverID: nil,
                endpoint: .service(name: Self.serverName, type: RemoteProtocol.serviceType, domain: "local.", interface: nil),
                txt: [:]
            ),
            RemoteServerEndpoint(
                name: "Living Room Mac mini",
                serverID: nil,
                endpoint: .service(name: "Living Room Mac mini", type: RemoteProtocol.serviceType, domain: "local.", interface: nil),
                txt: [:]
            ),
        ]
    }

    /// Generated covers: a warm gradient with record grooves — no real album art.
    func artwork() -> [String: Data] {
        var result: [String: Data] = [:]
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        for album in Self.albums {
            let image = renderer.image { context in
                let cg = context.cgContext
                let colors = [album.colors.0.cgColor, album.colors.1.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                }
                let center = CGPoint(x: size.width * 0.62, y: size.height * 0.58)
                for ring in stride(from: 40.0, through: 330.0, by: 14.0) {
                    cg.setStrokeColor(UIColor.white.withAlphaComponent(ring.truncatingRemainder(dividingBy: 56) == 40 ? 0.14 : 0.06).cgColor)
                    cg.setLineWidth(2)
                    cg.strokeEllipse(in: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2))
                }
                cg.setFillColor(album.colors.0.withAlphaComponent(0.9).cgColor)
                cg.fillEllipse(in: CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68))
            }
            if let data = image.pngData() {
                result[Self.artworkHash(album)] = data
            }
        }
        return result
    }
}
#endif

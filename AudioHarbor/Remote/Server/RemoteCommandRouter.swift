#if os(macOS)
import AppKit
#endif
import Foundation

/// Routes authenticated client messages onto AppModel services.
@MainActor
final class RemoteCommandRouter {
    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func handle(_ message: ClientMessage, requestID: UInt32?) async -> RouterReply {
        switch message {
        case .hello, .subscribe:
            // Handled by the session before routing.
            return .none

        case .transport(let command):
            apply(command)
            return .none

        case .playSelection(let selection):
            guard let resolved = LibraryQueryService.resolve(
                selection,
                library: appModel.library,
                playlists: appModel.playlists
            ) else {
                return .message(.error(code: .notFound, message: "Selection not found"), requestID: requestID)
            }
            appModel.play(resolved.queue, startingAt: resolved.track, from: resolved.source, showDeck: false)
            return .none

        case .browse(let request):
            let result = LibraryQueryService.browse(
                request,
                library: appModel.library,
                playlists: appModel.playlists
            )
            return .message(
                .browseResult(items: result.items, hasMore: result.hasMore),
                requestID: requestID
            )

        case .search(let query, let limit):
            let tracks = await LibraryQueryService.search(
                query: query,
                limit: limit,
                library: appModel.library
            )
            return .message(.searchResult(tracks: tracks), requestID: requestID)

        case .artwork(let hash, let maxPixel):
            guard let data = ArtworkCache.shared.load(hash), !data.isEmpty else {
                return .message(.error(code: .notFound, message: "Artwork missing"), requestID: requestID)
            }
            let scaled = Self.downscaleArtwork(data, maxPixel: maxPixel) ?? data
            return .artwork(
                header: .artworkHeader(hash: hash, byteCount: scaled.count),
                bytes: scaled,
                requestID: requestID
            )

        case .ping:
            return .message(.pong, requestID: requestID)
        }
    }

    private func apply(_ command: TransportCommand) {
        let playback = appModel.playback
        switch command {
        case .playPause:
            playback.togglePlayPause()
        case .next:
            playback.playNext()
        case .previous:
            playback.playPrevious()
        case .seek(let seconds):
            playback.seek(to: max(0, seconds))
        case .playQueueIndex(let index):
            playback.playQueueItem(at: index)
        case .setRepeat(let mode):
            if let repeatMode = RepeatMode(rawValue: mode) {
                playback.repeatMode = repeatMode
            }
        case .setShuffle(let on):
            if playback.isShuffled != on {
                playback.toggleShuffle()
            }
        case .setVolume(let level):
            playback.setOutputVolume(level)
        }
    }

    #if os(macOS)
    private static func downscaleArtwork(_ data: Data, maxPixel: Int) -> Data? {
        guard maxPixel > 0, maxPixel < 4096 else { return data }
        guard let image = NSImage(data: data) else { return data }
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > CGFloat(maxPixel) else { return data }
        let scale = CGFloat(maxPixel) / longest
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width.rounded(.down)),
            pixelsHigh: Int(target.height.rounded(.down)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return data }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
    #else
    private static func downscaleArtwork(_ data: Data, maxPixel: Int) -> Data? {
        _ = maxPixel
        return data
    }
    #endif
}

enum RouterReply {
    case none
    case message(ServerMessage, requestID: UInt32?)
    case artwork(header: ServerMessage, bytes: Data, requestID: UInt32?)
}

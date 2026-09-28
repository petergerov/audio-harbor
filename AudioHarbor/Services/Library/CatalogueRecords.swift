import Foundation

struct IndexedTrackRecord: Sendable {
    var path: String
    var title: String
    var artist: String
    var album: String
    var trackNumber: Int?
    var year: Int?
    var duration: TimeInterval
    var format: AudioFormat
    var sampleRateHz: Int?
    var bitDepth: Int?
    var channelCount: Int?
    var fileSize: Int64
    var mtime: TimeInterval
    var artworkHash: String?
    var filename: String
    var labels: [String]

    func asTrack(labelsByPath: [String: [String]]) -> Track {
        let filePath = VirtualTrackPath.filePath(from: path)
        return Track(
            title: title,
            artist: artist,
            album: album,
            trackNumber: trackNumber,
            year: year,
            duration: duration,
            format: format,
            sampleRateHz: sampleRateHz,
            bitDepth: bitDepth,
            channelCount: channelCount,
            url: URL(fileURLWithPath: filePath),
            artworkHash: artworkHash,
            labels: labelsByPath[path] ?? labels,
            cataloguePath: path
        )
    }
}

struct FileFingerprint: Sendable {
    var url: URL
    var path: String
    var fileSize: Int64
    var mtime: TimeInterval
}

struct StoredFingerprint: Sendable {
    var path: String
    var fileSize: Int64
    var mtime: TimeInterval
}

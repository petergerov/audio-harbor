import CryptoKit
import Foundation

/// Virtual catalogue identity so one ISO/DFF can own many tracks.
enum VirtualTrackPath {
    static let sacdMarker = "#sacd/"
    static let dffMarker = "#dff/"

    static func sacd(_ filePath: String, track: Int) -> String {
        "\(filePath)\(sacdMarker)\(track)"
    }

    static func dff(_ filePath: String, track: Int) -> String {
        "\(filePath)\(dffMarker)\(track)"
    }

    static func filePath(from identity: String) -> String {
        if let range = identity.range(of: sacdMarker) ?? identity.range(of: dffMarker) {
            return String(identity[..<range.lowerBound])
        }
        return identity
    }

    static func sacdTrack(from identity: String) -> Int? {
        guard let range = identity.range(of: sacdMarker) else { return nil }
        return Int(identity[range.upperBound...])
    }

    static func dffTrack(from identity: String) -> Int? {
        guard let range = identity.range(of: dffMarker) else { return nil }
        return Int(identity[range.upperBound...])
    }

    static func isVirtual(_ identity: String) -> Bool {
        identity.contains(sacdMarker) || identity.contains(dffMarker)
    }
}

struct SACDDiscTrack: Sendable {
    var number: Int
    var title: String
    var artist: String
    var album: String
    var year: Int?
    var duration: TimeInterval
    var startLSN: UInt32
    var lengthLSN: UInt32
    var sampleRateHz: Int
    var channelCount: Int
    var isDST: Bool
}

enum SACDError: LocalizedError {
    case notScarletBook
    case truncated
    case dstCompressed
    case noStereoArea
    case extractFailed

    var errorDescription: String? {
        switch self {
        case .notScarletBook:
            "This ISO is not a Scarlet Book SACD image."
        case .truncated:
            "The SACD image is truncated or unreadable."
        case .dstCompressed:
            "This SACD track is DST-compressed. Audio Harbor lists the titles; uncompressed DSD areas play now."
        case .noStereoArea:
            "No stereo SACD area on this disc."
        case .extractFailed:
            "Could not read DSD from this SACD track."
        }
    }
}

enum DSDPlayback {
    static func stream(for track: Track, strategy: DSDStrategy) throws -> DSDStreamSource {
        if track.format == .sacd || VirtualTrackPath.sacdTrack(from: track.cataloguePath) != nil {
            let url = try SACDISO.playbackURL(for: track)
            return try DSDStreamSource(url: url, strategy: strategy)
        }
        if let chapter = VirtualTrackPath.dffTrack(from: track.cataloguePath) {
            let header = try DSDDecoder.probe(url: track.url)
            if let found = DFFChapters.list(url: track.url, header: header).first(where: { $0.number == chapter }) {
                return try DSDStreamSource(
                    url: track.url,
                    strategy: strategy,
                    startSample: found.startSample,
                    sampleCount: found.sampleCount
                )
            }
        }
        return try DSDStreamSource(url: track.url, strategy: strategy)
    }
}

enum SACDISO {
    static let sectorSize = 2048
    static let masterTOCSector: UInt32 = 510
    static let framesPerSecond = 75
    private static let masterSignature = Data("SACDMTOC".utf8)
    private static let masterTextSignature = Data("SACDText".utf8)
    private static let stereoSignature = Data("TWOCHTOC".utf8)
    private static let multiSignature = Data("MULCHTOC".utf8)
    private static let trackList1 = Data("SACDTRL1".utf8)
    private static let trackList2 = Data("SACDTRL2".utf8)
    private static let trackTextSig = Data("SACDTTxt".utf8)

    static func probe(url: URL) -> Bool {
        (try? layout(of: url)) != nil
    }

    static func listTracks(url: URL) throws -> [SACDDiscTrack] {
        let layout = try layout(of: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let masterSector = try readSector(handle, lsn: masterTOCSector, layout: layout)
        guard masterSector.count >= 88, masterSector.prefix(8) == masterSignature else {
            throw SACDError.notScarletBook
        }

        let year = Int(be16(masterSector, 120))
        let stereoStart = be32(masterSector, 64)
        let stereoSize = be16(masterSector, 84)
        guard stereoStart > 0, stereoSize >= 2 else { throw SACDError.noStereoArea }

        let area = try readSectors(handle, start: stereoStart, count: Int(stereoSize), layout: layout)
        let toc = try parseAreaTOC(area)
        let text = (try? readMasterText(handle, layout: layout)) ?? MasterNames()
        let album = nonempty(text.albumTitle, text.discTitle, url.deletingPathExtension().lastPathComponent)
        let artist = nonempty(text.albumArtist, text.discArtist, "Unknown Artist")
        let safeYear = (year >= 1900 && year <= 2100) ? year : nil

        return (0..<toc.trackCount).map { index in
            let number = index + 1
            let title = toc.titles.indices.contains(index) ? nonempty(toc.titles[index], "Track \(number)") : "Track \(number)"
            let trackArtist = toc.performers.indices.contains(index) ? nonempty(toc.performers[index], artist) : artist
            let start = toc.startLSNs.indices.contains(index) ? toc.startLSNs[index] : 0
            let length = toc.lengthLSNs.indices.contains(index) ? toc.lengthLSNs[index] : 0
            let duration = toc.durations.indices.contains(index) ? toc.durations[index] : 0
            return SACDDiscTrack(
                number: number,
                title: title,
                artist: trackArtist,
                album: album,
                year: safeYear,
                duration: duration,
                startLSN: start,
                lengthLSN: length,
                sampleRateHz: toc.sampleRateHz,
                channelCount: toc.channelCount,
                isDST: toc.isDST
            )
        }
    }

    /// Extract one uncompressed DSD track to a cached DFF and return that URL.
    static func playbackURL(for track: Track) throws -> URL {
        let fileURL = track.url
        guard let number = VirtualTrackPath.sacdTrack(from: track.cataloguePath) ?? track.trackNumber else {
            throw SACDError.extractFailed
        }
        let tracks = try listTracks(url: fileURL)
        guard let discTrack = tracks.first(where: { $0.number == number }) else {
            throw SACDError.extractFailed
        }
        if discTrack.isDST { throw SACDError.dstCompressed }

        let cache = try cacheURL(for: fileURL, track: number)
        if FileManager.default.fileExists(atPath: cache.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: cache.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > 128 {
            return cache
        }

        try extract(track: discTrack, from: fileURL, to: cache)
        return cache
    }

    // MARK: - Extract

    private static func extract(track: SACDDiscTrack, from iso: URL, to output: URL) throws {
        guard track.startLSN > 0, track.lengthLSN > 0 else { throw SACDError.extractFailed }
        let layout = try layout(of: iso)
        let map = try NSData(contentsOf: iso, options: [.mappedIfSafe])
        let preamble = dffPreamble(sampleRate: track.sampleRateHz, channels: track.channelCount)
        let tmp = output.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: tmp)
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let out = try FileHandle(forWritingTo: tmp)
        try out.write(contentsOf: preamble)

        var dataBytes: UInt64 = 0
        let end = track.startLSN &+ track.lengthLSN
        var lsn = track.startLSN
        while lsn < end {
            let sector = try mappedSector(map, lsn: lsn, layout: layout)
            let chunk = demuxAudioPackets(sector)
            if !chunk.isEmpty {
                try out.write(contentsOf: chunk)
                dataBytes += UInt64(chunk.count)
            }
            lsn += 1
        }

        let fileSize = UInt64(preamble.count) + dataBytes
        var frm8 = Data()
        appendU64BE(&frm8, fileSize > 12 ? fileSize - 12 : 0)
        try out.seek(toOffset: 4)
        try out.write(contentsOf: frm8)
        var dsdSize = Data()
        appendU64BE(&dsdSize, dataBytes)
        try out.seek(toOffset: UInt64(preamble.count - 8))
        try out.write(contentsOf: dsdSize)
        try out.close()

        guard dataBytes > 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw SACDError.extractFailed
        }
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: tmp, to: output)
    }

    private static func cacheURL(for iso: URL, track: Int) throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("AudioHarbor", isDirectory: true)
            .appendingPathComponent("SACD", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mtime = (try? iso.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let key = "\(iso.path)|\(mtime)|\(track)"
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("\(digest).dff")
    }

    // MARK: - TOC

    private struct AreaInfo {
        var trackCount: Int
        var sampleRateHz: Int
        var channelCount: Int
        var isDST: Bool
        var startLSNs: [UInt32]
        var lengthLSNs: [UInt32]
        var durations: [TimeInterval]
        var titles: [String]
        var performers: [String]
        var trackStart: UInt32
        var trackEnd: UInt32
    }

    private struct MasterNames {
        var albumTitle: String = ""
        var albumArtist: String = ""
        var discTitle: String = ""
        var discArtist: String = ""
    }

    private enum SectorLayout {
        case raw2048
        case raw2352

        var stride: UInt64 {
            switch self {
            case .raw2048: 2048
            case .raw2352: 2352
            }
        }

        var header: UInt64 {
            switch self {
            case .raw2048: 0
            case .raw2352: 16
            }
        }
    }

    private static func layout(of url: URL) throws -> SectorLayout {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if let raw = try? peekSignature(handle, layout: .raw2048), raw == masterSignature {
            return .raw2048
        }
        if let raw = try? peekSignature(handle, layout: .raw2352), raw == masterSignature {
            return .raw2352
        }
        throw SACDError.notScarletBook
    }

    private static func peekSignature(_ handle: FileHandle, layout: SectorLayout) throws -> Data {
        try handle.seek(toOffset: offset(lsn: masterTOCSector, layout: layout))
        let data = try handle.read(upToCount: 8) ?? Data()
        return data
    }

    private static func offset(lsn: UInt32, layout: SectorLayout) -> UInt64 {
        UInt64(lsn) * layout.stride + layout.header
    }

    private static func readSector(_ handle: FileHandle, lsn: UInt32, layout: SectorLayout) throws -> Data {
        try handle.seek(toOffset: offset(lsn: lsn, layout: layout))
        let data = try handle.read(upToCount: sectorSize) ?? Data()
        guard data.count == sectorSize else { throw SACDError.truncated }
        return data
    }

    private static func readSectors(_ handle: FileHandle, start: UInt32, count: Int, layout: SectorLayout) throws -> Data {
        var out = Data()
        out.reserveCapacity(count * sectorSize)
        for i in 0..<count {
            out.append(try readSector(handle, lsn: start + UInt32(i), layout: layout))
        }
        return out
    }

    private static func mappedSector(_ map: NSData, lsn: UInt32, layout: SectorLayout) throws -> Data {
        let start = Int(offset(lsn: lsn, layout: layout))
        guard start + sectorSize <= map.length else { throw SACDError.truncated }
        return map.subdata(with: NSRange(location: start, length: sectorSize))
    }

    private static func readMasterText(_ handle: FileHandle, layout: SectorLayout) throws -> MasterNames {
        // Master text lives in the sectors after SACDMTOC (commonly LSN 511).
        for extra in 1...10 {
            let sector = try readSector(handle, lsn: masterTOCSector + UInt32(extra), layout: layout)
            if sector.prefix(8) == masterTextSignature {
                return parseMasterText(sector)
            }
        }
        return MasterNames()
    }

    private static func parseMasterText(_ bytes: Data) -> MasterNames {
        guard bytes.count >= 40 else { return MasterNames() }
        func at(_ pos: Int) -> String {
            let pointer = be16(bytes, pos)
            return cString(bytes, at: Int(pointer))
        }
        return MasterNames(
            albumTitle: at(16),
            albumArtist: at(18),
            discTitle: at(32),
            discArtist: at(34)
        )
    }

    private static func parseAreaTOC(_ area: Data) throws -> AreaInfo {
        guard area.count >= sectorSize else { throw SACDError.truncated }
        let id = area.prefix(8)
        guard id == stereoSignature || id == multiSignature else { throw SACDError.notScarletBook }

        // Sequential Area_TOC header — matches sacd-rs / Scarlet Book.
        var o = 8
        o += 2 // version
        let size = Int(be16(area, o)); o += 2
        o += 4 // reserved
        o += 4 // max byte rate
        let sampleFrequencyCode = area[o]; o += 1
        let frameFormat = area[o] & 0x0F; o += 1
        o += 10
        let channelCount = max(1, Int(area[o])); o += 1
        o += 1 // area config
        o += 1 // max available channels
        o += 1 // mute
        o += 12
        o += 1 // copy management
        o += 15
        o += 3 // playtime
        o += 1 // reserved
        o += 1 // track offset
        let trackCount = Int(area[o]); o += 1
        o += 2
        let trackStart = be32(area, o); o += 4
        let trackEnd = be32(area, o); o += 4
        o += 1 // text area count
        o += 7
        o += 32 // 8 locales
        o += 8
        let trackTextOffset = be16(area, o)
        guard trackCount > 0, trackCount <= 255 else { throw SACDError.truncated }

        let sampleRateHz = sampleFrequencyCode == 0x08 ? 5_644_800 : 2_822_400
        let isDST = frameFormat == 0

        var startLSNs = Array(repeating: UInt32(0), count: trackCount)
        var lengthLSNs = Array(repeating: UInt32(0), count: trackCount)
        var durations = Array(repeating: TimeInterval(0), count: trackCount)
        var titles = Array(repeating: "", count: trackCount)
        var performers = Array(repeating: "", count: trackCount)

        let bound = min(area.count, max(size, 2) * sectorSize)
        var cursor = sectorSize
        while cursor + 8 <= bound {
            let sig = area.subdata(in: cursor..<(cursor + 8))
            if sig == trackList1 {
                var p = cursor + 8
                for i in 0..<255 {
                    guard p + 4 <= area.count else { break }
                    let value = be32(area, p)
                    if i < trackCount { startLSNs[i] = value }
                    p += 4
                }
                for i in 0..<255 {
                    guard p + 4 <= area.count else { break }
                    let value = be32(area, p)
                    if i < trackCount { lengthLSNs[i] = value }
                    p += 4
                }
            } else if sig == trackList2 {
                var p = cursor + 8
                for _ in 0..<255 {
                    p += 4
                }
                for i in 0..<255 {
                    guard p + 4 <= area.count else { break }
                    if i < trackCount {
                        durations[i] = timeInterval(minutes: area[p], seconds: area[p + 1], frames: area[p + 2])
                    }
                    p += 4
                }
            }
            cursor += sectorSize
        }

        if trackTextOffset > 0 {
            let textStart = Int(trackTextOffset) * sectorSize
            if textStart + 8 <= area.count, area.subdata(in: textStart..<(textStart + 8)) == trackTextSig {
                let parsed = parseTrackText(area, start: textStart, trackCount: trackCount)
                titles = parsed.titles
                performers = parsed.performers
            }
        }

        for i in 0..<trackCount {
            if startLSNs[i] == 0 {
                if i == 0 {
                    startLSNs[i] = trackStart
                } else if startLSNs[i - 1] > 0, lengthLSNs[i - 1] > 0 {
                    startLSNs[i] = startLSNs[i - 1] &+ lengthLSNs[i - 1]
                }
            }
            if lengthLSNs[i] == 0 {
                if i + 1 < trackCount, startLSNs[i + 1] > startLSNs[i] {
                    lengthLSNs[i] = startLSNs[i + 1] &- startLSNs[i]
                } else if trackEnd > startLSNs[i] {
                    lengthLSNs[i] = trackEnd &- startLSNs[i]
                }
            }
        }

        return AreaInfo(
            trackCount: trackCount,
            sampleRateHz: sampleRateHz,
            channelCount: channelCount,
            isDST: isDST,
            startLSNs: startLSNs,
            lengthLSNs: lengthLSNs,
            durations: durations,
            titles: titles,
            performers: performers,
            trackStart: trackStart,
            trackEnd: trackEnd
        )
    }

    private static func parseTrackText(_ area: Data, start: Int, trackCount: Int) -> (titles: [String], performers: [String]) {
        var titles = Array(repeating: "", count: trackCount)
        var performers = Array(repeating: "", count: trackCount)
        let positions = start + 8
        for track in 0..<trackCount {
            let posOff = positions + track * 2
            guard posOff + 2 <= area.count else { break }
            let rel = Int(be16(area, posOff))
            guard rel > 0 else { continue }
            let textStart = start + rel
            guard textStart < area.count else { continue }
            let nItems = Int(area[textStart])
            var ptr = textStart + 4
            for _ in 0..<nItems {
                guard ptr + 2 < area.count else { break }
                let type = area[ptr]
                ptr += 2
                let stringStart = ptr
                while ptr < area.count, area[ptr] != 0 { ptr += 1 }
                let raw = area.subdata(in: stringStart..<ptr)
                let text = decodeText(raw)
                if ptr < area.count { ptr += 1 }
                while ptr < area.count, area[ptr] == 0 { ptr += 1 }
                if type == 0x01 { titles[track] = text }
                if type == 0x02 { performers[track] = text }
            }
        }
        return (titles, performers)
    }

    // MARK: - Sector demux (uncompressed DSD)

    private static func demuxAudioPackets(_ sector: Data) -> Data {
        guard sector.count == sectorSize else { return Data() }
        let header = sector[0]
        let packetCount = Int((header >> 5) & 0x07)
        let frameInfoCount = Int((header >> 2) & 0x07)
        let dstEncoded = (header & 0x01) != 0
        var offset = 1
        var packets: [(start: Bool, type: UInt8, length: Int)] = []
        packets.reserveCapacity(packetCount)
        for _ in 0..<packetCount {
            guard offset + 2 <= sector.count else { return Data() }
            let b0 = sector[offset]
            let b1 = sector[offset + 1]
            packets.append((
                start: (b0 & 0x80) != 0,
                type: (b0 >> 3) & 0x07,
                length: Int((UInt16(b0 & 0x07) << 8) | UInt16(b1))
            ))
            offset += 2
        }
        let frameInfoSize = dstEncoded ? 4 : 3
        offset += frameInfoCount * frameInfoSize
        guard offset <= sector.count else { return Data() }

        var audio = Data()
        for packet in packets {
            guard offset + packet.length <= sector.count else { break }
            if packet.type == 2 {
                audio.append(sector.subdata(in: offset..<(offset + packet.length)))
            }
            offset += packet.length
        }
        return audio
    }

    // MARK: - DFF wrap

    private static func dffPreamble(sampleRate: Int, channels: Int) -> Data {
        var prop = Data()
        prop.append(contentsOf: "SND ".utf8)
        prop.append(contentsOf: "FS  ".utf8)
        appendU64BE(&prop, 4)
        appendU32BE(&prop, UInt32(sampleRate))
        prop.append(contentsOf: "CHNL".utf8)
        appendU64BE(&prop, UInt64(2 + 4 * channels))
        appendU16BE(&prop, UInt16(channels))
        let ids = ["SLFT", "SRGT", "C   ", "LFE ", "LS  ", "RS  ", "L   ", "R   "]
        for i in 0..<channels {
            prop.append(contentsOf: (i < ids.count ? ids[i] : "C\(i)  ").utf8)
        }

        var d = Data()
        d.append(contentsOf: "FRM8".utf8)
        appendU64BE(&d, 0)
        d.append(contentsOf: "DSD ".utf8)
        d.append(contentsOf: "PROP".utf8)
        appendU64BE(&d, UInt64(prop.count))
        d.append(prop)
        d.append(contentsOf: "DSD ".utf8)
        appendU64BE(&d, 0)
        return d
    }

    // MARK: - Bytes

    private static func be16(_ d: Data, _ o: Int) -> UInt16 {
        guard o + 1 < d.count else { return 0 }
        return (UInt16(d[o]) << 8) | UInt16(d[o + 1])
    }

    private static func be32(_ d: Data, _ o: Int) -> UInt32 {
        guard o + 3 < d.count else { return 0 }
        return (UInt32(d[o]) << 24) | (UInt32(d[o + 1]) << 16) | (UInt32(d[o + 2]) << 8) | UInt32(d[o + 3])
    }

    private static func appendU16BE(_ d: inout Data, _ v: UInt16) {
        d.append(UInt8(v >> 8))
        d.append(UInt8(v & 0xFF))
    }

    private static func appendU32BE(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8((v >> 24) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF))
        d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8(v & 0xFF))
    }

    private static func appendU64BE(_ d: inout Data, _ v: UInt64) {
        for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
            d.append(UInt8((v >> shift) & 0xFF))
        }
    }

    private static func cString(_ d: Data, at pos: Int) -> String {
        guard pos > 0, pos < d.count else { return "" }
        var end = pos
        while end < d.count, d[end] != 0 { end += 1 }
        return decodeText(d.subdata(in: pos..<end))
    }

    private static func decodeText(_ raw: Data) -> String {
        let text = String(bytes: raw, encoding: .isoLatin1) ?? String(decoding: raw, as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func timeInterval(minutes: UInt8, seconds: UInt8, frames: UInt8) -> TimeInterval {
        Double(minutes) * 60 + Double(seconds) + Double(frames) / Double(framesPerSecond)
    }

    private static func nonempty(_ values: String...) -> String {
        values.first { !$0.isEmpty } ?? ""
    }
}

/// DSDIFF DIIN/MARK chapters — album-length DFF dumps that should be tracks.
enum DFFChapters {
    struct Chapter: Sendable {
        var number: Int
        var title: String
        var startSample: UInt64
        var sampleCount: UInt64
        var duration: TimeInterval
    }

    static func list(url: URL, header: DSDDecoder.Header) -> [Chapter] {
        guard header.format == .dff, let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return []
        }
        guard data.count >= 16, data.prefix(4) == Data("FRM8".utf8) else { return [] }

        var marks: [(sample: UInt64, type: UInt16, title: String)] = []
        var offset = 12
        while offset + 12 <= data.count {
            let id = String(data: data.subdata(in: offset..<(offset + 4)), encoding: .ascii) ?? ""
            let size = Int(be64(data, offset + 4))
            let payload = offset + 12
            guard size >= 0, payload + size <= data.count else { break }

            if id == "DIIN" {
                parseDIIN(data.subdata(in: payload..<(payload + size)), sampleRate: header.sampleRate, into: &marks)
            }
            offset = payload + size + (size % 2)
        }

        let starts = marks.filter { $0.type == 0 }.sorted { $0.sample < $1.sample }
        guard starts.count >= 2 else { return [] }

        let total = header.sampleCountPerChannel
        return starts.enumerated().map { index, mark in
            let next = index + 1 < starts.count ? starts[index + 1].sample : total
            let count = next > mark.sample ? next - mark.sample : 0
            let title = mark.title.isEmpty ? "Track \(index + 1)" : mark.title
            return Chapter(
                number: index + 1,
                title: title,
                startSample: mark.sample,
                sampleCount: count,
                duration: header.sampleRate > 0 ? Double(count) / Double(header.sampleRate) : 0
            )
        }
    }

    private static func parseDIIN(_ body: Data, sampleRate: Int, into marks: inout [(sample: UInt64, type: UInt16, title: String)]) {
        var offset = 0
        while offset + 12 <= body.count {
            let id = String(data: body.subdata(in: offset..<(offset + 4)), encoding: .ascii) ?? ""
            let size = Int(be64(body, offset + 4))
            let payload = offset + 12
            guard size >= 0, payload + size <= body.count else { break }
            if id == "MARK", size >= 19 {
                let hours = Int(be16(body, payload))
                let minutes = Int(body[payload + 2])
                let seconds = Int(body[payload + 3])
                let extra = be32(body, payload + 4)
                let type = be16(body, payload + 12)
                var title = ""
                if size >= 22 {
                    let count = Int(be32(body, payload + 18))
                    let titleAt = payload + 22
                    if count > 0, titleAt + count <= payload + size {
                        title = String(bytes: body.subdata(in: titleAt..<(titleAt + count)), encoding: .isoLatin1)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }
                }
                let sample = UInt64((hours * 3600 + minutes * 60 + seconds) * sampleRate) + UInt64(extra)
                marks.append((sample, type, title))
            }
            offset = payload + size + (size % 2)
        }
    }

    private static func be16(_ d: Data, _ o: Int) -> UInt16 {
        guard o + 1 < d.count else { return 0 }
        return (UInt16(d[o]) << 8) | UInt16(d[o + 1])
    }

    private static func be32(_ d: Data, _ o: Int) -> UInt32 {
        guard o + 3 < d.count else { return 0 }
        return (UInt32(d[o]) << 24) | (UInt32(d[o + 1]) << 16) | (UInt32(d[o + 2]) << 8) | UInt32(d[o + 3])
    }

    private static func be64(_ d: Data, _ o: Int) -> UInt64 {
        guard o + 7 < d.count else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(d[o + i]) }
        return v
    }
}

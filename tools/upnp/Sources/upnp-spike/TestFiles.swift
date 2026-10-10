import Foundation
import UPnPCommon

/// Quiet test tones (440 Hz, −20 dBFS), made on the Mac that runs the test: written here as
/// WAV, converted with macOS's own `afconvert`. Every second holds whole cycles of 440 Hz, so
/// one-second blocks repeat without a seam.
enum TestFiles {
    struct Set {
        let directory: URL
        /// 70 s, 96 kHz / 24-bit FLAC — long enough to seek and to wait for its end.
        let seek: URL
        /// One continuous tone cut in two near a crest: any gap or click at the change is audible.
        let gaplessFirst: URL
        let gaplessSecond: URL
        /// One 15 s file per format and rate.
        let formats: URL
        /// Files that could not be made (old macOS without the encoder); the test goes on without them.
        let skipped: [String]
    }

    private static let frequency = 440.0
    private static let level = pow(10, -20.0 / 20)

    static func make(in directory: URL) throws -> Set {
        let manager = FileManager.default
        let formats = directory.appendingPathComponent("formats")
        try manager.createDirectory(at: formats, withIntermediateDirectories: true)
        var skipped: [String] = []

        func attempt(_ name: String, _ work: () throws -> Void) {
            do { try work() } catch { skipped.append("\(name): \(error)") }
        }

        // FLAC across the rates (where the renderer's limit is), each container once, and the WAV
        // the app would stream for DSD (88.2 kHz / 24-bit) with both header variants.
        let flacs: [(String, Int, Int)] = [
            ("01-flac-44.1k-16bit", 44100, 16), ("02-flac-44.1k-24bit", 44100, 24),
            ("03-flac-88.2k-24bit", 88200, 24), ("04-flac-96k-24bit", 96000, 24),
            ("05-flac-176.4k-24bit", 176400, 24), ("06-flac-192k-24bit", 192000, 24),
            ("07-flac-352.8k-24bit", 352800, 24),
        ]
        for (name, rate, bits) in flacs {
            attempt(name) {
                try encode(tone(rate: rate, bits: bits, seconds: 15), rate: rate, bits: bits,
                           to: formats.appendingPathComponent(name + ".flac"), fileType: "flac", dataFormat: "flac")
            }
        }
        let cd = tone(rate: 44100, bits: 16, seconds: 15)
        try writeWAV(formats.appendingPathComponent("08-wav-44.1k-16bit.wav"), rate: 44100, bits: 16, samples: cd)
        let dsdAsPCM = tone(rate: 88200, bits: 24, seconds: 15)
        try writeWAV(formats.appendingPathComponent("09-wav-88.2k-24bit.wav"), rate: 88200, bits: 24, samples: dsdAsPCM)
        try writeWAV(formats.appendingPathComponent("10-wav-88.2k-24bit-extensible.wav"), rate: 88200, bits: 24,
                     samples: dsdAsPCM, extensible: true)
        attempt("11-aiff-44.1k-16bit") {
            try encode(cd, rate: 44100, bits: 16, to: formats.appendingPathComponent("11-aiff-44.1k-16bit.aiff"),
                       fileType: "AIFF", dataFormat: "BEI16")
        }
        attempt("12-alac-44.1k-16bit") {
            try encode(cd, rate: 44100, bits: 16, to: formats.appendingPathComponent("12-alac-44.1k-16bit.m4a"),
                       fileType: "m4af", dataFormat: "alac")
        }
        attempt("13-alac-96k-24bit") {
            try encode(tone(rate: 96000, bits: 24, seconds: 15), rate: 96000, bits: 24,
                       to: formats.appendingPathComponent("13-alac-96k-24bit.m4a"), fileType: "m4af", dataFormat: "alac")
        }
        attempt("14-aac-44.1k") {
            try encode(cd, rate: 44100, bits: 16, to: formats.appendingPathComponent("14-aac-44.1k.m4a"),
                       fileType: "m4af", dataFormat: "aac")
        }

        let seek = try encodeFLACOrWAV(tone(rate: 96000, bits: 24, seconds: 70), rate: 96000, bits: 24,
                                       to: directory.appendingPathComponent("tone-96k-24bit-70s"))
        // 25 frames into a second of 440 Hz at 44.1 kHz is close to a crest of the sine.
        let block = secondOfTone(rate: 44100, bits: 24)
        let split = 25 * 2 * 3
        var first = Data(capacity: block.count * 31)
        for _ in 0..<30 { first.append(block) }
        first.append(block.prefix(split))
        var second = Data(block.suffix(from: block.startIndex + split))
        for _ in 0..<19 { second.append(block) }
        let gaplessFirst = try encodeFLACOrWAV(first, rate: 44100, bits: 24, to: directory.appendingPathComponent("gapless-1"))
        let gaplessSecond = try encodeFLACOrWAV(second, rate: 44100, bits: 24, to: directory.appendingPathComponent("gapless-2"))

        return Set(directory: directory, seek: seek, gaplessFirst: gaplessFirst, gaplessSecond: gaplessSecond,
                   formats: formats, skipped: skipped)
    }

    // MARK: - Samples

    static func secondOfTone(rate: Int, bits: Int) -> Data {
        let full = Double((1 << (bits - 1)) - 1)
        let bytes = bits / 8
        var data = Data(capacity: rate * 2 * bytes)
        for index in 0..<rate {
            let value = Int32((level * full * sin(2 * .pi * frequency * Double(index) / Double(rate))).rounded())
            withUnsafeBytes(of: value.littleEndian) { sample in
                data.append(contentsOf: sample.prefix(bytes))
                data.append(contentsOf: sample.prefix(bytes))
            }
        }
        return data
    }

    static func tone(rate: Int, bits: Int, seconds: Int) -> Data {
        let block = secondOfTone(rate: rate, bits: bits)
        var data = Data(capacity: block.count * seconds)
        for _ in 0..<seconds { data.append(block) }
        return data
    }

    // MARK: - Files

    /// Little-endian PCM WAV, stereo. `extensible`: WAVE_FORMAT_EXTENSIBLE instead of the plain PCM tag,
    /// which some decoders insist on above 16 bits and others reject.
    static func writeWAV(_ url: URL, rate: Int, bits: Int, samples: Data, extensible: Bool = false) throws {
        var header = Data()
        func append(_ text: String) { header.append(contentsOf: Array(text.utf8)) }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        let blockAlign = UInt16(2 * bits / 8)
        let formatSize: UInt32 = extensible ? 40 : 16
        append("RIFF")
        u32(4 + 8 + formatSize + 8 + UInt32(samples.count))
        append("WAVE")
        append("fmt ")
        u32(formatSize)
        u16(extensible ? 0xFFFE : 1)
        u16(2)
        u32(UInt32(rate))
        u32(UInt32(rate) * UInt32(blockAlign))
        u16(blockAlign)
        u16(UInt16(bits))
        if extensible {
            u16(22)
            u16(UInt16(bits))
            u32(0x3) // front left + front right
            // KSDATAFORMAT_SUBTYPE_PCM, 00000001-0000-0010-8000-00AA00389B71
            header.append(contentsOf: [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00,
                                       0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71])
        }
        append("data")
        u32(UInt32(samples.count))
        try (header + samples).write(to: url)
    }

    /// WAV first, then `afconvert` into the target; the WAV is removed again.
    static func encode(_ samples: Data, rate: Int, bits: Int, to target: URL, fileType: String, dataFormat: String) throws {
        let wav = target.deletingPathExtension().appendingPathExtension("source.wav")
        try writeWAV(wav, rate: rate, bits: bits, samples: samples)
        defer { try? FileManager.default.removeItem(at: wav) }
        try? FileManager.default.removeItem(at: target)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", fileType, "-d", dataFormat, wav.path, target.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ToolError("afconvert \(fileType)/\(dataFormat) exited with \(process.terminationStatus)")
        }
    }

    /// FLAC when this Mac can encode it, else the WAV — the essential files must exist.
    static func encodeFLACOrWAV(_ samples: Data, rate: Int, bits: Int, to base: URL) throws -> URL {
        let flac = base.appendingPathExtension("flac")
        if (try? encode(samples, rate: rate, bits: bits, to: flac, fileType: "flac", dataFormat: "flac")) != nil {
            return flac
        }
        let wav = base.appendingPathExtension("wav")
        try writeWAV(wav, rate: rate, bits: bits, samples: samples)
        return wav
    }
}

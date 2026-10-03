import Foundation

/// Length-prefixed frames: `[UInt32 BE length][kind][payload]`.
/// `length` covers kind + payload. Kind `0` = UTF-8 JSON, `1` = raw binary (artwork).
enum FrameKind: UInt8, Sendable {
    case json = 0
    case binary = 1
}

enum FrameCodec {
    static let headerSize = 5 // 4 length + 1 kind

    static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(value)
        return wrap(kind: .json, payload: payload)
    }

    static func encodeBinary(_ payload: Data) -> Data {
        wrap(kind: .binary, payload: payload)
    }

    static func wrap(kind: FrameKind, payload: Data) -> Data {
        var length = UInt32(1 + payload.count).bigEndian
        var data = Data(count: headerSize + payload.count)
        withUnsafeBytes(of: &length) { lengthBytes in
            data.replaceSubrange(0..<4, with: lengthBytes)
        }
        data[4] = kind.rawValue
        data.replaceSubrange(headerSize..<(headerSize + payload.count), with: payload)
        return data
    }

    /// Append `chunk` into `buffer` and yield complete frames.
    static func feed(chunk: Data, into buffer: inout Data) throws -> [DecodedFrame] {
        buffer.append(chunk)
        var frames: [DecodedFrame] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length >= 1 else {
                throw FrameError.invalidLength(Int(length))
            }
            guard length <= RemoteProtocol.maxFrameBytes else {
                throw FrameError.frameTooLarge(Int(length))
            }
            let total = 4 + Int(length)
            guard buffer.count >= total else { break }
            let kindByte = buffer[4]
            guard let kind = FrameKind(rawValue: kindByte) else {
                throw FrameError.unknownKind(kindByte)
            }
            let payload = Data(buffer.subdata(in: headerSize..<total))
            buffer.removeSubrange(0..<total)
            frames.append(DecodedFrame(kind: kind, payload: payload))
        }
        return frames
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, from payload: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: payload)
    }
}

struct DecodedFrame: Sendable {
    var kind: FrameKind
    var payload: Data
}

enum FrameError: Error, LocalizedError {
    case invalidLength(Int)
    case frameTooLarge(Int)
    case unknownKind(UInt8)

    var errorDescription: String? {
        switch self {
        case .invalidLength(let n): "Invalid frame length \(n)"
        case .frameTooLarge(let n): "Frame too large (\(n) bytes)"
        case .unknownKind(let k): "Unknown frame kind \(k)"
        }
    }
}

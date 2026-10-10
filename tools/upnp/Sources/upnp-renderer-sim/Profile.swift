import Foundation
import UPnPCommon

/// What the simulated renderer claims and accepts. The defaults are a guess at the Expert 220 —
/// replace them with `--sink-file protocolinfo-sink.txt` from a spike run on the real device.
struct Profile {
    var name = "Expert 220 Simulator"
    var manufacturer = "Devialet (simulated)"
    var modelName = "Expert 220"
    var httpPort: UInt16 = 49152
    var uuid = "uuid:" + UUID().uuidString.lowercased()
    var supportsNext = true
    var supportsEvents = true
    var maxSampleRate = 192_000.0
    /// Seconds in TRANSITIONING before PLAYING, on top of the fetch.
    var startDelay = 0.4
    var initialVolume = 20
    /// No audio out of the Mac; position comes from a clock.
    var silent = false
    var sink: [String] = Profile.defaultSink

    static let defaultSink = [
        "audio/flac", "audio/x-flac", "audio/wav", "audio/x-wav", "audio/wave",
        "audio/aiff", "audio/x-aiff", "audio/mp4", "audio/x-m4a", "audio/mpeg",
    ].map { "http-get:*:\($0):*" }

    var acceptedMIMETypes: Set<String> {
        Set(sink.compactMap { entry in
            let parts = entry.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            return parts.count >= 3 ? String(parts[2]).lowercased() : nil
        })
    }

    static func parse(_ arguments: [String]) throws -> Profile {
        var profile = Profile()
        var index = 1
        func value() throws -> String {
            index += 1
            guard index < arguments.count else { throw ToolError("\(arguments[index - 1]) needs a value") }
            return arguments[index]
        }
        while index < arguments.count {
            switch arguments[index] {
            case "--name": profile.name = try value()
            case "--port":
                guard let port = UInt16(try value()) else { throw ToolError("--port <number>") }
                profile.httpPort = port
            case "--uuid": profile.uuid = "uuid:" + (try value())
            case "--no-next": profile.supportsNext = false
            case "--no-events": profile.supportsEvents = false
            case "--max-rate":
                guard let rate = Double(try value()) else { throw ToolError("--max-rate <Hz>") }
                profile.maxSampleRate = rate
            case "--start-delay":
                guard let delay = Double(try value()) else { throw ToolError("--start-delay <seconds>") }
                profile.startDelay = delay
            case "--volume":
                guard let volume = Int(try value()), (0...100).contains(volume) else { throw ToolError("--volume 0…100") }
                profile.initialVolume = volume
            case "--silent": profile.silent = true
            case "--sink-file":
                let text = try String(contentsOfFile: (try value() as NSString).expandingTildeInPath, encoding: .utf8)
                profile.sink = text.split(whereSeparator: { $0 == "\n" || $0 == "," })
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case "--help", "-h":
                print(usage)
                exit(0)
            default:
                throw ToolError("unknown option \(arguments[index])\n\(usage)")
            }
            index += 1
        }
        return profile
    }

    static let usage = """
    upnp-renderer-sim [options]
      --name <text>         friendly name (default "Expert 220 Simulator")
      --port <n>            HTTP port for description / control / events (default 49152)
      --uuid <id>           fixed UDN, so the app's stored output pick survives restarts
      --no-next             no SetNextAVTransportURI (gapless off, like many renderers)
      --no-events           no GENA eventing (control point has to poll)
      --max-rate <Hz>       reject higher sample rates (default 192000)
      --start-delay <s>     time in TRANSITIONING before PLAYING (default 0.4)
      --volume <0…100>      start volume (default 20)
      --silent              no sound on the Mac, position from a clock
      --sink-file <path>    protocolInfo list, one per line (protocolinfo-sink.txt from the spike)
    """
}

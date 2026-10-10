import CryptoKit
import Foundation
import UPnPCommon

// A prototype of Audio Harbor as a music server: shares one folder over UPnP / DLNA, so a
// player such as mconnect on an iPhone can browse it and play the files.

let usage = """
upnp-media-server <music folder> [--name <text>] [--port <n>]
  Shares the folder on the network as a UPnP / DLNA music server.
  --name <text>   name players show (default "Audio Harbor (<folder>)")
  --port <n>      HTTP port (default 49200)
"""

var folder: String?
var name: String?
var port: UInt16 = 49200
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--name": name = arguments.next()
    case "--port":
        guard let value = arguments.next().flatMap(UInt16.init) else {
            print(usage)
            exit(2)
        }
        port = value
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        folder = argument
    }
}
guard let folder else {
    print(usage)
    exit(2)
}

let library: Library
do {
    library = try Library(root: URL(fileURLWithPath: (folder as NSString).expandingTildeInPath))
} catch {
    print("\(error)")
    exit(1)
}
let serverName = "macOS UPnP/1.0 AudioHarborServer/0.1"
let displayName = name ?? "Audio Harbor (\(library.name))"

// The same folder gives the same UDN, so players recognise the server after a restart.
let digest = Array(SHA256.hash(data: Data(library.root.path.utf8)).prefix(16)).map { String(format: "%02x", $0) }.joined()
let udn = "uuid:" + [digest.prefix(8), digest.dropFirst(8).prefix(4), digest.dropFirst(12).prefix(4),
                      digest.dropFirst(16).prefix(4), digest.dropFirst(20)].map(String.init).joined(separator: "-")

let content = ContentServer(library: library, name: displayName, udn: udn, port: port)
let ssdp = SSDPResponder(uuid: udn, httpPort: port, deviceType: Documents.deviceType,
                         serviceTypes: Documents.services, server: serverName)
// Kept at the top level: a server that goes out of scope stops listening.
let http: HTTPServer
do {
    http = try HTTPServer(port: port, serverName: serverName) { request in await content.handle(request) }
    http.start()
    try ssdp.start()
} catch {
    say("failed to start: \(error)")
    exit(1)
}

// Players stream while nobody touches the Mac; idle sleep would cut them off.
let awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Sharing music")
signal(SIGINT, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler {
    ssdp.announce(alive: false)
    ProcessInfo.processInfo.endActivity(awake)
    say("stopped")
    exit(0)
}
interrupt.resume()

say("""
sharing \(library.root.path)
  as "\(displayName)" · \(udn) · port \(port)
  iPhone: mconnect → Server → \(displayName)
  ctrl-C stops (and tells players the server is gone)
""")
dispatchMain()

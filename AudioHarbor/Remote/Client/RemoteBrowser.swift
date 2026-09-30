import Foundation
import Network
import Observation

struct RemoteServerEndpoint: Identifiable, Hashable, Sendable {
    var id: String { "\(name)|\(serverID?.uuidString ?? endpoint.debugDescription)" }
    var name: String
    var serverID: UUID?
    var endpoint: NWEndpoint
    var txt: [String: String]
}

/// Bonjour browser for `_audioharbor._tcp`.
@Observable
@MainActor
final class RemoteBrowser {
    private(set) var servers: [RemoteServerEndpoint] = []
    private(set) var statusText = "Idle"
    private(set) var isBrowsing = false

    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: RemoteProtocol.serviceType,
            domain: "local."
        )
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isBrowsing = true
                    self?.statusText = "Looking for Audio Harbor…"
                case .failed(let error):
                    self?.isBrowsing = false
                    self?.statusText = "Browse failed: \(error.localizedDescription)"
                case .cancelled:
                    self?.isBrowsing = false
                    self?.statusText = "Idle"
                default:
                    break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.apply(results)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        statusText = "Starting…"
    }

    func stop() {
        browser?.cancel()
        browser = nil
        servers = []
        isBrowsing = false
        statusText = "Idle"
    }

    private func apply(_ results: Set<NWBrowser.Result>) {
        var next: [RemoteServerEndpoint] = []
        for result in results {
            var txt: [String: String] = [:]
            if case .bonjour(let metadata) = result.metadata {
                for (key, value) in metadata.dictionary {
                    txt[key] = value
                }
            }
            let name = txt["name"]
                ?? {
                    if case .service(let name, _, _, _) = result.endpoint { return name }
                    return "Audio Harbor"
                }()
            let serverID = txt["id"].flatMap(UUID.init(uuidString:))
            next.append(
                RemoteServerEndpoint(
                    name: name,
                    serverID: serverID,
                    endpoint: result.endpoint,
                    txt: txt
                )
            )
        }
        servers = next.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if servers.isEmpty {
            statusText = isBrowsing ? "No Harbor found on this network" : statusText
        } else {
            statusText = "\(servers.count) Harbor\(servers.count == 1 ? "" : "s") nearby"
        }
    }
}

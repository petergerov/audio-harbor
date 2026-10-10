#if os(macOS)
import Foundation

/// Forwards `PlaybackEngine` calls to Core Audio or the UPnP renderer based on the picked output.
@MainActor
final class RoutingPlaybackEngine: PlaybackEngine {
    let local: CoreAudioPlaybackEngine
    let network: UPnPPlaybackEngine

    private var usingNetwork = false
    private var preferredUID: String?
    private var outputStatusHandler: ((OutputStatus) -> Void)?
    private var outputVolumeHandler: ((Double?) -> Void)?
    private var onTrackEnded: ((Track) -> Void)?
    private var localVolume: Double?
    private var networkVolume: Double?

    var state: PlaybackState { active.state }
    var currentTime: TimeInterval { active.currentTime }
    var duration: TimeInterval { active.duration }
    var activeFormatLabel: String? { active.activeFormatLabel }
    var pathLabel: String { active.pathLabel }
    var meterLeft: Double { active.meterLeft }
    var meterRight: Double { active.meterRight }

    private var active: any PlaybackEngine { usingNetwork ? network : local }

    init(local: CoreAudioPlaybackEngine, network: UPnPPlaybackEngine) {
        self.local = local
        self.network = network
        local.setTrackEndedHandler { [weak self] track in
            self?.onTrackEnded?(track)
        }
        network.setTrackEndedHandler { [weak self] track in
            self?.onTrackEnded?(track)
        }
        local.setOutputVolumeHandler { [weak self] level in
            self?.localVolume = level
            guard let self, !self.usingNetwork else { return }
            self.outputVolumeHandler?(level)
        }
        network.setOutputVolumeHandler { [weak self] level in
            self?.networkVolume = level
            guard let self, self.usingNetwork else { return }
            self.outputVolumeHandler?(level)
        }
        local.setOutputStatusHandler { [weak self] status in
            self?.outputStatusHandler?(status)
        }
        network.setOutputStatusHandler { _ in }
    }

    func load(_ track: Track) async throws {
        try await active.load(track)
    }

    func play() { active.play() }
    func pause() { active.pause() }
    func stop() { active.stop() }
    func seek(to seconds: TimeInterval) { active.seek(to: seconds) }

    func setOutputMode(_ mode: OutputMode) {
        // Network path ignores Exclusive / DoP; keep the local engine in sync for when we return.
        local.setOutputMode(mode)
        network.setOutputMode(mode)
    }

    func setOutputDevice(uid: String?) {
        preferredUID = uid
        let wantNetwork = uid?.hasPrefix("upnp:") == true
        if wantNetwork != usingNetwork {
            active.stop()
            usingNetwork = wantNetwork
            outputVolumeHandler?(usingNetwork ? networkVolume : localVolume)
        }
        if usingNetwork {
            // Leave Core Audio on the system output so Exclusive is not held while streaming.
            local.setOutputDevice(uid: nil)
            network.setOutputDevice(uid: uid)
        } else {
            network.setOutputDevice(uid: nil)
            local.setOutputDevice(uid: uid)
        }
    }

    func setOutputStatusHandler(_ handler: @escaping (OutputStatus) -> Void) {
        outputStatusHandler = handler
        // Re-bind so the local engine pushes current devices immediately.
        local.setOutputStatusHandler { [weak self] status in
            self?.outputStatusHandler?(status)
        }
    }

    func setOutputVolume(_ level: Double) {
        active.setOutputVolume(level)
    }

    func setOutputVolumeHandler(_ handler: @escaping (Double?) -> Void) {
        outputVolumeHandler = handler
        handler(usingNetwork ? networkVolume : localVolume)
    }

    func setTrackEndedHandler(_ handler: @escaping (Track) -> Void) {
        onTrackEnded = handler
    }

    func prepareNext(_ track: Track?) async {
        if usingNetwork {
            await network.prepareNext(track)
        } else {
            await local.prepareNext(track)
        }
    }

    func adoptPreparedNext() -> Track? {
        usingNetwork ? network.adoptPreparedNext() : local.adoptPreparedNext()
    }

    func setNetworkStreamQuality(_ quality: NetworkStreamQuality) {
        network.setNetworkStreamQuality(quality)
    }

    func setNetworkDsdMode(_ mode: NetworkDsdMode) {
        network.setNetworkDsdMode(mode)
    }

    func networkPlayerFormats(uid: String) async -> NetworkPlayerFormats? {
        await network.networkPlayerFormats(uid: uid)
    }
}
#endif

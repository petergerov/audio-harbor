import Foundation
import Observation

@Observable
@MainActor
final class PlaybackService {
    private let engine: any PlaybackEngine
    private let license: LicenseService

    private(set) var currentTrack: Track?
    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0
    /// Display name for the active queue source (playlist name, album, folder…).
    private(set) var queueSourceName: String?
    /// Short label for the context rail header (e.g. "Playlist", "Album").
    private(set) var queueSourceKind: String = "Queue"
    /// True once the last queue entry has played to its end.
    private(set) var queueEnded = false

    /// Mirrored engine state so SwiftUI Observation actually refreshes the UI.
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playbackState: PlaybackState = .idle
    private(set) var activeFormatLabel: String?
    private(set) var pathLabel: String = "Shared"
    private(set) var meterLeft: Double = 0
    private(set) var meterRight: Double = 0

    var outputMode: OutputMode = .shared {
        didSet {
            guard outputMode != oldValue else { return }
            UserDefaults.standard.set(outputMode.rawValue, forKey: Self.outputModeKey)
            engine.setOutputMode(outputMode)
        }
    }

    var dsdStrategy: DSDStrategy = .preferDoP {
        didSet {
            guard dsdStrategy != oldValue else { return }
            UserDefaults.standard.set(dsdStrategy.rawValue, forKey: Self.dsdStrategyKey)
            engine.setDSDStrategy(dsdStrategy)
        }
    }

    var repeatMode: RepeatMode = .off {
        didSet {
            guard repeatMode != oldValue else { return }
            UserDefaults.standard.set(repeatMode.rawValue, forKey: Self.repeatModeKey)
        }
    }

    var isShuffled: Bool = false {
        didSet {
            guard isShuffled != oldValue else { return }
            UserDefaults.standard.set(isShuffled, forKey: Self.shuffleKey)
            // Keep the current track on the deck, redraw everything after it.
            rebuildPlayOrder(anchoredTo: queueIndex)
        }
    }

    var state: PlaybackState { playbackState }
    var isPlaying: Bool { playbackState == .playing }

    private var syncTimer: Timer?
    /// Guards against two loads overlapping — the later one wins.
    private var loadGeneration: UInt64 = 0
    /// Indices into `queue`, in the order they play — the natural order, or a shuffled draw.
    private var playOrder: [Int] = []
    private var orderPosition: Int = 0

    private static let outputModeKey = "audioharbor.outputMode"
    private static let dsdStrategyKey = "audioharbor.dsdStrategy"
    private static let repeatModeKey = "audioharbor.repeatMode"
    private static let shuffleKey = "audioharbor.shuffle"

    init(engine: any PlaybackEngine, license: LicenseService) {
        self.engine = engine
        self.license = license
        if let raw = UserDefaults.standard.string(forKey: Self.outputModeKey),
           let mode = OutputMode(rawValue: raw) {
            outputMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: Self.dsdStrategyKey),
           let strategy = DSDStrategy(rawValue: raw) {
            dsdStrategy = strategy
        }
        if let raw = UserDefaults.standard.string(forKey: Self.repeatModeKey),
           let mode = RepeatMode(rawValue: raw) {
            repeatMode = mode
        }
        isShuffled = UserDefaults.standard.bool(forKey: Self.shuffleKey)
        engine.setOutputMode(outputMode)
        engine.setDSDStrategy(dsdStrategy)
        engine.setTrackEndedHandler { [weak self] endedTrack in
            self?.advanceAfterTrackEnd(after: endedTrack)
        }
        syncFromEngine()
    }

    func play(
        track: Track,
        in queueTracks: [Track]? = nil,
        sourceName: String? = nil,
        sourceKind: String? = nil
    ) {
        guard allowPlayback() else { return }

        if let queueTracks {
            queue = queueTracks
            queueIndex = queueTracks.firstIndex(of: track) ?? 0
        } else {
            queue = [track]
            queueIndex = 0
        }
        rebuildPlayOrder(anchoredTo: queueIndex)

        if let sourceName, !sourceName.isEmpty {
            queueSourceName = sourceName
            queueSourceKind = sourceKind ?? "Queue"
        } else if queueTracks != nil, !track.album.isEmpty {
            queueSourceName = track.album
            queueSourceKind = sourceKind ?? "Album"
        } else {
            queueSourceName = nil
            queueSourceKind = "Queue"
        }

        Task { await loadAndPlay(track) }
    }

    func togglePlayPause() {
        if isPlaying {
            engine.pause()
            stopSyncing()
            syncFromEngine()
        } else if let track = currentTrack {
            guard allowPlayback() else { return }
            // After the queue ran out the file sits at its end — start it over.
            if queueEnded {
                Task { await loadAndPlay(track) }
                return
            }
            engine.play()
            syncFromEngine()
            startSyncing()
        }
    }

    func playNext() {
        // Pressing skip always moves on, whatever the repeat mode says.
        guard let index = stepForward(wrapping: true) else { return }
        queueIndex = index
        Task { await loadAndPlay(queue[index]) }
    }

    func playPrevious() {
        guard !queue.isEmpty, !playOrder.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        orderPosition = (orderPosition - 1 + playOrder.count) % playOrder.count
        queueIndex = playOrder[orderPosition]
        Task { await loadAndPlay(queue[queueIndex]) }
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.cycled
    }

    func toggleShuffle() {
        isShuffled.toggle()
    }

    /// End of file: roll on to the next entry in play order, or stop on the last one.
    private func advanceAfterTrackEnd(after endedTrack: Track) {
        // A late end signal from a track we already left must not skip the current one.
        guard endedTrack.id == currentTrack?.id else { return }

        if repeatMode == .one, let track = currentTrack {
            queueEnded = false
            Task { await loadAndPlay(track) }
            return
        }

        guard let index = stepForward(wrapping: repeatMode == .all) else {
            queueEnded = true
            stopSyncing()
            syncFromEngine()
            return
        }
        queueEnded = false
        queueIndex = index
        Task { await loadAndPlay(queue[index]) }
    }

    /// Next queue index in play order. `nil` when the order ran out and we do not wrap.
    private func stepForward(wrapping: Bool) -> Int? {
        guard !queue.isEmpty else { return nil }
        if playOrder.count != queue.count {
            rebuildPlayOrder(anchoredTo: queueIndex)
        }
        guard !playOrder.isEmpty else { return nil }

        let next = orderPosition + 1
        if next < playOrder.count {
            orderPosition = next
        } else if wrapping {
            // A fresh pass gets a fresh draw, so a shuffled queue does not repeat itself.
            if isShuffled { reshuffleForNewPass() }
            orderPosition = 0
        } else {
            return nil
        }
        return playOrder[orderPosition]
    }

    private func rebuildPlayOrder(anchoredTo index: Int) {
        guard !queue.isEmpty else {
            playOrder = []
            orderPosition = 0
            return
        }
        let anchor = queue.indices.contains(index) ? index : 0
        if isShuffled {
            var rest = Array(queue.indices)
            rest.removeAll { $0 == anchor }
            rest.shuffle()
            playOrder = [anchor] + rest
            orderPosition = 0
        } else {
            playOrder = Array(queue.indices)
            orderPosition = anchor
        }
    }

    private func reshuffleForNewPass() {
        var order = Array(queue.indices)
        order.shuffle()
        // Do not open the new pass with the track that just finished.
        if order.count > 1, order.first == queueIndex {
            order.swapAt(0, order.count - 1)
        }
        playOrder = order
    }

    func playQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        if index == queueIndex, currentTrack != nil {
            if !isPlaying {
                togglePlayPause()
            }
            return
        }
        queueIndex = index
        if let position = playOrder.firstIndex(of: index) {
            orderPosition = position
        } else {
            rebuildPlayOrder(anchoredTo: index)
        }
        Task { await loadAndPlay(queue[index]) }
    }

    func seek(to seconds: TimeInterval) {
        engine.seek(to: seconds)
        syncFromEngine()
        if isPlaying {
            startSyncing()
        }
    }

    private func loadAndPlay(_ track: Track) async {
        guard allowPlayback() else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        currentTrack = track
        queueEnded = false
        stopSyncing()
        playbackState = .loading
        do {
            await ICloudItem.ensureDownloaded(track.url)
            guard generation == loadGeneration else { return }
            try await engine.load(track)
            guard generation == loadGeneration else { return }
            engine.play()
            syncFromEngine()
            startSyncing()
        } catch {
            guard generation == loadGeneration else { return }
            syncFromEngine()
            stopSyncing()
        }
    }

    private func startSyncing() {
        stopSyncing()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromEngine()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }

    private func stopSyncing() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func syncFromEngine() {
        let time = engine.currentTime
        let dur = engine.duration
        let newState = engine.state

        // Always publish while playing so the progress bar moves.
        if abs(time - currentTime) >= 0.01 || newState == .playing {
            currentTime = time
        }
        if dur != duration {
            duration = dur
        }
        if newState != playbackState {
            playbackState = newState
        }
        activeFormatLabel = engine.activeFormatLabel
        pathLabel = engine.pathLabel
        meterLeft = engine.meterLeft
        meterRight = engine.meterRight

        if newState != .playing {
            stopSyncing()
        }
    }

    @discardableResult
    private func allowPlayback() -> Bool {
        if license.canPlay { return true }
        if isPlaying {
            engine.pause()
            stopSyncing()
            syncFromEngine()
        }
        license.requestUnlock()
        return false
    }
}

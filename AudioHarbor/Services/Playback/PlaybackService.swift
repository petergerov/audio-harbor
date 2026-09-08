import Foundation
import Observation

@Observable
@MainActor
final class PlaybackService {
    private let engine: any PlaybackEngine

    private(set) var currentTrack: Track?
    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0
    /// Display name for the active queue source (playlist name, album, folder…).
    private(set) var queueSourceName: String?
    /// Short label for the context rail header (e.g. "Playlist", "Album").
    private(set) var queueSourceKind: String = "Queue"

    /// Mirrored engine state so SwiftUI Observation actually refreshes the UI.
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playbackState: PlaybackState = .idle
    private(set) var activeFormatLabel: String?
    private(set) var pathLabel: String = "Shared"

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

    var state: PlaybackState { playbackState }
    var isPlaying: Bool { playbackState == .playing }

    private var syncTimer: Timer?

    private static let outputModeKey = "audioharbor.outputMode"
    private static let dsdStrategyKey = "audioharbor.dsdStrategy"

    init(engine: any PlaybackEngine) {
        self.engine = engine
        if let raw = UserDefaults.standard.string(forKey: Self.outputModeKey),
           let mode = OutputMode(rawValue: raw) {
            outputMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: Self.dsdStrategyKey),
           let strategy = DSDStrategy(rawValue: raw) {
            dsdStrategy = strategy
        }
        engine.setOutputMode(outputMode)
        engine.setDSDStrategy(dsdStrategy)
        syncFromEngine()
    }

    func play(
        track: Track,
        in queueTracks: [Track]? = nil,
        sourceName: String? = nil,
        sourceKind: String? = nil
    ) {
        if let queueTracks {
            queue = queueTracks
            queueIndex = queueTracks.firstIndex(of: track) ?? 0
        } else {
            queue = [track]
            queueIndex = 0
        }

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
        } else if currentTrack != nil {
            engine.play()
            syncFromEngine()
            startSyncing()
        }
    }

    func playNext() {
        guard !queue.isEmpty else { return }
        queueIndex = (queueIndex + 1) % queue.count
        Task { await loadAndPlay(queue[queueIndex]) }
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        queueIndex = (queueIndex - 1 + queue.count) % queue.count
        Task { await loadAndPlay(queue[queueIndex]) }
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
        currentTrack = track
        stopSyncing()
        playbackState = .loading
        do {
            await ICloudItem.ensureDownloaded(track.url)
            try await engine.load(track)
            engine.play()
            syncFromEngine()
            startSyncing()
        } catch {
            syncFromEngine()
            stopSyncing()
        }
    }

    private func startSyncing() {
        stopSyncing()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
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

        if newState != .playing {
            stopSyncing()
        }
    }
}

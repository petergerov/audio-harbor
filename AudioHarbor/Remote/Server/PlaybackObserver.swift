import Foundation

/// Observes `PlaybackService` and emits coalesced `NowPlayingSnapshot` / `QueueSnapshot` updates.
@MainActor
final class PlaybackObserver {
    private let playback: PlaybackService
    private let onNowPlaying: (NowPlayingSnapshot) -> Void
    private let onQueue: (QueueSnapshot) -> Void

    private var generation: UInt64 = 0
    private var lastNowPlaying: NowPlayingSnapshot?
    private var lastQueueSignature: String = ""
    private var heartbeat: Timer?
    private var started = false

    init(
        playback: PlaybackService,
        onNowPlaying: @escaping (NowPlayingSnapshot) -> Void,
        onQueue: @escaping (QueueSnapshot) -> Void
    ) {
        self.playback = playback
        self.onNowPlaying = onNowPlaying
        self.onQueue = onQueue
    }

    func start() {
        guard !started else { return }
        started = true
        arm()
        emit(force: true)
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playback.isPlaying else { return }
                self.emit(force: true)
            }
        }
    }

    func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        started = false
    }

    func currentNowPlaying() -> NowPlayingSnapshot {
        makeNowPlaying()
    }

    func currentQueue() -> QueueSnapshot {
        makeQueue()
    }

    private func arm() {
        withObservationTracking {
            _ = playback.currentTrack?.cataloguePath
            _ = playback.playbackState
            _ = playback.currentTime
            _ = playback.duration
            _ = playback.queueIndex
            _ = playback.queue.count
            _ = playback.queueSourceName
            _ = playback.repeatMode
            _ = playback.isShuffled
            _ = playback.activeFormatLabel
            _ = playback.pathLabel
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.arm()
                self.emit(force: false)
            }
        }
    }

    private func emit(force: Bool) {
        generation &+= 1
        let nowPlaying = makeNowPlaying()
        if force
            || lastNowPlaying == nil
            || !(lastNowPlaying?.equalsIgnoringPosition(nowPlaying) ?? false)
        {
            lastNowPlaying = nowPlaying
            onNowPlaying(nowPlaying)
        } else if force {
            onNowPlaying(nowPlaying)
        }

        let queue = makeQueue()
        let signature = queue.tracks.map(\.cataloguePath).joined(separator: "\n")
            + "|\(queue.index)|\(queue.sourceKind)|\(queue.sourceName ?? "")"
        if force || signature != lastQueueSignature {
            lastQueueSignature = signature
            onQueue(queue)
        }
    }

    private func makeNowPlaying() -> NowPlayingSnapshot {
        let state: String = {
            switch playback.playbackState {
            case .idle: "idle"
            case .loading: "loading"
            case .playing: "playing"
            case .paused: "paused"
            case .failed(let message): "failed:\(message)"
            }
        }()
        return NowPlayingSnapshot(
            generation: generation,
            track: playback.currentTrack.map(TrackDTO.init(track:)),
            state: state,
            position: playback.currentTime,
            duration: playback.duration,
            positionTimestamp: Date(),
            rate: playback.isPlaying ? 1 : 0,
            queueIndex: playback.queueIndex,
            queueCount: playback.queue.count,
            queueSourceKind: playback.queueSourceKind,
            queueSourceName: playback.queueSourceName,
            repeatMode: playback.repeatMode.rawValue,
            isShuffled: playback.isShuffled,
            activeFormatLabel: playback.activeFormatLabel,
            pathLabel: playback.pathLabel
        )
    }

    private func makeQueue() -> QueueSnapshot {
        QueueSnapshot(
            generation: generation,
            index: playback.queueIndex,
            tracks: playback.queue.map(TrackDTO.init(track:)),
            sourceKind: playback.queueSourceKind,
            sourceName: playback.queueSourceName
        )
    }
}

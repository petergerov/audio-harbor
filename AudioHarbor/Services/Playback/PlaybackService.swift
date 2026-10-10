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
    /// Where the active queue came from (playlist, album, folder…); `nil` for a loose queue.
    private(set) var queueSource: QueueSource?
    var queueSourceName: String? { queueSource?.name }
    /// Short label for the context rail header (e.g. "Playlist", "Album").
    var queueSourceKind: String { queueSource?.kindLabel ?? "Queue" }
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
            UserDefaults.standard.set(outputMode.rawValue, forKey: DefaultsKey.outputMode)
            let wasPlayingAs = effectiveMode(for: oldValue)
            guard pathChanges(from: wasPlayingAs, to: effectiveOutputMode) else {
                engine.setOutputMode(outputMode)
                return
            }
            // Move the current track over now instead of from the next one on.
            reloadCurrentTrack { engine.setOutputMode(outputMode) }
        }
    }

    /// Gain on DSD converted to PCM; takes effect within the playing track.
    var dsdPCMLevel: DSDPCMLevel = .default {
        didSet {
            guard dsdPCMLevel != oldValue else { return }
            UserDefaults.standard.set(dsdPCMLevel.rawValue, forKey: DefaultsKey.dsdPCMLevel)
            DSDConversion.gain = dsdPCMLevel.linearGain
        }
    }

    /// Network (UPnP): Full vs Wi‑Fi (DSD/SACD → CD-rate PCM; other formats untouched).
    var networkStreamQuality: NetworkStreamQuality = .full {
        didSet {
            guard networkStreamQuality != oldValue else { return }
            UserDefaults.standard.set(networkStreamQuality.rawValue, forKey: DefaultsKey.networkStreamQuality)
            engine.setNetworkStreamQuality(networkStreamQuality)
            reloadNetworkTrackIfNeeded()
        }
    }

    /// Per-player DSD mode for network output (Auto / PCM / DoP).
    var networkDsdMode: NetworkDsdMode = .pcm {
        didSet {
            guard networkDsdMode != oldValue else { return }
            engine.setNetworkDsdMode(networkDsdMode)
            if let uid = outputDeviceUID, uid.hasPrefix("upnp:") {
                storeDsdMode(networkDsdMode, for: uid)
            }
            reloadNetworkTrackIfNeeded()
        }
    }

    /// Settings radios for a network player (Wi‑Fi friendly / Full / DSD, SACD, DoP).
    var networkOutputChoice: NetworkOutputChoice {
        get { NetworkOutputChoice.from(quality: networkStreamQuality, dsd: networkDsdMode) }
        set { selectNetworkOutputChoice(newValue) }
    }

    /// What the picked network player lists for DSD (nil when not a network pick).
    private(set) var networkPlayerFormats: NetworkPlayerFormats?

    /// Skips track reload while applying stream + DSD together from one radio tap.
    private var suppressNetworkReload = false

    var repeatMode: RepeatMode = .off {
        didSet {
            guard repeatMode != oldValue else { return }
            UserDefaults.standard.set(repeatMode.rawValue, forKey: DefaultsKey.repeatMode)
        }
    }

    var isShuffled: Bool = false {
        didSet {
            guard isShuffled != oldValue else { return }
            UserDefaults.standard.set(isShuffled, forKey: DefaultsKey.shuffle)
            // Keep the current track on the deck, redraw everything after it.
            rebuildPlayOrder(anchoredTo: queueIndex)
        }
    }

    /// The picked output by Core Audio UID; nil follows the system output. Changing it moves
    /// the current track over at the same position.
    var outputDeviceUID: String? {
        didSet {
            guard outputDeviceUID != oldValue else { return }
            UserDefaults.standard.set(outputDeviceUID, forKey: DefaultsKey.outputDevice)
            rememberOutputDeviceName()
            applyStoredDsdMode(for: outputDeviceUID)
            refreshNetworkFormats()
            moveToOutputDevice()
        }
    }

    /// Name of the picked output, kept so it can be shown while the device is unplugged.
    private(set) var outputDeviceName: String?

    /// The outputs on this Mac and what the active one can do. Empty on iOS.
    private(set) var outputStatus = OutputStatus()

    /// Core Audio status before network renderers are merged in.
    private var localOutputStatus = OutputStatus()
    /// Live UPnP renderers (`upnp:<UDN>`), published by `SSDPBrowser` on macOS.
    private var networkOutputs: [OutputDevice] = []

    /// Hardware volume (0…1) of the output playback goes to — the DAC, or the Mac's own output.
    /// Nil when that output has no volume control (a fixed-level DAC).
    private(set) var outputVolume: Double?

    /// The picked output is not plugged in, so playback goes to the system output.
    var isOutputDeviceMissing: Bool {
        guard let outputDeviceUID else { return false }
        return !outputStatus.devices.contains { $0.uid == outputDeviceUID }
    }

    /// Whether the stored pick is a network renderer (even if it is offline right now).
    var isNetworkOutputSelected: Bool {
        outputDeviceUID?.hasPrefix("upnp:") == true
    }

    /// Merges live UPnP renderers into the output list. Local Core Audio devices stay as they are.
    func setNetworkOutputs(_ devices: [OutputDevice]) {
        networkOutputs = devices
        publishOutputStatus()
        refreshNetworkFormats()
    }

    /// Re-reads GetProtocolInfo for the picked network player (Settings gates the DSD radio on it).
    func refreshNetworkFormats() {
        guard let uid = outputDeviceUID, uid.hasPrefix("upnp:") else {
            networkPlayerFormats = nil
            return
        }
        Task {
            let formats = await engine.networkPlayerFormats(uid: uid)
            guard outputDeviceUID == uid else { return }
            networkPlayerFormats = formats
            // DSD radio needs a player that lists DSD — fall back to Full if this one does not.
            if networkOutputChoice == .dsd, let formats, formats.online, !formats.supportsNativeDSD {
                networkOutputChoice = .full
            }
        }
    }

    /// What actually plays: the stored choice where the output can take it, else the next step
    /// down (DoP → Exclusive → Shared). `outputMode` keeps the choice, so it comes back when a
    /// capable DAC is the output again.
    var effectiveOutputMode: OutputMode {
        effectiveMode(for: outputMode)
    }

    private func effectiveMode(for mode: OutputMode) -> OutputMode {
        switch mode {
        case .dop where outputStatus.canDoP: .dop
        case .dop, .exclusive: outputStatus.canExclusive ? .exclusive : .shared
        case .shared: .shared
        }
    }

    func isAvailable(_ mode: OutputMode) -> Bool {
        switch mode {
        case .shared: true
        case .exclusive: outputStatus.canExclusive
        case .dop: outputStatus.canDoP
        }
    }

    var state: PlaybackState { playbackState }
    /// The trial has ended without an unlock — play requests open the unlock sheet instead.
    var requiresUnlock: Bool { !license.canPlay }
    var isPlaying: Bool { playbackState == .playing }

    private var syncTimer: Timer?
    /// Guards against two loads overlapping — the later one wins.
    private var loadGeneration: UInt64 = 0
    /// Indices into `queue`, in the order they play — the natural order, or a shuffled draw.
    private var playOrder: [Int] = []
    private var orderPosition: Int = 0


    init(engine: any PlaybackEngine, license: LicenseService) {
        self.engine = engine
        self.license = license
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.outputMode),
           let mode = OutputMode(rawValue: raw) {
            outputMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.repeatMode),
           let mode = RepeatMode(rawValue: raw) {
            repeatMode = mode
        }
        isShuffled = UserDefaults.standard.bool(forKey: DefaultsKey.shuffle)
        if UserDefaults.standard.object(forKey: DefaultsKey.dsdPCMLevel) != nil,
           let level = DSDPCMLevel(rawValue: UserDefaults.standard.integer(forKey: DefaultsKey.dsdPCMLevel)) {
            dsdPCMLevel = level
        }
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.networkStreamQuality),
           let quality = NetworkStreamQuality(rawValue: raw) {
            networkStreamQuality = quality
        }
        DSDConversion.gain = dsdPCMLevel.linearGain
        engine.setOutputMode(outputMode)
        engine.setNetworkStreamQuality(networkStreamQuality)
        // Assigned in init, so didSet does not run — hand the engine the pick directly.
        outputDeviceName = UserDefaults.standard.string(forKey: DefaultsKey.outputDeviceName)
        outputDeviceUID = UserDefaults.standard.string(forKey: DefaultsKey.outputDevice)
        applyStoredDsdMode(for: outputDeviceUID)
        engine.setNetworkDsdMode(networkDsdMode)
        engine.setOutputDevice(uid: outputDeviceUID)
        refreshNetworkFormats()
        engine.setOutputStatusHandler { [weak self] status in
            self?.localOutputStatus = status
            self?.publishOutputStatus()
        }
        engine.setTrackEndedHandler { [weak self] endedTrack in
            self?.advanceAfterTrackEnd(after: endedTrack)
        }
        engine.setOutputVolumeHandler { [weak self] level in
            guard let self, self.outputVolume != level else { return }
            self.outputVolume = level
        }
        syncFromEngine()
    }

    func setOutputVolume(_ level: Double) {
        guard level.isFinite, outputVolume != nil else { return }
        engine.setOutputVolume(min(1, max(0, level)))
    }

    func play(track: Track, in queueTracks: [Track]? = nil, from source: QueueSource? = nil) {
        guard allowPlayback() else { return }

        if let queueTracks {
            queue = queueTracks
            queueIndex = queueTracks.firstIndex(of: track) ?? 0
        } else {
            queue = [track]
            queueIndex = 0
        }
        rebuildPlayOrder(anchoredTo: queueIndex)

        if let source, !source.name.isEmpty {
            queueSource = source
        } else if queueTracks != nil, !track.album.isEmpty {
            queueSource = .album(track.album)
        } else {
            queueSource = nil
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
            // A failed load or start leaves the engine empty — load the track again
            // instead of playing nothing ("Could not read the audio file").
            if queueEnded || engineIsEmpty {
                Task { await loadAndPlay(track) }
                return
            }
            engine.play()
            syncFromEngine()
            startSyncing()
        }
    }

    private var engineIsEmpty: Bool {
        switch engine.state {
        case .idle, .failed: true
        case .loading, .playing, .paused: false
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
        let next = queue[index]
        // Gapless: the network engine already promoted SetNext — take it without reloading.
        if let adopted = engine.adoptPreparedNext(), adopted.id == next.id {
            currentTrack = next
            syncFromEngine()
            startSyncing()
            Task { await prepareFollowingTrack() }
            return
        }
        Task { await loadAndPlay(next) }
    }

    /// Arms SetNextAVTransportURI for the track after the current one (network output only).
    private func prepareFollowingTrack() async {
        guard let peek = peekNextIndex() else {
            await engine.prepareNext(nil)
            return
        }
        await engine.prepareNext(queue[peek])
    }

    private func peekNextIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if playOrder.count != queue.count {
            return nil
        }
        let next = orderPosition + 1
        if next < playOrder.count {
            return playOrder[next]
        }
        if repeatMode == .all {
            return playOrder.first
        }
        return nil
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

    /// Core Audio devices plus live network renderers. When a network pick is online it is the
    /// active output (Exclusive / DoP off — those need a local DAC).
    private func publishOutputStatus() {
        var devices = localOutputStatus.devices
        devices.append(contentsOf: networkOutputs)
        // Capabilities / footnotes follow the Device menu pick, not a leftover hog or system default.
        var active = localOutputStatus.activeUID
        if let uid = outputDeviceUID {
            if uid.hasPrefix("upnp:"), networkOutputs.contains(where: { $0.uid == uid }) {
                active = uid
            } else if devices.contains(where: { $0.uid == uid }) {
                active = uid
            }
        }
        outputStatus = OutputStatus(devices: devices, activeUID: active)
        rememberOutputDeviceName()
    }

    /// Keeps the last known name of the picked output; an unplugged device keeps its old one.
    private func rememberOutputDeviceName() {
        let name: String?
        if let outputDeviceUID {
            guard let device = outputStatus.devices.first(where: { $0.uid == outputDeviceUID }) else { return }
            name = device.name
        } else {
            name = nil
        }
        guard name != outputDeviceName else { return }
        outputDeviceName = name
        UserDefaults.standard.set(name, forKey: DefaultsKey.outputDeviceName)
    }

    /// Whether the current track sounds different on the new path. Exclusive and DoP only
    /// differ for DSD — a PCM track keeps playing untouched.
    private func pathChanges(from old: OutputMode, to new: OutputMode) -> Bool {
        guard old != new else { return false }
        if old != .shared, new != .shared {
            return currentTrack?.format.isDSD == true
        }
        return true
    }

    private func moveToOutputDevice() {
        reloadCurrentTrack { engine.setOutputDevice(uid: outputDeviceUID) }
    }

    /// Applies an output change and reloads the current track so it takes the new path,
    /// at the same position and in the same play/pause state.
    private func reloadCurrentTrack(applying change: () -> Void) {
        let hadTrack = !engineIsEmpty
        let resume = isPlaying
        let position = engine.currentTime
        change()
        guard hadTrack, let track = currentTrack else {
            syncFromEngine()
            return
        }
        Task { await loadAndPlay(track, at: position, autoplay: resume) }
    }

    private func loadAndPlay(_ track: Track, at position: TimeInterval = 0, autoplay: Bool = true) async {
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
            if autoplay {
                engine.play()
                if position > 0 { engine.seek(to: position) }
                syncFromEngine()
                startSyncing()
            } else {
                if position > 0 { engine.seek(to: position) }
                syncFromEngine()
            }
            await prepareFollowingTrack()
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

    // MARK: - Network output choice

    private func selectNetworkOutputChoice(_ choice: NetworkOutputChoice) {
        let quality = choice.streamQuality
        let dsd = choice.dsdMode
        guard quality != networkStreamQuality || dsd != networkDsdMode else { return }
        suppressNetworkReload = true
        networkStreamQuality = quality
        networkDsdMode = dsd
        suppressNetworkReload = false
        reloadNetworkTrackIfNeeded()
    }

    private func reloadNetworkTrackIfNeeded() {
        guard !suppressNetworkReload, isNetworkOutputSelected, currentTrack != nil else { return }
        reloadCurrentTrack { engine.setOutputDevice(uid: outputDeviceUID) }
    }

    private func applyStoredDsdMode(for uid: String?) {
        let mode = storedDsdMode(for: uid) ?? .pcm
        guard mode != networkDsdMode else {
            engine.setNetworkDsdMode(mode)
            return
        }
        suppressNetworkReload = true
        networkDsdMode = mode
        suppressNetworkReload = false
    }

    private func storedDsdMode(for uid: String?) -> NetworkDsdMode? {
        guard let uid, uid.hasPrefix("upnp:") else { return nil }
        let map = UserDefaults.standard.dictionary(forKey: DefaultsKey.networkDsdModes) as? [String: String] ?? [:]
        guard let raw = map[uid] else { return nil }
        return NetworkDsdMode(rawValue: raw)
    }

    private func storeDsdMode(_ mode: NetworkDsdMode, for uid: String) {
        var map = UserDefaults.standard.dictionary(forKey: DefaultsKey.networkDsdModes) as? [String: String] ?? [:]
        if mode == .pcm {
            map.removeValue(forKey: uid)
        } else {
            map[uid] = mode.rawValue
        }
        UserDefaults.standard.set(map, forKey: DefaultsKey.networkDsdModes)
    }
}

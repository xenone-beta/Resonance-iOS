import AVFoundation
import MediaPlayer
import SwiftUI

enum RepeatMode { case off, all, one }

/// Position of the current song, published apart from the player so only the seek bar redraws often.
final class PlaybackClock: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
}

struct EQPreset: Identifiable {
    let id: String
    let gains: [Float]
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let all: [EQPreset] = [
        EQPreset(id: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(id: "Bass boost", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        EQPreset(id: "Treble boost", gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        EQPreset(id: "Vocal", gains: [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
        EQPreset(id: "Rock", gains: [5, 4, 2, -1, -2, -1, 2, 4, 5, 5]),
        EQPreset(id: "Electronic", gains: [5, 4, 1, 0, -2, 2, 1, 2, 4, 5]),
    ]
}

/// Plays the queue through AVAudioEngine: player node → equalizer → time/pitch → mixer.
@MainActor
final class PlayerModel: ObservableObject {
    // Queue, in play order. [original] is the order before shuffling.
    @Published private(set) var items: [Track] = []
    @Published private(set) var position = -1
    @Published private(set) var isPlaying = false
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var previousTrack: Track?
    @Published private(set) var nextTrack: Track?
    @Published private(set) var sleepEndsAt: Date?
    @Published private(set) var cover: UIImage?
    @Published private(set) var coverSeed: UInt32?

    @Published var speed: Float = 1 {
        didSet { timePitch.rate = speed; updateNowPlayingRate() }
    }
    @Published var pitchSemitones = 0 {
        didSet { timePitch.pitch = Float(pitchSemitones) * 100 }
    }
    @Published var eqGains = [Float](repeating: 0, count: 10) {
        didSet { applyEQ() }
    }

    let clock = PlaybackClock()
    let spectrum = SpectrumModel()
    var library: Library?

    var current: Track? { items.indices.contains(position) ? items[position] : nil }

    private var original: [Track] = []
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 10)
    private let timePitch = AVAudioUnitTimePitch()
    private var graphFormat: AVAudioFormat?
    private var file: AVAudioFile?
    private var startOffset: Double = 0
    private var generation = 0
    private var timer: Timer?
    private var sleepTask: Task<Void, Never>?
    private var coverTask: Task<Void, Never>?

    init() {
        engine.attach(playerNode)
        engine.attach(eq)
        engine.attach(timePitch)
        for (i, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = EQPreset.frequencies[i]
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
        spectrum.attach(to: engine.mainMixerNode)
        configureSession()
        configureRemoteCommands()
        observeSystemEvents()
    }

    // MARK: Queue control

    /// Replaces the queue and starts [tracks][start].
    func play(_ tracks: [Track], start: Int = 0, shuffled: Bool? = nil) {
        guard tracks.indices.contains(start) else { return }
        if let shuffled { shuffle = shuffled }
        original = tracks
        if shuffle {
            let first = tracks[start]
            var rest = tracks
            rest.remove(at: start)
            items = [first] + rest.shuffled()
            position = 0
        } else {
            items = tracks
            position = start
        }
        load(at: position, autoplay: true)
    }

    func playNext(_ track: Track) {
        guard current != nil else { return play([track]) }
        items.insert(track, at: position + 1)
        if let i = original.firstIndex(where: { $0.id == current?.id }) { original.insert(track, at: i + 1) }
        refreshNeighbors()
    }

    func addToQueue(_ tracks: [Track]) {
        guard current != nil else { return play(tracks) }
        items.append(contentsOf: tracks)
        original.append(contentsOf: tracks)
        refreshNeighbors()
    }

    func removeFromQueue(at index: Int) {
        guard items.indices.contains(index), index != position else { return }
        let removed = items.remove(at: index)
        if index < position { position -= 1 }
        if let i = original.firstIndex(where: { $0.id == removed.id }) { original.remove(at: i) }
        refreshNeighbors()
    }

    func jump(to index: Int) {
        guard items.indices.contains(index) else { return }
        position = index
        load(at: index, autoplay: true)
    }

    func setShuffle(_ on: Bool) {
        shuffle = on
        guard let now = current else { return }
        if on {
            var rest = items
            rest.remove(at: position)
            items = [now] + rest.shuffled()
            position = 0
        } else {
            let ids = Set(items.map { $0.id })
            items = original.filter { ids.contains($0.id) }
            position = items.firstIndex(where: { $0.id == now.id }) ?? 0
        }
        refreshNeighbors()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        refreshNeighbors()
    }

    func stopAndClear() {
        generation += 1
        playerNode.stop()
        engine.stop()
        items = []; original = []; position = -1; file = nil
        isPlaying = false
        stopTimer()
        clock.position = 0; clock.duration = 0
        cover = nil; coverSeed = nil
        refreshNeighbors()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Transport

    func togglePlay() { isPlaying ? pause() : resume() }

    func resume() {
        guard current != nil else { return }
        if file == nil { load(at: position, autoplay: true); return }
        do {
            if !engine.isRunning { try engine.start() }
            playerNode.play()
            isPlaying = true
            spectrum.active = true
            startTimer()
            updateNowPlayingRate()
        } catch {
            isPlaying = false
        }
    }

    func pause() {
        guard isPlaying else { return }
        clock.position = currentPosition()
        playerNode.pause()
        isPlaying = false
        spectrum.active = false
        spectrum.calm()
        stopTimer()
        updateNowPlayingRate()
    }

    func next() {
        if position + 1 < items.count {
            jump(to: position + 1)
        } else if repeatMode != .off, !items.isEmpty {
            jump(to: 0)
        } else {
            // End of the queue: stay on the last song, stopped at its start.
            seek(to: 0)
            pause()
        }
    }

    /// Back to the start of the song, or to the previous one when already near the start.
    func previous() {
        if currentPosition() > 3 || (position == 0 && repeatMode == .off) {
            seek(to: 0)
        } else {
            goToPreviousTrack()
        }
    }

    func goToPreviousTrack() {
        if position > 0 { jump(to: position - 1) }
        else if repeatMode != .off, items.count > 1 { jump(to: items.count - 1) }
        else { seek(to: 0) }
    }

    func seek(to seconds: Double) {
        guard file != nil else { return }
        let target = max(0, min(seconds, clock.duration))
        let wasPlaying = isPlaying
        schedule(from: target)
        clock.position = target
        if wasPlaying { playerNode.play() }
        updateNowPlayingRate()
    }

    func skip(by seconds: Double) { seek(to: currentPosition() + seconds) }

    // MARK: Sleep timer

    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        guard let minutes else { sleepEndsAt = nil; return }
        sleepEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.pause()
            self?.sleepEndsAt = nil
        }
    }

    // MARK: Loading

    private func load(at index: Int, autoplay: Bool) {
        guard items.indices.contains(index) else { return }
        position = index
        let track = items[index]
        do {
            let opened = try AVAudioFile(forReading: track.url)
            file = opened
            clock.duration = Double(opened.length) / opened.processingFormat.sampleRate
            configureGraph(format: opened.processingFormat)
            schedule(from: 0)
            clock.position = 0
            if autoplay { resume() }
        } catch {
            // Unreadable file: skip to the next song instead of getting stuck.
            file = nil
            isPlaying = false
            if autoplay, index + 1 < items.count { load(at: index + 1, autoplay: true) }
            return
        }
        refreshNeighbors()
        loadCover(for: track)
        updateNowPlaying(track)
    }

    private func configureGraph(format: AVAudioFormat) {
        if let last = graphFormat, last == format { return }
        engine.stop()
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(timePitch)
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        graphFormat = format
        engine.prepare()
    }

    private func schedule(from seconds: Double) {
        guard let file else { return }
        generation += 1
        let mine = generation
        playerNode.stop()
        let rate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, min(seconds, clock.duration)) * rate)
        let frames = AVAudioFrameCount(max(0, file.length - startFrame))
        startOffset = Double(startFrame) / rate
        guard frames > 0 else {
            Task { @MainActor [weak self] in self?.trackEnded(generation: mine) }
            return
        }
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.trackEnded(generation: mine) }
        }
    }

    private func trackEnded(generation ended: Int) {
        guard ended == generation, isPlaying else { return }
        if repeatMode == .one {
            seek(to: 0)
            playerNode.play()
        } else {
            next()
        }
    }

    private func currentPosition() -> Double {
        guard isPlaying,
              let render = playerNode.lastRenderTime,
              let played = playerNode.playerTime(forNodeTime: render) else { return clock.position }
        return min(clock.duration, startOffset + Double(played.sampleTime) / played.sampleRate)
    }

    private func refreshNeighbors() {
        let count = items.count
        guard count > 0, items.indices.contains(position) else {
            previousTrack = nil; nextTrack = nil
            return
        }
        let wrap = repeatMode != .off && count > 1
        previousTrack = position > 0 ? items[position - 1] : (wrap ? items[count - 1] : nil)
        nextTrack = position + 1 < count ? items[position + 1] : (wrap ? items[0] : nil)
    }

    private func applyEQ() {
        for (i, band) in eq.bands.enumerated() where i < eqGains.count {
            band.gain = max(-12, min(12, eqGains[i]))
        }
    }

    // MARK: Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isPlaying else { return }
        clock.position = currentPosition()
    }

    // MARK: Cover

    private func loadCover(for track: Track) {
        coverTask?.cancel()
        coverTask = Task { [weak self] in
            guard let self, let library = self.library else { return }
            let image = await library.cover(for: track)
            guard !Task.isCancelled, self.current?.id == track.id else { return }
            self.cover = image
            self.coverSeed = image.flatMap { SeedColor.from($0) }
            self.updateNowPlaying(track)
        }
    }

    // MARK: System integration

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let kind = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0) }
            Task { @MainActor in
                if kind == .began { self?.pause() }
                else if options?.contains(.shouldResume) == true { self?.resume() }
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.pause() } // headphones unplugged
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.recoverEngine() }
        }
    }

    /// The audio route changed and the engine stopped: restart it at the same place.
    private func recoverEngine() {
        guard file != nil else { return }
        let wasPlaying = isPlaying
        let place = clock.position
        isPlaying = false
        schedule(from: place)
        clock.position = place
        if wasPlaying { resume() }
    }

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlay() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in self?.seek(to: time) }
            return .success
        }
    }

    private func updateNowPlaying(_ track: Track) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: clock.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(speed) : 0.0,
        ]
        if let image = cover, current?.id == track.id {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingRate() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clock.position
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(speed) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

import AVFoundation
import Foundation
import OSLog

@Observable
final class PlayerCenter {
    static let shared = PlayerCenter()

    private(set) var tracks: [PlayableTrack] = []
    private(set) var index: Int = 0
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let node = AVAudioPlayerNode()
        @ObservationIgnored let analysis = AudioSpectrumAnalyzer()
        @ObservationIgnored private let pipelineQueue = DispatchQueue(label: "com.lhy.lyricglow.pipeline")

        private struct Pipe {
        var file: AVAudioFile?
        var sr: Double = 0
        var startSeconds: Double = 0
        var pausedSeconds: Double = 0
        var trackDuration: Double = 0
        var chunksScheduled = 0
        var atEOF = false
        var generation = 0
        var nodeSR: Double = 0
        var nodeChannels: UInt32 = 0
    }
    @ObservationIgnored private var pipe = Pipe()
    @ObservationIgnored private let stateLock = NSLock()
    @ObservationIgnored private var tickTimer: Timer?

    var currentTrack: PlayableTrack? {
        tracks.indices.contains(index) ? tracks[index] : nil
    }

                var lyricOffset: Double {
        get {
            let key = offsetKey()
            return UserDefaults.standard.object(forKey: key) as? Double ?? 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: offsetKey())
        }
    }

    private func offsetKey() -> String {
                "lyricOffset.\(currentTrack?.id.uuidString ?? "global")"
    }

        var lyricClock: Double {
        max(0, liveTime + lyricOffset)
    }

            var liveTime: Double {
        let s = snapshot()
        guard s.sr > 0 else { return s.pausedSeconds }
        if node.isPlaying,
           let nodeTime = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: nodeTime), playerTime.sampleRate > 0 {
            let t = Double(playerTime.sampleTime) / Double(playerTime.sampleRate) + s.startSeconds
            return min(max(t, 0), s.trackDuration)
        }
        return s.pausedSeconds
    }

    private func snapshot() -> Pipe {
        stateLock.lock(); defer { stateLock.unlock() }
        return pipe
    }
    private func mutatePipe(_ body: (inout Pipe) -> Void) {
        stateLock.lock(); body(&pipe); stateLock.unlock()
    }

    private init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: nil)
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in PlayerCenter.shared.handleTick() }
        }
    }

        func play(_ newTracks: [PlayableTrack], at startIndex: Int) {
        guard newTracks.indices.contains(startIndex) else { return }
        tracks = newTracks
        index = startIndex
        currentTime = 0
        startEngineIfNeeded()
        duration = tracks[startIndex].duration ?? 0
        pipelineQueue.async { [weak self] in
            self?.loadOnPipeline(tracks: newTracks, index: startIndex, startSeconds: 0, play: true)
        }
        isPlaying = true
        syncNowPlaying()
    }

        func refreshTrack(id: UUID, title: String, artist: String, album: String, artworkData: Data?) {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[idx].title = title
        tracks[idx].artist = artist
        tracks[idx].album = album
        tracks[idx].artworkData = artworkData
        syncNowPlaying()
    }

    func playPause() {
        guard currentTrack != nil else { return }
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        guard currentTrack != nil else { return }
        let t = liveTime
        mutatePipe { $0.pausedSeconds = t }
        node.pause()
        isPlaying = false
        syncNowPlaying()
    }

    private func resume() {
        guard currentTrack != nil else { return }
        startEngineIfNeeded()
        let s = snapshot()
                if s.sr > 0, s.atEOF, s.chunksScheduled == 0 {
            switchTo(index)
            return
        }
        pipelineQueue.async { [weak self] in
            guard let self else { return }
            let s = self.snapshot()
                        if s.sr > 0, s.file != nil, s.chunksScheduled == 0, !s.atEOF {
                self.pump()
            }
            if !self.node.isPlaying { self.node.play() }
        }
        isPlaying = true
        syncNowPlaying()
    }

            func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        let wasPlaying = isPlaying
        let currentTracks = tracks
        let currentIdx = index
        mutatePipe {
            $0.pausedSeconds = target
            $0.generation += 1
        }
        Self.logSeek.info("SEEK target=\(target, format: .fixed(precision: 3)) playing=\(wasPlaying)")
        startEngineIfNeeded()
        pipelineQueue.async { [weak self] in
            self?.loadOnPipeline(tracks: currentTracks, index: currentIdx,
                                 startSeconds: target, play: wasPlaying)
        }
        currentTime = target
        syncNowPlaying()
    }

    func next() {
        guard index + 1 < tracks.count else { return }
        switchTo(index + 1)
    }

    func previous() {
        guard index > 0 else { return }
        switchTo(index - 1)
    }

    private func switchTo(_ newIndex: Int) {
        index = newIndex
        currentTime = 0
        startEngineIfNeeded()
        duration = tracks[newIndex].duration ?? 0
        let currentTracks = tracks
        pipelineQueue.async { [weak self] in
            self?.loadOnPipeline(tracks: currentTracks, index: newIndex, startSeconds: 0, play: true)
        }
        isPlaying = true
        syncNowPlaying()
    }

        private func loadOnPipeline(tracks: [PlayableTrack], index: Int, startSeconds: Double, play: Bool) {
        node.stop()
        guard tracks.indices.contains(index) else { return }
        let track = tracks[index]

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: track.audioURL)
        } catch {
            Self.logSeek.error("OPEN FAILED \(track.title, privacy: .public): \(String(describing: error), privacy: .public)")
            Task { @MainActor in PlayerCenter.shared.skipBrokenTrack() }
            return
        }

        let gen = snapshot().generation
        let sr = file.processingFormat.sampleRate
        let channels = file.processingFormat.channelCount
        let total = Double(file.length) / sr
        let clamped = max(0, min(startSeconds, total))
        file.framePosition = Int64(clamped * sr)
        let startSecondsExact = Double(file.framePosition) / sr

                let s0 = snapshot()
        if s0.nodeSR != sr || s0.nodeChannels != channels {
            engine.disconnectNodeOutput(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        }

        mutatePipe {
            $0.file = file
            $0.sr = sr
            $0.startSeconds = startSecondsExact
            $0.pausedSeconds = startSecondsExact
            $0.trackDuration = total
            $0.chunksScheduled = 0
            $0.atEOF = false
            $0.nodeSR = sr
            $0.nodeChannels = channels
        }
        Task { @MainActor in
            PlayerCenter.shared.duration = total
        }
        Self.logSeek.info("LOAD gen=\(gen) track=\(track.title, privacy: .public) start=\(startSecondsExact, format: .fixed(precision: 3)) total=\(total, format: .fixed(precision: 3))")

        if play {
            pump()
            node.play()
        }
    }

        private func pump() {
        while true {
            let s = snapshot()
            guard s.chunksScheduled < 3, !s.atEOF, let file = s.file, s.sr > 0 else { return }
            guard let buf = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(65536)) else { return }
            do {
                try file.read(into: buf)
            } catch {
                mutatePipe { $0.atEOF = true }
                return
            }
            if buf.frameLength == 0 {
                mutatePipe { $0.atEOF = true }
                return
            }
            mutatePipe { $0.chunksScheduled += 1 }
            let gen = s.generation
            node.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                self.pipelineQueue.async { self.chunkCompleted(gen: gen) }
            }
        }
    }

        private func chunkCompleted(gen: Int) {
        let s = snapshot()
        guard gen == s.generation else { return }
        mutatePipe { $0.chunksScheduled = max(0, $0.chunksScheduled - 1) }
        let s2 = snapshot()
        if s2.atEOF && s2.chunksScheduled == 0 {
            Task { @MainActor in PlayerCenter.shared.handleTrackFinished() }
        } else {
            pump()
        }
    }

    @MainActor
    private func handleTrackFinished() {
        if index + 1 < tracks.count {
            next()
        } else {
            isPlaying = false
            let s = snapshot()
            currentTime = s.trackDuration
            mutatePipe { $0.pausedSeconds = $0.trackDuration }
            NowPlayingCoordinator.shared.updateElapsed(currentTime, duration: duration, playing: false)
        }
    }

    @MainActor
    private func skipBrokenTrack() {
        guard let failed = currentTrack, let failedIndex = tracks.firstIndex(where: { $0.id == failed.id })
        else { return }
        tracks.remove(at: failedIndex)
        if tracks.isEmpty {
            pipelineQueue.async { [weak self] in self?.node.stop() }
            mutatePipe {
                $0.file = nil; $0.sr = 0; $0.chunksScheduled = 0; $0.atEOF = false
                $0.pausedSeconds = 0; $0.trackDuration = 0; $0.generation += 1
            }
            index = 0
            isPlaying = false
            currentTime = 0
            duration = 0
        } else {
            switchTo(min(failedIndex, tracks.count - 1))
        }
        syncNowPlaying()
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
            analysis.attach(engine: engine)
        } catch {
            Self.logSeek.error("ENGINE START FAILED: \(String(describing: error), privacy: .public)")
        }
    }

    private func handleTick() {
        let t = liveTime
        currentTime = t.isFinite ? t : 0
        NowPlayingCoordinator.shared.updateElapsed(currentTime, duration: duration, playing: isPlaying)
    }

    private func syncNowPlaying() {
        NowPlayingCoordinator.shared.update(
            track: currentTrack,
            duration: duration,
            elapsed: min(currentTime, duration),
            playing: isPlaying
        )
    }

    private static let logSeek = Logger(subsystem: "com.lhy.lyricglow", category: "seek")
}

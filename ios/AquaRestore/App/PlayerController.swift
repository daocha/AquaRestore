import AVFoundation
import Combine
import SwiftUI

/// The preview player: the original video, graded live by the GPU compositor, so no re-encode is needed.
/// Slider changes only update the shared `GradeState`; the player and decoder are never rebuilt.
@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    /// Kept out of the model so playback ticks redraw only the trim bar and time labels.
    @Published private(set) var playhead: Int64 = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var durationMs: Int64 = 0
    /// The rate playback runs at, which follows the speed chosen in the clip controls.
    @Published private(set) var rate: Float = 1
    /// The source's display aspect ratio, which the player view keeps (its controls cover only the video).
    @Published private(set) var aspect: CGFloat?

    private unowned let model: EditorModel
    private var item: AVPlayerItem?
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    /// What is playing, so that a preview given up for an export can come back.
    private var loaded: (media: SourceMedia, gradeEdge: Int)?
    /// The preview has given up its memory until the export and its comparison end.
    private var released = false
    private var retry = PlaybackRetry()
    private var observers: [AnyCancellable] = []
    private var itemObservers: [AnyCancellable] = []
    private var originalBoost = GainBox()
    private var musicBoost = GainBox()
    private var originalAudio: AVAssetTrack?
    private var musicAudio: AVAssetTrack?
    private var musicPlayer: AVPlayer?
    private var musicEnd: AnyCancellable?
    private var appActive = true
    private var exporting = false
    private var resume = false
    private var previous: MsRange = 0...0
    private var speed: Float = 1
    private var refreshing = false
    private var refreshAgain = false
    private static let previewFps: Float = 30

    init(model: EditorModel) {
        self.model = model
        AppActivity.observe()
        Self.configureAudioSession()
        let center = NotificationCenter.default
        observers = [
            center.publisher(for: Notification.Name("UIApplicationWillResignActiveNotification")).sink { [weak self] _ in self?.resignActive() },
            center.publisher(for: Notification.Name("UIApplicationDidBecomeActiveNotification")).sink { [weak self] _ in self?.becomeActive() },
            center.publisher(for: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification")).sink { [weak self] _ in
                NSLog("AquaRestore: memory warning\(AppLog.memory)")
                if self?.exporting == true { self?.releaseForExport() }
            },
            center.publisher(for: AVAudioSession.interruptionNotification).sink { note in
                NSLog("AquaRestore: audio interrupted: \(note.userInfo?[AVAudioSessionInterruptionTypeKey] ?? "unknown")")
            },
            center.publisher(for: AVAudioSession.routeChangeNotification).sink { _ in
                NSLog("AquaRestore: audio route: \(AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName))")
            },
            // A reset ends the audio session and every player. The video's own failure brings the preview back; this is the rest.
            center.publisher(for: AVAudioSession.mediaServicesWereResetNotification).sink { [weak self] _ in
                NSLog("AquaRestore: media services were reset\(AppLog.memory)")
                Self.configureAudioSession()
                self?.loadMusic(self?.model.music)
            },
            model.$speed.sink { [weak self] value in self?.speed = value; self?.applyRate() },
            model.$originalVolume.sink { [weak self] value in self?.setOriginalVolume(value) },
            model.$musicVolume.sink { [weak self] value in self?.setMusicVolume(value) },
            model.$music.sink { [weak self] track in self?.loadMusic(track) },
            Publishers.CombineLatest(model.$trim, model.$trimming).sink { [weak self] range, active in self?.trimChanged(range, active) },
            Publishers.CombineLatest(model.$grade, model.$compare).dropFirst().sink { [weak self] _ in self?.refreshPausedFrame() },
            model.scrub.sink { [weak self] position, play in
                self?.seek(position)
                if play { self?.play() } else { self?.pause() }
            },
            // After the song window moves, replay from the trim start so the new section can be heard.
            model.audition.sink { [weak self] in
                guard let self else { return }
                self.loopBack(self.model.trim.lowerBound, reason: "the song section moved")
            },
            Exports.shared.$status.map { $0.busy || $0.comparisonsBusy }.removeDuplicates().sink { [weak self] busy in
                guard let self else { return }
                self.exporting = busy
                if busy {
                    self.pause()
                    if let source = self.model.source, LivePreview.previewYields(width: source.width, height: source.height,
                                                                                 hdr: source.isHdr, availableMemory: AppLog.availableMemory) {
                        self.releaseForExport()
                    }
                } else if self.released, let loaded = self.loaded {
                    self.released = false
                    self.load(loaded.media, gradeEdge: loaded.gradeEdge)
                } else if self.model.playbackWanted && self.appActive { self.play() }
            },
        ]
    }

    /// The default audio category goes silent with the Ring/Silent switch, which should not mute a video being edited.
    private static func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { NSLog("AquaRestore: audio session unavailable: \(error)") }
    }

    // MARK: Loading

    /// `gradeEdge` limits the long edge the preview is graded at; 0 grades at the video's full size.
    func load(_ media: SourceMedia, gradeEdge: Int = 0) {
        // A preview that gave up its memory for an export stays away until the export ends, then comes back as this.
        if released { loaded = (media, gradeEdge); return }
        unload()
        loaded = (media, gradeEdge)
        loopingSince = nil
        FrameProbe.reset()
        requestsSeen = model.gradeState.requests
        lastRequestAt = Date()
        loadTask = Task { [weak self] in
            do {
                let asset = AVURLAsset(url: media.url)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaProblem("playbackFailed") }
                let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
                let duration = try await asset.load(.duration)
                let audio = try await asset.loadTracks(withMediaType: .audio).first
                guard let self, !Task.isCancelled else { return }

                // The layer scales the graded frames to the view.
                let display = GradeInstruction.displaySize(natural, transform)
                let scale = gradeEdge > 0 ? min(1, CGFloat(gradeEdge) / max(display.width, display.height)) : 1
                let render = CGSize(width: max(2, (display.width * scale / 2).rounded() * 2), height: max(2, (display.height * scale / 2).rounded() * 2))
                let fps = Int32(min(max(media.fps.rounded(), 24), 60))
                let composition = GradeComposition.make(track: track, trackID: track.trackID, duration: duration, state: self.model.gradeState,
                    hdr: media.hdr, transform: transform, naturalSize: natural, renderSize: render, frameDuration: CMTime(value: 1, timescale: fps))
                let item = AVPlayerItem(asset: asset)
                item.videoComposition = composition
                item.audioTimePitchAlgorithm = .spectral
                self.originalAudio = audio
                let player = AVPlayer(playerItem: item)
                player.actionAtItemEnd = .none
                self.item = item
                self.durationMs = Int64((duration.seconds * 1000).rounded())
                self.aspect = display.width / display.height
                self.previous = self.model.trim
                self.observe(item, player)
                self.player = player
                self.setOriginalVolume(self.model.originalVolume)
                self.applyRate()
                self.startTimer()
                // The watchdog runs on its own, so a seek that never completes cannot switch it off.
                self.watchTask = Task { [weak self] in await self?.watchStart(item, media) }
                // Start only once the item is ready, from the seek's completion, rather than seeking and playing while it is
                // still preparing: with an HDR clip in the iOS Simulator that left the video waiting for ever for its first
                // frame. Readiness is polled, with a limit, so that it can never stop playback from starting.
                var polls = 0
                while item.status == .unknown && polls < 200 && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    polls += 1
                }
                guard !Task.isCancelled, self.item === item, item.status != .failed else { return }
                let start = min(max(self.model.playbackPositionMs, 0), max(self.durationMs - 1, 0))
                self.playhead = start
                player.seek(to: CMTime(value: start, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.item === item else { return }
                        if self.model.playbackWanted && !self.exporting && self.appActive { self.play() }
                    }
                }
            } catch is CancellationError {
            } catch {
                self?.model.error = "playbackFailed"
            }
        }
    }

    /// A black preview with sound leaves no error, so say what the player is doing shortly after it starts.
    private func watchStart(_ item: AVPlayerItem, _ media: SourceMedia) async {
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        guard let player, self.item === item else { return }
        NSLog("AquaRestore: playback check hdr=\(media.hdr.rawValue) rate=\(player.rate) time=\(player.currentTime().seconds)s status=\(item.status.rawValue) frame requests=\(model.gradeState.requests) error=\(String(describing: item.error))\(AppLog.memory)")
        logAudio(player, item)
        // Again once it has had time to play, since the first check can come before any sound.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if self.player === player, self.item === item { logAudio(player, item) }
        // Then every five seconds, so a preview that looks slow can be measured rather than guessed at.
        var seen = model.gradeState.requests
        var since = Date()
        while !Task.isCancelled, AppLog.enabled, self.player === player, self.item === item {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            let requests = model.gradeState.requests, now = Date()
            if player.rate != 0 {
                let shown = item.tracks.first { $0.assetTrack?.mediaType == .video }?.currentVideoFrameRate ?? 0
                let asked = Double(requests - seen) / max(now.timeIntervalSince(since), 0.001)
                NSLog("AquaRestore: preview playing at \(player.currentTime().seconds)s: shown \(String(format: "%.1f", shown)) fps, \(String(format: "%.1f", asked)) frames asked for per second, heat level \(ProcessInfo.processInfo.thermalState.rawValue)\(AppLog.memory)")
            }
            seen = requests; since = now
        }
    }

    /// What the output path looks like, for when a preview plays without sound. Above 100% volume, no deliveries means
    /// the file's audio is not reaching the pipeline, and a zero peak means it is silent there.
    private func logAudio(_ player: AVPlayer, _ item: AVPlayerItem) {
        let session = AVAudioSession.sharedInstance()
        let tracks = item.tracks.filter { $0.assetTrack?.mediaType == .audio }
        // Deliveries and peak stay at zero until the boost stage is added, at volumes above 100%.
        NSLog("AquaRestore: audio check tracks=\(tracks.count) enabled=\(tracks.filter(\.isEnabled).count) mix=\(item.audioMix != nil) " +
              "volume=\(player.volume) muted=\(player.isMuted) rate=\(player.rate) gain=\(originalBoost.gain) " +
              "deliveries=\(originalBoost.deliveries) peak=\(originalBoost.peak) " +
              "category=\(session.category.rawValue) mode=\(session.mode.rawValue) output=\(session.outputVolume) " +
              "otherAudio=\(session.isOtherAudioPlaying) route=\(session.currentRoute.outputs.map(\.portName))")
        originalBoost.peak = 0
    }

    func unload() {
        stop()
        loaded = nil
        released = false
        playhead = 0
        durationMs = 0
        aspect = nil
    }

    /// Frees the player and its decoded frames. The check that logs playback holds on to them while it waits, so it stops too.
    private func stop() {
        loadTask?.cancel(); loadTask = nil
        watchTask?.cancel(); watchTask = nil
        timer?.invalidate(); timer = nil
        itemObservers = []
        player?.pause()
        player = nil
        item = nil
        originalAudio = nil
        isPlaying = false
        updateGradeRate()
        resume = false
        musicPlayer?.pause()
    }

    /// Makes room for an export. The position, length and shape stay, so the controls do not move and playback comes back
    /// where it was; only the picture is black until then.
    private func releaseForExport() {
        guard loaded != nil, !released else { return }
        model.playbackPositionMs = playhead
        stop()
        released = true
        NSLog("AquaRestore: preview released for the export\(AppLog.memory)")
    }

    /// A failed item never plays again, even once what stopped it has passed, so the play button would do nothing from then on.
    /// During an export the preview comes back when the export ends; otherwise it is built again once before saying so.
    private func itemFailed(_ failed: AVPlayerItem) {
        guard self.item === failed, let loaded else { return }
        NSLog("AquaRestore: preview playback failed: \(String(describing: failed.error))\(AppLog.memory)")
        if exporting { releaseForExport(); return }
        guard retry.allowed() else { model.error = "playbackFailed"; return }
        model.playbackPositionMs = playhead
        load(loaded.media, gradeEdge: loaded.gradeEdge)
    }

    private func observe(_ item: AVPlayerItem, _ player: AVPlayer) {
        itemObservers = [
            item.publisher(for: \.status).sink { [weak self] status in
                if status == .readyToPlay { NSLog("AquaRestore: preview ready \(item.presentationSize) tracks=\(item.tracks.count)") }
                if status == .failed { Task { @MainActor [weak self] in self?.itemFailed(item) } }
            },
            // The loop stays inside the trim range; ending the whole clip wraps to the trim start.
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item).sink { [weak self] _ in
                guard let self else { return }
                self.loopBack(self.model.trim.lowerBound, reason: "the clip ended")
            },
            player.publisher(for: \.timeControlStatus).dropFirst().sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = status != .paused
                self.updateGradeRate()
                if self.appActive && !self.exporting { self.model.playbackWanted = status != .paused }
            },
        ]
    }

    // MARK: Transport

    /// The preview holds still, graded and seekable, until a copy it is waiting for is ready.
    func play() {
        guard model.previewPreparing == nil else { return }
        player?.play()
    }

    func pause() { player?.pause() }

    func togglePlay() {
        guard let player else { return }
        if player.timeControlStatus == .paused {
            let range = model.trim
            if playhead >= range.upperBound { seek(range.lowerBound) }
            play()
        } else { pause() }
    }

    /// Seeking exactly to the end would wrap the looping player; 1 ms earlier shows the last frame.
    func seek(_ positionMs: Int64) {
        guard let player else { return }
        let limit = durationMs > 0 ? min(positionMs, durationMs - 1) : positionMs
        let target = max(limit, 0)
        playhead = target
        player.seek(to: CMTime(value: target, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private var loopingSince: Date?

    /// Back to the start of the loop and playing from there. Playing from the seek's completion, as at the start, rather
    /// than while the seek is still going: that left an HDR clip's picture frozen in the iOS Simulator at the second loop.
    private func loopBack(_ positionMs: Int64, reason: String) {
        // A seek still going is left alone, but never for more than three seconds, in case its completion never arrives.
        guard let player, let item, loopingSince.map({ Date().timeIntervalSince($0) > 3 }) ?? true else { return }
        loopingSince = Date()
        let limit = durationMs > 0 ? min(positionMs, durationMs - 1) : positionMs
        let target = max(limit, 0)
        NSLog("AquaRestore: looping back to \(target) ms because \(reason) (frame requests so far \(model.gradeState.requests))")
        playhead = target
        player.seek(to: CMTime(value: target, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loopingSince = nil
                guard self.item === item else { return }
                self.play()
            }
        }
    }

    /// At most 30 frames a second on screen at any speed: 60 fps footage keeps every frame at 0.5×, and
    /// high-resolution footage grades half as many frames at 1×. Paused frames always grade, so sliders update them.
    private func updateGradeRate() {
        model.gradeState.frameRate = isPlaying ? Self.previewFps / max(speed, 0.01) : 0
    }

    private func applyRate() {
        rate = speed
        updateGradeRate()
        guard let player else { return }
        player.defaultRate = speed
        if player.rate != 0 { player.rate = speed }
    }

    private func setOriginalVolume(_ value: Float) {
        player?.volume = min(value, 1)
        originalBoost.gain = max(value, 1)
        if value > 1 { installBoost(on: item, originalAudio, originalBoost) }
    }

    /// AVPlayer's own volume stops at 1, so volumes above 100% go through a boost stage in the audio pipeline. It is only
    /// added once needed: at normal volume the audio takes the same plain path as Photos and an unchanged export.
    private func installBoost(on item: AVPlayerItem?, _ track: AVAssetTrack?, _ box: GainBox) {
        guard let item, let track, item.audioMix == nil else { return }
        let mix = AVMutableAudioMix()
        mix.inputParameters = [GainTap.parameters(track, box)]
        item.audioMix = mix
    }

    // MARK: Trim

    private func trimChanged(_ range: MsRange, _ active: Bool) {
        guard player != nil else { previous = range; return }
        if active {
            if !resume && isPlaying { resume = true; pause() }
            if range != previous { seek(range.lowerBound != previous.lowerBound ? range.lowerBound : range.upperBound) }
        } else if resume {
            // Playback was running before the drag: carry on from the new start.
            seek(range.lowerBound); play(); resume = false
        } else if range != previous {
            // A new end pauses on the last kept frame (exports keep frames before the end), a new start plays on.
            if range.lowerBound == previous.lowerBound { pause(); seek(range.upperBound - 1) } else { seek(range.lowerBound) }
        }
        previous = range
    }

    // MARK: Ticks

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let player, let item else { return }
        let position = Int64((player.currentTime().seconds * 1000).rounded())
        if position != playhead && position >= 0 { playhead = position }
        let range = model.trim
        // Loop inside the trim range; ending the whole clip alone would replay everything.
        if !model.trimming && range.upperBound > range.lowerBound && item.status == .readyToPlay {
            if player.rate != 0 && position >= range.upperBound { loopBack(range.lowerBound, reason: "the trim end was reached") }
            else if position < range.lowerBound - 50 { seek(range.lowerBound) }
        }
        watchForStall(player, item, position)
        syncMusic(position, range)
    }

    private var requestsSeen = 0
    private var lastRequestAt = Date()

    /// The clock runs but the compositor is no longer asked for frames, so the picture freezes while the sound goes on.
    /// With an HDR clip in the iOS Simulator this happens when playback starts from the beginning, at the start and again
    /// at each loop; moving the playhead a little ahead and playing starts it again, as a tap on the trim bar does.
    /// Above normal speed a gap only means the decoder is behind, since it has to read every frame, four times as fast at
    /// 4×. Jumping would send it back to a keyframe with more to read, and the picture would freeze instead of catching up.
    private func watchForStall(_ player: AVPlayer, _ item: AVPlayerItem, _ position: Int64) {
        let count = model.gradeState.requests
        guard player.rate != 0, speed <= 1, item.status == .readyToPlay, !model.trimming, appActive, !exporting else {
            requestsSeen = count; lastRequestAt = Date(); return
        }
        if count != requestsSeen { requestsSeen = count; lastRequestAt = Date(); return }
        guard Date().timeIntervalSince(lastRequestAt) > 1.2 else { return }
        lastRequestAt = Date()
        let range = model.trim
        let ahead = min(position + 500, max(range.upperBound - 1, range.lowerBound))
        NSLog("AquaRestore: video stalled at \(position) ms (no frame requested for 1.2 s while playing); jumping to \(ahead) ms and playing")
        seek(ahead)
        play()
    }

    /// While paused, a changed grade is shown by re-rendering the current frame.
    private func refreshPausedFrame() {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        Task { [weak self] in
            repeat {
                guard let self else { return }
                self.refreshAgain = false
                if let player = self.player, self.item?.status == .readyToPlay, player.rate == 0 {
                    // Nudge back a millisecond so the compositor draws the frame again.
                    let now = max(Int64((player.currentTime().seconds * 1000).rounded()) - 1, 0)
                    await player.seek(to: CMTime(value: now, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            } while self?.refreshAgain == true
            self?.refreshing = false
        }
    }

    // MARK: Lifecycle

    private func resignActive() {
        appActive = false
        if player?.rate != 0 && player != nil { model.playbackWanted = true }
        model.playbackPositionMs = playhead
        player?.pause()
        musicPlayer?.pause()
    }

    private func becomeActive() {
        appActive = true
        if !exporting && model.playbackWanted { play() }
    }

    // MARK: Music

    /// Background music plays on its own player at normal speed, following the video's output time.
    private func loadMusic(_ track: MusicTrack?) {
        musicPlayer?.pause()
        musicPlayer = nil
        musicEnd = nil
        guard let track else { return }
        musicBoost = GainBox()
        musicAudio = nil
        let item = AVPlayerItem(url: track.url)
        let boost = musicBoost
        Task { [weak self] in
            let asset = AVURLAsset(url: track.url)
            guard let audio = try? await asset.loadTracks(withMediaType: .audio).first, let self, self.musicBoost === boost else { return }
            self.musicAudio = audio
            if self.model.musicVolume > 1 { self.installBoost(on: item, audio, boost) }
        }
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        musicEnd = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item).sink { [weak player] _ in
            player?.seek(to: .zero); player?.play()
        }
        musicPlayer = player
        setMusicVolume(model.musicVolume)
    }

    private func setMusicVolume(_ value: Float) {
        musicPlayer?.volume = min(value, 1)
        musicBoost.gain = max(value, 1)
        if value > 1 { installBoost(on: musicPlayer?.currentItem, musicAudio, musicBoost) }
    }

    private func syncMusic(_ position: Int64, _ range: MsRange) {
        guard let song = musicPlayer else { return }
        let track = model.music
        let outputMs = Int64(Double(range.upperBound - range.lowerBound) / Double(model.speed))
        let window = track.map { musicWindow(songMs: $0.durationMs, startMs: model.musicStartMs, outputMs: outputMs) }
        let elapsed = Int64(Double(position - range.lowerBound) / Double(model.speed))
        let target: Int64? = track == nil || window == nil || player?.rate == 0 || model.trimming || !appActive ? nil
            : musicPosition(songMs: track!.durationMs, window: window!, elapsedMs: elapsed)
        guard let target else {
            if song.rate != 0 { song.pause() }
            return
        }
        // Re-sync only on real drift (seeks, loops), not on normal clock jitter.
        let current = Int64((song.currentTime().seconds * 1000).rounded())
        if abs(current - target) > 250 {
            song.seek(to: CMTime(value: target, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if song.rate == 0 { song.play() }
    }
}

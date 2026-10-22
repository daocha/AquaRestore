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
    /// The rate playback runs at; the controller's settings menu can change it, as Media3's does.
    @Published private(set) var rate: Float = 1
    /// The source's display aspect ratio, which the player view keeps (its controls cover only the video).
    @Published private(set) var aspect: CGFloat?

    private unowned let model: EditorModel
    private var item: AVPlayerItem?
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var observers: [AnyCancellable] = []
    private var itemObservers: [AnyCancellable] = []
    private var originalBoost = GainBox()
    private var musicBoost = GainBox()
    private var musicPlayer: AVPlayer?
    private var musicEnd: AnyCancellable?
    private var appActive = true
    private var exporting = false
    private var resume = false
    private var previous: MsRange = 0...0
    private var speed: Float = 1
    private var refreshing = false
    private var refreshAgain = false

    init(model: EditorModel) {
        self.model = model
        AppActivity.observe()
        let center = NotificationCenter.default
        observers = [
            center.publisher(for: Notification.Name("UIApplicationWillResignActiveNotification")).sink { [weak self] _ in self?.resignActive() },
            center.publisher(for: Notification.Name("UIApplicationDidBecomeActiveNotification")).sink { [weak self] _ in self?.becomeActive() },
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
                self.seek(self.model.trim.lowerBound); self.play()
            },
            Exports.shared.$status.map(\.busy).removeDuplicates().sink { [weak self] busy in
                guard let self else { return }
                self.exporting = busy
                if busy { self.pause() } else if self.model.playbackWanted && self.appActive { self.play() }
            },
        ]
    }

    // MARK: Loading

    func load(_ media: SourceMedia) {
        unload()
        loadTask = Task { [weak self] in
            do {
                let asset = AVURLAsset(url: media.url)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaProblem("playbackFailed") }
                let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
                let duration = try await asset.load(.duration)
                let audio = try await asset.loadTracks(withMediaType: .audio).first
                guard let self, !Task.isCancelled else { return }

                // The preview renders at up to 1920px; the layer scales it to the view.
                let display = GradeInstruction.displaySize(natural, transform)
                let scale = min(1, 1920 / max(display.width, display.height))
                let render = CGSize(width: max(2, (display.width * scale / 2).rounded() * 2), height: max(2, (display.height * scale / 2).rounded() * 2))
                let fps = Int32(min(max(media.fps.rounded(), 24), 60))
                let composition = GradeComposition.make(track: track, trackID: track.trackID, duration: duration, state: self.model.gradeState,
                    hdr: media.hdr, transform: transform, naturalSize: natural, renderSize: render, frameDuration: CMTime(value: 1, timescale: fps))
                let item = AVPlayerItem(asset: asset)
                item.videoComposition = composition
                item.audioTimePitchAlgorithm = .spectral
                // Volumes above 100% go through a boost stage in the audio pipeline; AVPlayer's own volume stops at 1.
                if let audio {
                    let mix = AVMutableAudioMix()
                    mix.inputParameters = [GainTap.parameters(audio, self.originalBoost)]
                    item.audioMix = mix
                }
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
                self.seek(self.model.playbackPositionMs)
                if self.model.playbackWanted && !self.exporting && self.appActive { self.play() }
                self.startTimer()
            } catch is CancellationError {
            } catch {
                self?.model.error = "playbackFailed"
            }
        }
    }

    func unload() {
        loadTask?.cancel(); loadTask = nil
        timer?.invalidate(); timer = nil
        itemObservers = []
        player?.pause()
        player = nil
        item = nil
        playhead = 0
        durationMs = 0
        aspect = nil
        isPlaying = false
        resume = false
        musicPlayer?.pause()
    }

    private func observe(_ item: AVPlayerItem, _ player: AVPlayer) {
        itemObservers = [
            item.publisher(for: \.status).sink { [weak self] status in
                if status == .failed {
                    NSLog("AquaRestore: preview playback failed: \(String(describing: item.error))")
                    self?.model.error = "playbackFailed"
                }
            },
            // The loop stays inside the trim range; ending the whole clip wraps to the trim start.
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item).sink { [weak self] _ in
                guard let self else { return }
                self.seek(self.model.trim.lowerBound); self.play()
            },
            player.publisher(for: \.timeControlStatus).dropFirst().sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = status != .paused
                if self.appActive && !self.exporting { self.model.playbackWanted = status != .paused }
            },
        ]
    }

    // MARK: Transport

    func play() { player?.play() }

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

    private func applyRate() {
        rate = speed
        guard let player else { return }
        player.defaultRate = speed
        if player.rate != 0 { player.rate = speed }
    }

    /// The controller's "Speed" setting: changes the player only, like Media3's settings menu.
    func overrideRate(_ value: Float) {
        rate = value
        guard let player else { return }
        player.defaultRate = value
        if player.rate != 0 { player.rate = value }
    }

    /// Media3's rewind (5 s) and fast-forward (15 s) buttons.
    func seek(by deltaMs: Int64) { seek(min(max(playhead + deltaMs, 0), max(durationMs - 1, 0))) }

    /// Media3's previous button with a single item: back to the beginning.
    func seekToPrevious() { seek(0) }

    /// How far the file has been loaded, for the time bar's buffered segment.
    var bufferedMs: Int64 {
        guard let item else { return 0 }
        let end = item.loadedTimeRanges.map { $0.timeRangeValue.end.seconds }.max() ?? 0
        return Int64((end * 1000).rounded())
    }

    private func setOriginalVolume(_ value: Float) {
        player?.volume = min(value, 1)
        originalBoost.gain = max(value, 1)
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
        if !model.trimming && range.upperBound > range.lowerBound && item.status == .readyToPlay &&
            (position < range.lowerBound - 50 || (player.rate != 0 && position >= range.upperBound)) {
            seek(range.lowerBound)
        }
        syncMusic(position, range)
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
        let item = AVPlayerItem(url: track.url)
        let boost = musicBoost
        Task { [weak self] in
            let asset = AVURLAsset(url: track.url)
            guard let audio = try? await asset.loadTracks(withMediaType: .audio).first, let self, self.musicBoost === boost else { return }
            let mix = AVMutableAudioMix()
            mix.inputParameters = [GainTap.parameters(audio, boost)]
            item.audioMix = mix
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

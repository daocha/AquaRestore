import AVFoundation
import AudioToolbox
import Combine
import Photos
import UniformTypeIdentifiers

/// The request holds a frozen grade and the original file, never a preview copy.
struct ExportRequest {
    let source: SourceMedia
    let grade: Grade
    let options: ExportOptions
    let chinese: Bool
    var audio = AudioMix()
}

struct ExportStatus: Equatable {
    var busy = false
    var progress: Int?
    var stage = "exporting"
    var saved = false
    var error: String?
    var batch: BatchExportStatus?
    var comparisons: [ShareMedia] = []
    var comparisonUnavailable = false
    var comparisonsBusy = false
}

/// Photos or videos already copied out of the Photos library, each graded automatically and exported whole.
struct BatchRequest {
    let sources: [SourceMedia]
    /// Picked items that could not be copied or read; reported with the rest.
    let failures: [BatchFailure]
    let selection: ExportSelection
    let videos: Bool
    let chinese: Bool
    /// The app's copies of the picked files, removed when the batch ends.
    let folders: [URL]
    var total: Int { sources.count + failures.count }
}

/// A flag that background queues can poll, set when the export task is cancelled.
final class CancelFlag {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Counts the video frames an export reads, for the log and for noticing that none ever arrive.
final class FrameCounter {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    /// Returns true for the first frame.
    func add() -> Bool { lock.lock(); defer { lock.unlock() }; value += 1; return value == 1 }
}

/// Each attempt owns a different path while an interrupted writer is still shutting down.
private final class ExportFile {
    let url: URL
    init(extension ext: String) {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).\(ext)")
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

@MainActor
final class Exports: ObservableObject {
    static let shared = Exports()
    @Published var status = ExportStatus()
    private var task: Task<Void, Never>?
    @Published var resultActionBusy = false

    func activityChanged(_ active: Bool) {
        AppActivity.set(active)
        guard status.busy, status.stage != "saving" else { return }
        if !active { status.stage = "paused" }
        else if status.stage == "paused" { status.stage = "restarting" }
    }

    func start(_ request: ExportRequest) {
        if status.busy { return }
        ComparisonWork.reset(); ShareMediaMaker.remove(status.comparisons)
        batch = nil
        status = ExportStatus(busy: true)
        Platform.keepScreenAwake(true)
        task = Task { [weak self] in
            var terminal = ExportStatus(error: "exportFailed")
            let comparison = ComparisonWork.submit(request)
            do {
                try await Exporter.run(request, load: comparison?.load) { progress, stage in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.status.busy else { return }
                        self.status = ExportStatus(busy: true, progress: progress,
                            stage: stage == "paused" && AppActivity.active ? "restarting" : stage)
                    }
                }
                ComparisonWork.accept(comparison)
                terminal = ExportStatus(progress: 100, stage: "saved", saved: true)
            } catch is CancellationError {
                terminal = ExportStatus(stage: "cancelled")
            } catch {
                NSLog("AquaRestore: export failed: \(error)")
                terminal = ExportStatus(error: (error as? MediaProblem)?.key ?? "exportFailed")
            }
            Platform.keepScreenAwake(false)
            self?.task = nil
            if !terminal.saved { ComparisonWork.reject(comparison) }
            ComparisonWork.finish(terminal)
        }
    }

    /// The running batch's progress; read by `publish` for every update.
    private var batch: BatchExportStatus?
    /// The item whose export is running, or -1 between items. Progress arrives queued on the main thread, so a
    /// finished item's last updates can land after it was counted, and would push the bar past it.
    private var batchItem = -1

    private func publish(_ progress: Int?, _ stage: String) {
        guard status.busy, let batch else { return }
        let overall = progress.map { min((batch.completed * 100 + $0) / max(batch.total, 1), 100) }
        status = ExportStatus(busy: true, progress: overall,
            stage: stage == "paused" && AppActivity.active ? "restarting" : stage, batch: batch)
    }

    func startBatch(_ request: BatchRequest) {
        if status.busy { request.folders.forEach { try? FileManager.default.removeItem(at: $0) }; return }
        ComparisonWork.reset(); ShareMediaMaker.remove(status.comparisons)
        // The player starts watching for this too, but a batch starts from the home screen, without a player.
        AppActivity.observe()
        batch = BatchExportStatus(total: request.total, failures: request.failures, videos: request.videos)
        status = ExportStatus(busy: true, stage: "analyzing", batch: batch)
        Platform.keepScreenAwake(true)
        task = Task { [weak self] in
            guard let self else { return }
            var terminal = ExportStatus(error: "exportFailed")
            do {
                for (index, source) in request.sources.enumerated() {
                    try Task.checkCancellation()
                    self.batch?.currentName = source.name
                    // Export pauses in the background; wait here too, so nothing starts while the app is away.
                    try await BatchRun.whileInactive { self.publish(nil, "paused") }
                    self.publish(0, "analyzing")
                    var comparison: ComparisonWork.Entry?
                    do {
                        if source.video != request.videos { throw MediaProblem(request.videos ? "batchVideosOnly" : "batchPhotosOnly") }
                        let grade = try await ForegroundExport.run(waiting: { self.publish(nil, AppActivity.active ? "restarting" : "paused") }) {
                            self.publish(0, "analyzing")
                            return try await MediaIO.analyze(source).grade
                        }
                        try Task.checkCancellation()
                        let options = request.videos ? request.selection.videoOptions(width: source.width, height: source.height,
                                                                                     fps: source.fps, codec: source.codec, hdr: source.isHdr)
                            : request.selection.photoOptions(width: source.width, height: source.height, pngSource: source.url.pathExtension.lowercased() == "png")
                        // Checked before each video, since the earlier ones have used some of the space.
                        if request.videos, let size = BatchRun.estimatedBytes(source, options),
                           let free = BatchRun.freeSpace, free < batchVideoSpace([size]) { throw MediaProblem("storageFull") }
                        self.batchItem = index
                        let item = ExportRequest(source: source, grade: grade, options: options, chinese: request.chinese)
                        comparison = ComparisonWork.submit(item)
                        try await Exporter.run(item, load: comparison?.load) { progress, stage in
                            DispatchQueue.main.async { if self.batchItem == index { self.publish(progress, stage) } }
                        }
                        self.batchItem = -1
                        self.batch?.saved += 1
                        ComparisonWork.accept(comparison)
                    } catch is CancellationError {
                        ComparisonWork.reject(comparison)
                        throw CancellationError()
                    } catch {
                        ComparisonWork.reject(comparison)
                        self.batchItem = -1
                        NSLog("AquaRestore: batch item failed: \(error)")
                        self.batch?.failures.append(BatchFailure(name: source.name, error: (error as? MediaProblem)?.key ?? "exportFailed"))
                    }
                    // Free the copy straight away; a batch of videos would otherwise hold all of them.
                    try? FileManager.default.removeItem(at: source.url.deletingLastPathComponent())
                    self.publish(0, "exporting")
                }
                let failed = !(self.batch?.failures.isEmpty ?? true)
                terminal = ExportStatus(progress: 100, stage: failed ? "batchFinished" : "saved", saved: (self.batch?.saved ?? 0) > 0)
            } catch {
                terminal = ExportStatus(stage: "cancelled")
            }
            request.folders.forEach { try? FileManager.default.removeItem(at: $0) }
            Platform.keepScreenAwake(false)
            self.batchItem = -1
            self.task = nil
            self.batch?.currentName = nil
            terminal.batch = self.batch
            self.batch = nil
            ComparisonWork.finish(terminal)
        }
    }

    func cancel() { task?.cancel() }
    func dismissResult() {
        guard !resultActionBusy else { return }
        ComparisonWork.dismiss()
        ShareMediaMaker.remove(status.comparisons)
        status = ExportStatus()
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !status.busy { RatingReminder.requestIfEligible() }
        }
    }
}

/// Runs on the main actor with the batch, so its `waiting` callbacks can update the export status directly.
@MainActor
enum BatchRun {
    /// Waits while AquaRestore is not the active app.
    static func whileInactive(_ waiting: () -> Void) async throws {
        while !AppActivity.active {
            waiting()
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    static func estimatedBytes(_ source: SourceMedia, _ options: ExportOptions) -> Int64? {
        videoExportPlan(width: source.width, height: source.height, fps: source.fps, sourceBitrate: source.bitrate,
                        audioBitrate: source.audioBitrate, durationMs: source.durationMs, options: options).estimatedBytes
    }

    /// Free space where exports are written first, as iOS counts it for work the user asked for.
    static var freeSpace: Int64? {
        let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

enum Exporter {
    typealias Update = @Sendable (Int?, String) -> Void

    static func run(_ request: ExportRequest, load: ExportLoad? = nil, update: @escaping Update) async throws {
        await MainActor.run { AppActivity.observe() }
        let o = request.options
        let source = request.source
        let lossless = o.png
        let ext = source.video ? "mp4" : (lossless ? "png" : "jpg")
        let file = try await ForegroundExport.run(waiting: { update(nil, AppActivity.active ? "restarting" : "paused") }) {
            let file = ExportFile(extension: ext)
            update(0, "exporting")
            if source.video {
                try await exportVideo(request, to: file.url, load: load, update: update)
            } else {
                try await exportPhoto(request, to: file.url, lossless: lossless, update: update)
            }
            return file
        }
        try Task.checkCancellation()
        update(90, "saving")
        // Once publication starts, let the short transaction finish and report success, so cancelling at 99%
        // cannot leave a saved file while the UI says "cancelled".
        let name = exportFileName(sourceName: source.name, extension: ext)
        try await Task.detached { try await PhotoSaver.save(file.url, video: source.video, name: name) }.value
        await MainActor.run { RatingReminder.saved(video: source.video) }

    }

    // MARK: Photo

    static func exportPhoto(_ request: ExportRequest, to temp: URL, lossless: Bool, update: @escaping Update) async throws {
        let o = request.options
        let flag = CancelFlag()
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let bitmap = try MediaIO.bitmap(request.source.url, edge: o.original ? 0 : o.longEdge)
                let graded = try MediaIO.gradeBitmap(bitmap, request.grade, progress: { update($0 * 80 / 100, "exporting") }, cancelled: { flag.isSet })
                update(82, "encoding")
                guard let image = graded.cgImage,
                      let destination = CGImageDestinationCreateWithURL(temp as CFURL, (lossless ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)
                else { throw MediaProblem("exportFailed") }
                let properties = lossless ? nil : [kCGImageDestinationLossyCompressionQuality: Double(o.quality) / 100] as CFDictionary
                CGImageDestinationAddImage(destination, image, properties)
                guard CGImageDestinationFinalize(destination) else { throw MediaProblem("exportFailed") }
            }.value
        } onCancel: { flag.set() }
    }

    // MARK: Video

    static func exportVideo(_ request: ExportRequest, to temp: URL, comparison: Bool = false, load: ExportLoad? = nil, update: @escaping Update) async throws {
        let generation = AppActivity.generation
        let source = request.source
        let o = request.options
        let audioMix = request.audio
        try MediaIO.requireHdrEncoder(source)
        // MP4 export supports AVC and HEVC here. Original must not silently change another codec.
        if o.original && !canPreserveVideoCodec(source.codec, hdr: source.isHdr) {
            throw MediaProblem("originalCodec")
        }

        let asset = AVURLAsset(url: source.url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw MediaProblem("unsupported") }
        let audioTracks = comparison ? [] : try await asset.loadTracks(withMediaType: .audio)
        let (natural, transform) = try await videoTrack.load(.naturalSize, .preferredTransform)
        let assetDuration = try await asset.load(.duration)

        let start = CMTime(value: o.startMs, timescale: 1000)
        let end = o.endMs > 0 ? min(CMTime(value: o.endMs, timescale: 1000), assetDuration) : assetDuration
        let range = CMTimeRange(start: start, end: end)
        guard range.duration.seconds > 0 else { throw MediaProblem("exportFailed") }

        // Speed retimes video and the camera's sound together; music is added afterwards at normal speed.
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw MediaProblem("exportFailed") }
        try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        // Media3 stalls retiming a video-only item, so with a speed change muted sound stays in as silence;
        // here the original track is simply dropped when it is muted at normal speed.
        let dropOriginal = audioMix.originalVolume == 0 && o.speed == 1
        var compAudio: AVMutableCompositionTrack?
        if !dropOriginal, let audio = audioTracks.first {
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw MediaProblem("exportFailed")
            }
            try track.insertTimeRange(range, of: audio, at: .zero)
            compAudio = track
        }
        if o.speed != 1 {
            composition.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration),
                                       toDuration: CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / Double(o.speed)))
        }
        var compMusic: AVMutableCompositionTrack?
        if let music = audioMix.music, audioMix.hasMusic {
            let songAsset = AVURLAsset(url: music.url)
            guard let song = try await songAsset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw MediaProblem("exportFailed") }
            let outputMs = Int64(Double(o.trimmedMs(source.durationMs)) / Double(o.speed))
            let window = musicWindow(songMs: music.durationMs, startMs: audioMix.musicStartMs, outputMs: outputMs)
            var position = CMTime.zero
            // A song shorter than the video repeats back to back, the last copy cut to fit.
            for piece in musicPieces(window: window, outputMs: outputMs) {
                let length = CMTime(value: piece.upperBound - piece.lowerBound, timescale: 1000)
                try track.insertTimeRange(CMTimeRange(start: CMTime(value: piece.lowerBound, timescale: 1000), duration: length), of: song, at: position)
                position = position + length
            }
            compMusic = track
        }

        // Video: graded by the same GPU compositor as the preview, at the output size.
        let edge = o.original ? 0 : o.longEdge
        let (width, height) = ExportSizing.dimensions(source.width, source.height, edge, even: true)
        let effectiveFps = source.fps * (comparison ? o.speed : min(o.speed, 1))
        let fpsLimit: Float = comparison ? 30 : (!o.original && o.fps > 0 ? min(Float(o.fps), source.fps) : source.fps)
        let frameDuration = CMTime(value: 1000, timescale: CMTimeScale(max(1, (min(effectiveFps, comparison ? 30 : effectiveFps) * 1000).rounded())))
        let videoComposition = GradeComposition.make(track: compVideo, trackID: compVideo.trackID, duration: composition.duration,
            state: GradeState(request.grade), hdr: source.hdr, transform: transform, naturalSize: natural,
            renderSize: CGSize(width: width, height: height), frameDuration: frameDuration, comparison: comparison)
        // Speeding up keeps the source frame rate by dropping frames; a lower cap drops more, never invents any.
        let cadence: FrameCadence? = fpsLimit < source.fps * o.speed ? FrameCadence(fps: fpsLimit) : nil

        let reader = try AVAssetReader(asset: composition)
        // Keeps the retimed audio from running on past the video.
        reader.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [compVideo], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: source.isHdr ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA,
        ])
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderOutput?
        var passthroughFormat: CMFormatDescription?
        let audioSources = [compAudio, compMusic].compactMap { $0 }
        if !audioSources.isEmpty {
            // An untouched AAC track can pass into MP4 without a lossy second encode.
            var originalFormat: CMFormatDescription?
            if let sourceAudio = audioTracks.first {
                originalFormat = try await sourceAudio.load(.formatDescriptions).first
            }
            if o.speed == 1, !audioMix.changesAudio, let compAudio,
               let originalFormat, CMFormatDescriptionGetMediaSubType(originalFormat) == kAudioFormatMPEG4AAC {
                let output = AVAssetReaderTrackOutput(track: compAudio, outputSettings: nil)
                guard reader.canAdd(output) else { throw MediaProblem("exportFailed") }
                reader.add(output)
                audioOutput = output
                passthroughFormat = originalFormat
            } else {
                let output = AVAssetReaderAudioMixOutput(audioTracks: audioSources, audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
                    AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
                ])
                let mix = AVMutableAudioMix()
                var parameters: [AVMutableAudioMixInputParameters] = []
                if let compAudio { parameters.append(GainTap.parameters(compAudio, GainBox(audioMix.originalVolume))) }
                if let compMusic { parameters.append(GainTap.parameters(compMusic, GainBox(audioMix.musicVolume))) }
                mix.inputParameters = parameters
                output.audioMix = mix
                output.audioTimePitchAlgorithm = .spectral
                guard reader.canAdd(output) else { throw MediaProblem("exportFailed") }
                reader.add(output)
                audioOutput = output
            }
        }

        // Writer: target bitrate from the same plan the size estimate uses.
        let bitrate = videoExportPlan(width: source.width, height: source.height, fps: source.fps, sourceBitrate: source.bitrate,
            audioBitrate: source.audioBitrate, durationMs: source.durationMs, options: o, mixedAudio: audioMix.changesAudio).bitrate
        let useHevc = source.isHdr || (o.original && (source.codec == "hvc1" || source.codec == "hev1"))
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: Int(min(effectiveFps, fpsLimit).rounded()),
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoProfileLevelKey: useHevc ? (source.isHdr ? "HEVC_Main10_AutoLevel" : "HEVC_Main_AutoLevel") : AVVideoProfileLevelH264HighAutoLevel,
        ]
        if !useHevc { compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC }
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: useHevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: compression,
        ]
        videoSettings[AVVideoColorPropertiesKey] = [
            AVVideoColorPrimariesKey: source.isHdr ? AVVideoColorPrimaries_ITU_R_2020 : AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: source.hdr == .pq ? AVVideoTransferFunction_SMPTE_ST_2084_PQ : (source.hdr == .hlg ? AVVideoTransferFunction_ITU_R_2100_HLG : AVVideoTransferFunction_ITU_R_709_2),
            AVVideoYCbCrMatrixKey: source.isHdr ? AVVideoYCbCrMatrix_ITU_R_2020 : AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        try? FileManager.default.removeItem(at: temp)
        let label = comparison ? "comparison" : "export"
        NSLog("AquaRestore: \(label) starting: \(source.width)x\(source.height) at \(source.fps) fps to \(width)x\(height), original=\(o.original), \(useHevc ? "hevc" : "h264"), \(bitrate) bps\(AppLog.memory)")
        defer { NSLog("AquaRestore: \(label) ended\(AppLog.memory)") }
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mp4)
        // Creating the input with settings the device refuses raises an exception that Swift cannot catch.
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            NSLog("AquaRestore: this device cannot encode \(width)x\(height) as \(useHevc ? "HEVC" : "H.264")")
            throw MediaProblem(source.isHdr ? "hdrDevice" : "exportFailed")
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw MediaProblem(source.isHdr ? "hdrDevice" : "exportFailed") }
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = passthroughFormat.map {
                AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: $0)
            } ?? AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: min(max(source.audioBitrate, 128_000), 256_000),
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw MediaProblem("exportFailed") }
            writer.add(input)
            audioInput = input
        }

        let interrupted = CancelFlag()
        let completion = ExportCompletion()
        let cleanup = DispatchQueue(label: "AquaRestore.export.cleanup.\(UUID().uuidString)")
        let observer = NotificationCenter.default.addObserver(
            forName: AppActivity.didBecomeInactive, object: nil, queue: nil
        ) { _ in
            interrupted.set()
            update(nil, "paused")
            // Cancellation may wait on a frame; do not block the lifecycle callback or the retry on it.
            completion.resolve(.failure(ExportInterrupted()))
            cleanup.async { reader.cancelReading(); writer.cancelWriting() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        guard AppActivity.active, generation == AppActivity.generation, !interrupted.isSet else { throw ExportInterrupted() }
        guard writer.startWriting() else { throw writer.error ?? MediaProblem("exportFailed") }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw reader.error ?? MediaProblem("exportFailed")
        }
        writer.startSession(atSourceTime: .zero)
        NSLog("AquaRestore: \(label) video started: \(width)x\(height) hdr=\(source.hdr.rawValue) codec=\(useHevc ? "hevc" : "h264") bitrate=\(bitrate) length=\(composition.duration.seconds)s")
        let started = Date()

        let flag = CancelFlag()
        let failed = CancelFlag()
        let finished = CancelFlag()
        let frames = FrameCounter()
        let totalSeconds = max(composition.duration.seconds, 0.001)
        load?.begin(total: totalSeconds, now: started)
        let group = DispatchGroup()

        func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, video: Bool) {
            group.enter()
            let queue = DispatchQueue(label: "AquaRestore.\(label).\(video ? "video" : "audio")")
            // A dedicated pump can exit even when a cancelled writer stops asking for media data.
            queue.async {
                defer { group.leave() }
                while !flag.isSet && !failed.isSet && !interrupted.isSet {
                    if writer.status != .writing { failed.set(); break }
                    guard input.isReadyForMoreMediaData else { Thread.sleep(forTimeInterval: 0.01); continue }
                    guard let sample = output.copyNextSampleBuffer() else { break }
                    if flag.isSet || interrupted.isSet { break }
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    if video {
                        if frames.add() { NSLog("AquaRestore: \(label) video read its first frame after \(String(format: "%.1f", Date().timeIntervalSince(started))) s") }
                        load?.frame(at: time.seconds)
                        update(Int(min(time.seconds / totalSeconds, 1) * 90), "exporting")
                        AppLog.progress(label, percent: Int(min(time.seconds / totalSeconds, 1) * 100))
                        if let cadence, !cadence.accept(timeUs: Int64((time.seconds * 1_000_000).rounded())) { continue }
                    }
                    if !input.append(sample) { failed.set(); break }
                }
                if writer.status == .writing { input.markAsFinished() }
            }
        }
        pump(videoInput, videoOutput, video: true)
        if let audioInput, let audioOutput { pump(audioInput, audioOutput, video: false) }

        // If the video step never produces a frame (the HDR pipeline on some devices), stop with an error rather than
        // waiting for ever. Time spent in the background does not count.
        func watch(_ waited: Int) {
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if frames.count > 0 || flag.isSet || failed.isSet || finished.isSet || interrupted.isSet { return }
                let next = waited + (AppActivity.active ? 5 : 0)
                if next >= 30 {
                    NSLog("AquaRestore: \(label) video received no frames in 30 s; stopping")
                    failed.set()
                    reader.cancelReading()
                } else { watch(next) }
            }
        }
        watch(0)

        // Twice a second, because a crash from running out of memory leaves nothing else in the log. The comparison runs in
        // the same process, so the export's lines cover it.
        func sampleMemory() {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if flag.isSet || failed.isSet || finished.isSet || interrupted.isSet { return }
                NSLog("AquaRestore: \(label) read \(frames.count) frames\(AppLog.memory)")
                sampleMemory()
            }
        }
        if !comparison && AppLog.enabled { sampleMemory() }

        try await withTaskCancellationHandler {
            group.notify(queue: cleanup) {
                finished.set()
                NSLog("AquaRestore: \(label) video read \(frames.count) frames in \(String(format: "%.1f", Date().timeIntervalSince(started))) s; reader status \(reader.status.rawValue), cancelled \(flag.isSet), failed \(failed.isSet)")
                if flag.isSet {
                    reader.cancelReading(); writer.cancelWriting()
                    completion.resolve(.failure(CancellationError()))
                } else if interrupted.isSet || generation != AppActivity.generation {
                    reader.cancelReading(); writer.cancelWriting()
                    completion.resolve(.failure(ExportInterrupted()))
                } else if failed.isSet || reader.status == .failed {
                    let error = reader.error ?? writer.error ?? MediaProblem("exportFailed")
                    reader.cancelReading(); writer.cancelWriting()
                    completion.resolve(.failure(error))
                } else {
                    writer.finishWriting {
                        let size = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int) ?? nil
                        NSLog("AquaRestore: \(label) video writer status \(writer.status.rawValue), file \(size.map(String.init) ?? "missing") bytes, error \(String(describing: writer.error))")
                        if writer.status == .completed { completion.resolve(.success(())) }
                        else { completion.resolve(.failure(writer.error ?? MediaProblem("exportFailed"))) }
                    }
                }
            }
            try await completion.wait()
        } onCancel: {
            flag.set()
            completion.resolve(.failure(CancellationError()))
            cleanup.async { reader.cancelReading(); writer.cancelWriting() }
        }
    }
}

enum PhotoSaver {
    /// Adds the file to the Photos library. Only add-only access is requested.
    static func save(_ file: URL, video: Bool, name: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw MediaProblem("photosDenied") }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                options.originalFilename = name
                PHAssetCreationRequest.forAsset().addResource(with: video ? .video : .photo, fileURL: file, options: options)
            }
            NSLog("AquaRestore: saved \(name) to Photos")
        } catch {
            NSLog("AquaRestore: saving \(name) to Photos failed: \(error)")
            throw error
        }
    }
}

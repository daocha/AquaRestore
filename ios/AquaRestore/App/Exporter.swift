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
}

/// A flag that background queues can poll, set when the export task is cancelled.
final class CancelFlag {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// This build has no Background GPU Access entitlement, so the export pauses in the background.
enum AppActivity {
    private static let lock = NSLock()
    private static var _active = true
    static var active: Bool { lock.lock(); defer { lock.unlock() }; return _active }
    static func set(_ value: Bool) { lock.lock(); _active = value; lock.unlock() }

    private static var observers: [NSObjectProtocol] = []
    static func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: Notification.Name("UIApplicationWillResignActiveNotification"), object: nil, queue: nil) { _ in set(false) },
            center.addObserver(forName: Notification.Name("UIApplicationDidBecomeActiveNotification"), object: nil, queue: nil) { _ in set(true) },
        ]
    }
}

@MainActor
final class Exports: ObservableObject {
    static let shared = Exports()
    @Published var status = ExportStatus()
    private var task: Task<Void, Never>?

    func start(_ request: ExportRequest) {
        if status.busy { return }
        status = ExportStatus(busy: true)
        Platform.keepScreenAwake(true)
        task = Task { [weak self] in
            var terminal = ExportStatus(error: "exportFailed")
            do {
                try await Exporter.run(request) { progress, stage in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.status.busy else { return }
                        self.status = ExportStatus(busy: true, progress: progress, stage: stage)
                    }
                }
                terminal = ExportStatus(progress: 100, stage: "saved", saved: true)
            } catch is CancellationError {
                terminal = ExportStatus(stage: "cancelled")
            } catch {
                NSLog("AquaRestore: export failed: \(error)")
                terminal = ExportStatus(error: (error as? MediaProblem)?.key ?? "exportFailed")
            }
            Platform.keepScreenAwake(false)
            self?.task = nil
            self?.status = terminal
        }
    }

    func cancel() { task?.cancel() }
    func dismissResult() { status = ExportStatus() }
}

enum Exporter {
    typealias Update = @Sendable (Int?, String) -> Void

    static func run(_ request: ExportRequest, update: @escaping Update) async throws {
        let o = request.options
        let source = request.source
        let lossless = o.png
        let ext = source.video ? "mp4" : (lossless ? "png" : "jpg")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: temp) }
        if source.video {
            try await exportVideo(request, to: temp, update: update)
        } else {
            try await exportPhoto(request, to: temp, lossless: lossless, update: update)
        }
        try Task.checkCancellation()
        update(90, "saving")
        // Once publication starts, let the short transaction finish and report success, so cancelling at 99%
        // cannot leave a saved file while the UI says "cancelled".
        let name = exportFileName(sourceName: source.name, extension: ext)
        try await Task.detached { try await PhotoSaver.save(temp, video: source.video, name: name) }.value
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

    static func exportVideo(_ request: ExportRequest, to temp: URL, update: @escaping Update) async throws {
        let source = request.source
        let o = request.options
        let audioMix = request.audio
        try MediaIO.requireHdrEncoder(source)
        // MP4 export supports AVC and HEVC here. Original must not silently change another codec.
        let avc = ["avc1", "avc3"].contains(source.codec)
        let hevc = ["hvc1", "hev1"].contains(source.codec)
        if o.original && !(hevc || (avc && !source.isHdr)) {
            throw MediaProblem("originalCodec")
        }

        let asset = AVURLAsset(url: source.url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw MediaProblem("unsupported") }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
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
        let effectiveFps = source.fps * min(o.speed, 1)
        let fpsLimit: Float = !o.original && o.fps > 0 ? min(Float(o.fps), source.fps) : source.fps
        let frameDuration = CMTime(value: 1000, timescale: CMTimeScale(max(1, (effectiveFps * 1000).rounded())))
        let videoComposition = GradeComposition.make(track: compVideo, trackID: compVideo.trackID, duration: composition.duration,
            state: GradeState(request.grade), hdr: source.hdr, transform: transform, naturalSize: natural,
            renderSize: CGSize(width: width, height: height), frameDuration: frameDuration)
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
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mp4)
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

        guard writer.startWriting() else { throw writer.error ?? MediaProblem("exportFailed") }
        guard reader.startReading() else { throw reader.error ?? MediaProblem("exportFailed") }
        writer.startSession(atSourceTime: .zero)

        let flag = CancelFlag()
        let failed = CancelFlag()
        let totalSeconds = max(composition.duration.seconds, 0.001)
        let group = DispatchGroup()

        func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, label: String, video: Bool) {
            group.enter()
            let queue = DispatchQueue(label: "AquaRestore.export.\(label)")
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    while !AppActivity.active && !flag.isSet { Thread.sleep(forTimeInterval: 0.1) }
                    if flag.isSet || failed.isSet { input.markAsFinished(); group.leave(); return }
                    guard let sample = output.copyNextSampleBuffer() else { input.markAsFinished(); group.leave(); return }
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    if video {
                        update(Int(min(time.seconds / totalSeconds, 1) * 90), "exporting")
                        if let cadence, !cadence.accept(timeUs: Int64((time.seconds * 1_000_000).rounded())) { continue }
                    }
                    if !input.append(sample) { failed.set(); input.markAsFinished(); group.leave(); return }
                }
            }
        }
        pump(videoInput, videoOutput, label: "video", video: true)
        if let audioInput, let audioOutput { pump(audioInput, audioOutput, label: "audio", video: false) }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                group.notify(queue: .global()) {
                    if flag.isSet {
                        reader.cancelReading(); writer.cancelWriting()
                        continuation.resume(throwing: CancellationError())
                    } else if failed.isSet || reader.status == .failed {
                        let error = reader.error ?? writer.error ?? MediaProblem("exportFailed")
                        reader.cancelReading(); writer.cancelWriting()
                        continuation.resume(throwing: error)
                    } else {
                        writer.finishWriting {
                            if writer.status == .completed { continuation.resume() }
                            else { continuation.resume(throwing: writer.error ?? MediaProblem("exportFailed")) }
                        }
                    }
                }
            }
        } onCancel: { flag.set() }
    }
}

enum PhotoSaver {
    /// Adds the file to the Photos library. Only add-only access is requested.
    static func save(_ file: URL, video: Bool, name: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw MediaProblem("photosDenied") }
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            options.originalFilename = name
            PHAssetCreationRequest.forAsset().addResource(with: video ? .video : .photo, fileURL: file, options: options)
        }
    }
}

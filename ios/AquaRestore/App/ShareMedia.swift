import AVFoundation
import UIKit
import CoreImage

struct ShareMedia: Equatable, Identifiable {
    let id = UUID()
    let url: URL
    let video: Bool
}

enum ShareMediaMaker {
    static var root: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("share-previews") }
    private static let processCleanup: Void = { try? FileManager.default.removeItem(at: root) }()
    static func cleanup() { _ = processCleanup }
    static func remove(_ items: [ShareMedia]) { items.forEach { try? FileManager.default.removeItem(at: $0.url) } }

    static func make(_ request: ExportRequest, onAsset: (@Sendable (ShareMedia) -> Void)? = nil) async -> [ShareMedia] {
        guard request.source.width >= 2, request.source.height >= 2 else { return [] }
        if !request.source.video { return await makePhoto(request, onAsset: onAsset) }
        let flag = CancelFlag()
        let worker = Task<[ShareMedia], Never>.detached(priority: .utility) {
                var result: [ShareMedia] = []
                var pending: URL?
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                        let source = request.source
                        let total = Int64(Double(request.options.trimmedMs(source.durationMs)) / Double(request.options.speed))
                        let (offset, length) = SharingPlan.clip(total)
                        let (w, h) = SharingPlan.videoSize(source.width, source.height)
                        let input = source
                        let start = request.options.startMs + Int64(Double(offset) * Double(request.options.speed))
                        let end = min(source.durationMs, start + Int64(Double(length) * Double(request.options.speed)))
                        let options = ExportOptions(original: false, longEdge: max(w, h), fps: 30, quality: 85,
                                                    speed: request.options.speed, startMs: start, endMs: end)
                        let preview = ExportRequest(source: input, grade: request.grade, options: options, chinese: request.chinese)
                        let url = root.appendingPathComponent("\(UUID().uuidString).mp4"); pending = url
                        try await ForegroundExport.run(waiting: {}) {
                            try await Exporter.exportVideo(preview, to: url, comparison: true) { _, _ in }
                        }
                        result.append(ShareMedia(url: url, video: true)); pending = nil
                } catch {
                    if let pending { try? FileManager.default.removeItem(at: pending) }
                    if flag.isSet { remove(result); return [] }
                    NSLog("AquaRestore: comparison preview unavailable: \(error)")
                }
                return result
        }
        let deadline = Task.detached {
            do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
            flag.set(); worker.cancel()
        }
        defer { deadline.cancel() }
        return await withTaskCancellationHandler { await worker.value } onCancel: { flag.set(); worker.cancel() }
    }

    private final class PhotoVideoAttempt {
        let asset: ShareMedia
        var keep = false
        init(_ asset: ShareMedia) { self.asset = asset }
        deinit { if !keep { ShareMediaMaker.remove([asset]) } }
    }

    private static func makePhoto(_ request: ExportRequest, onAsset: (@Sendable (ShareMedia) -> Void)?) async -> [ShareMedia] {
        let flag = CancelFlag()
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { return [] }
        let movie = Task<[ShareMedia], Never>.detached(priority: .userInitiated) {
            do {
                let output = try await ForegroundExport.run(waiting: {}) {
                    PhotoVideoAttempt(try await photoVideo(request, flag: flag))
                }
                output.keep = true
                let item = output.asset
                guard !flag.isSet else { remove([item]); return [] }
                onAsset?(item)
                return [item]
            } catch { NSLog("AquaRestore: photo comparison video unavailable: \(error)"); return [] }
        }
        let still = Task<[ShareMedia], Never>.detached(priority: .utility) {
            do {
                let item = try photoCollage(request, flag: flag)
                guard !flag.isSet else { remove([item]); return [] }
                onAsset?(item)
                return [item]
            } catch { NSLog("AquaRestore: comparison collage unavailable: \(error)"); return [] }
        }
        let deadline = Task<Void, Never>.detached {
            do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
            flag.set(); movie.cancel(); still.cancel()
        }
        defer { deadline.cancel() }
        return await withTaskCancellationHandler {
            let video = await movie.value, photo = await still.value
            let assets = video + photo
            if Task.isCancelled { remove(assets); return [] }
            return assets
        } onCancel: { flag.set(); movie.cancel(); still.cancel() }
    }

    private static func photoCollage(_ request: ExportRequest, flag: CancelFlag) throws -> ShareMedia {
        let o = ExportRecommendation.photo(width: request.source.width, height: request.source.height,
                                           pngSource: request.source.url.pathExtension.lowercased() == "png")
        let before = try MediaIO.bitmap(request.source.url, edge: o.original ? 0 : o.longEdge)
        let after = try MediaIO.gradeBitmap(before, request.grade, cancelled: { flag.isSet })
        guard let b = before.cgImage, let a = after.cgImage else { throw MediaProblem("photoUnreadable") }
        let image = collage(UIImage(cgImage: b), UIImage(cgImage: a))
        guard let data = o.png ? image.pngData() : image.jpegData(compressionQuality: CGFloat(o.quality) / 100) else { throw MediaProblem("exportFailed") }
        let url = root.appendingPathComponent("\(UUID().uuidString).\(o.png ? "png" : "jpg")")
        do { try data.write(to: url) } catch { try? FileManager.default.removeItem(at: url); throw error }
        return ShareMedia(url: url, video: false)
    }

    private static func pixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { throw MediaProblem("memory") }
        return buffer
    }

    private static func photoVideo(_ request: ExportRequest, flag: CancelFlag) async throws -> ShareMedia {
        let (w, h) = SharingPlan.videoSize(request.source.width, request.source.height)
        let bitmap = try MediaIO.bitmap(request.source.url, edge: max(w, h))
        guard let cg = bitmap.cgImage, let grader = MetalGrader.shared else { throw MediaProblem("exportFailed") }
        let before = try pixelBuffer(width: w, height: h), after = try pixelBuffer(width: w, height: h)
        let size = CGSize(width: w, height: h)
        let image = CIImage(cgImage: cg)
        let scale = min(CGFloat(w) / image.extent.width, CGFloat(h) / image.extent.height)
        let fitted = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGAffineTransform(translationX: (CGFloat(w) - fitted.extent.width)/2, y: (CGFloat(h) - fitted.extent.height)/2)
        let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        ComparisonFrame.renderImage(fitted.transformed(by: offset).composited(over: background), to: before)
        let instruction = GradeInstruction(timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 6, timescale: 1)),
            trackID: 1, state: GradeState(request.grade), hdr: .sdr, transform: .identity, naturalSize: size)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            grader.render(instruction, source: before, output: after) { ok in
                if ok { continuation.resume() } else { continuation.resume(throwing: MediaProblem("exportFailed")) }
            }
        }
        if flag.isSet { throw CancellationError() }
        let original = CIImage(cvPixelBuffer: before), restored = CIImage(cvPixelBuffer: after)
        let mark = brandingImage(width: w, height: h).map { CIImage(cgImage: $0) }
        let url = root.appendingPathComponent("\(UUID().uuidString).mp4")
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: url) } }
        let began = Date()
        try await encode(url, width: w, height: h, duration: 6000, flag: flag) { pixel, fraction in
            ComparisonFrame.renderReveal(original: original, graded: restored, mark: mark, fraction: fraction, to: pixel)
        }
        NSLog("AquaRestore: GPU photo reveal generated in %.3f s", Date().timeIntervalSince(began))
        complete = true
        return ShareMedia(url: url, video: true)
    }

    static func brandingImage(width: Int, height: Int) -> CGImage? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            brand(width: CGFloat(width), height: CGFloat(height))
        }.cgImage
    }

    private static func draw(_ image: UIImage, in rect: CGRect) {
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width/2, y: rect.midY - size.height/2, width: size.width, height: size.height))
    }
    private static func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat) {
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black; shadow.shadowBlurRadius = size * 0.15
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: size), .foregroundColor: UIColor.white, .shadow: shadow])
    }
    private static func brand(width: CGFloat, height: CGFloat) {
        let size = max(8, min(width, height) * 0.035)
        let x = width * 0.025, y = height - size * 1.5
        UIImage(named: "ShareLogo")?.draw(in: CGRect(x: x, y: y, width: size, height: size))
        label("AquaRestore", x: x + size * 1.25, y: y + size * 0.1, size: size * 0.7)
    }
    private static func render(_ size: CGSize, drawing: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 12/255, green: 23/255, blue: 31/255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size)); drawing(context.cgContext)
        }
    }
    private static func collage(_ before: UIImage, _ after: UIImage) -> UIImage {
        let side = before.size.height > before.size.width
        let rawW = before.size.width * (side ? 2 : 1), rawH = before.size.height * (side ? 1 : 2)
        let width = side ? max(rawW, rawH) : rawW, height = side ? rawH : max(rawH, rawW + 1)
        let scale = min(1, 2560 / max(width, height)); let w = floor(width * scale), h = floor(height * scale)
        return render(CGSize(width: w, height: h)) { _ in
            let first = CGRect(x: 0, y: 0, width: side ? w/2 : w, height: side ? h : h/2)
            let second = CGRect(x: side ? w/2 : 0, y: side ? 0 : h/2, width: first.width, height: first.height)
            draw(before, in: first); draw(after, in: second)
            label("Original", x: w * 0.025, y: h * 0.025, size: min(w,h) * 0.035)
            label("Restored", x: second.minX + w * 0.025, y: second.minY + h * 0.025, size: min(w,h) * 0.035)
            brand(width: w, height: h)
        }
    }
    private static func encode(_ url: URL, width: Int, height: Int, duration: Int64, flag: CancelFlag,
                               frame: (CVPixelBuffer, Double) throws -> Void) async throws {
        guard duration > 0 else { throw MediaProblem("exportFailed") }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(500_000, width * height * 4), AVVideoExpectedSourceFrameRateKey: 30, AVVideoAllowFrameReorderingKey: false]])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()])
        guard writer.canAdd(input) else { throw MediaProblem("exportFailed") }
        writer.add(input); guard writer.startWriting() else { throw writer.error ?? MediaProblem("exportFailed") }
        writer.startSession(atSourceTime: .zero)
        let deadline = Date().addingTimeInterval(60)
        let count = max(1, Int(duration * 30 / 1000))
        for index in 0..<count {
            while !input.isReadyForMoreMediaData {
                if flag.isSet { throw CancellationError() }
                guard Date() < deadline else { throw MediaProblem("exportFailed") }
                guard writer.status == .writing else { throw writer.error ?? MediaProblem("exportFailed") }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            if flag.isSet { throw CancellationError() }
            guard Date() < deadline else { throw MediaProblem("exportFailed") }
            try autoreleasepool {
                var pixel: CVPixelBuffer?
                guard let pool = adapter.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else { throw MediaProblem("memory") }
                try frame(pixel, Double(index) / Double(max(1, count - 1)))
                guard adapter.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else { throw writer.error ?? MediaProblem("exportFailed") }
            }
        }
        input.markAsFinished(); writer.endSession(atSourceTime: CMTime(value: duration, timescale: 1000))
        let finished = CancelFlag()
        writer.finishWriting { finished.set() }
        while !finished.isSet {
            if flag.isSet { throw CancellationError() }
            guard Date() < deadline else { throw MediaProblem("exportFailed") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard writer.status == .completed else { throw writer.error ?? MediaProblem("exportFailed") }
    }
}

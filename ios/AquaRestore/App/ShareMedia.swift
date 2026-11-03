import AVFoundation
import UIKit

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

    static func make(_ request: ExportRequest, restored: URL) async -> [ShareMedia] {
        guard request.source.width >= 2, request.source.height >= 2 else { return [] }
        let flag = CancelFlag()
        return await withTaskCancellationHandler {
            await Task.detached(priority: .utility) {
                var result: [ShareMedia] = []
                var pending: URL?
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    if !request.source.video {
                        let o = ExportRecommendation.photo(width: request.source.width, height: request.source.height,
                                                           pngSource: request.source.url.pathExtension.lowercased() == "png")
                        let before = try MediaIO.bitmap(request.source.url, edge: o.original ? 0 : o.longEdge)
                        let after = try MediaIO.gradeBitmap(before, request.grade, cancelled: { flag.isSet })
                        guard let b = before.cgImage, let a = after.cgImage else { throw MediaProblem("photoUnreadable") }
                        let first = UIImage(cgImage: b), second = UIImage(cgImage: a)
                        let collageURL = root.appendingPathComponent("\(UUID().uuidString).\(o.png ? "png" : "jpg")")
                        pending = collageURL
                        let image = collage(first, second)
                        guard let data = o.png ? image.pngData() : image.jpegData(compressionQuality: CGFloat(o.quality) / 100) else { throw MediaProblem("exportFailed") }
                        try data.write(to: collageURL)
                        result.append(ShareMedia(url: collageURL, video: false)); pending = nil
                        let (w, h) = SharingPlan.videoSize(b.width, b.height)
                        let url = root.appendingPathComponent("\(UUID().uuidString).mp4"); pending = url
                        try await encode(url, width: w, height: h, duration: 6000, flag: flag) { _, fraction in
                            reveal(first, second, width: w, height: h, fraction: fraction)
                        }
                        result.insert(ShareMedia(url: url, video: true), at: 0); pending = nil
                    } else {
                        let restoredSource = try await MediaIO.inspect(restored)
                        let (start, length) = SharingPlan.clip(restoredSource.durationMs)
                        let (w, h) = SharingPlan.videoSize(min(request.source.width, restoredSource.width), min(request.source.height, restoredSource.height))
                        let b = AVAssetImageGenerator(asset: AVURLAsset(url: request.source.url))
                        let a = AVAssetImageGenerator(asset: AVURLAsset(url: restored))
                        for generator in [b, a] {
                            generator.appliesPreferredTrackTransform = true
                            generator.maximumSize = CGSize(width: w, height: h)
                            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
                        }
                        let url = root.appendingPathComponent("\(UUID().uuidString).mp4"); pending = url
                        try await encode(url, width: w, height: h, duration: length, flag: flag) { ms, fraction in
                            let t = start + ms
                            let sourceTime = request.options.startMs + Int64(Double(t) * Double(request.options.speed))
                            let before = try b.copyCGImage(at: CMTime(value: sourceTime, timescale: 1000), actualTime: nil)
                            let after = try a.copyCGImage(at: CMTime(value: t, timescale: 1000), actualTime: nil)
                            return reveal(UIImage(cgImage: before), UIImage(cgImage: after), width: w, height: h, fraction: fraction)
                        }
                        result.append(ShareMedia(url: url, video: true)); pending = nil
                    }
                } catch {
                    if let pending { try? FileManager.default.removeItem(at: pending) }
                    if flag.isSet { remove(result); return [] }
                    NSLog("AquaRestore: comparison preview unavailable: \(error)")
                }
                return result
            }.value
        } onCancel: { flag.set() }
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
    private static func reveal(_ before: UIImage, _ after: UIImage, width: Int, height: Int, fraction: Double) -> UIImage {
        let w = CGFloat(width), h = CGFloat(height), progress = CGFloat(min(1, max(0, (fraction - 0.25) / 0.5)))
        return render(CGSize(width: w, height: h)) { context in
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            draw(before, in: rect)
            context.saveGState(); context.clip(to: CGRect(x: 0, y: 0, width: w * progress, height: h)); draw(after, in: rect); context.restoreGState()
            if progress > 0 && progress < 1 {
                context.setStrokeColor(UIColor.white.cgColor); context.setLineWidth(max(1, w/400))
                context.move(to: CGPoint(x: w * progress, y: 0)); context.addLine(to: CGPoint(x: w * progress, y: h)); context.strokePath()
            }
            let size = min(w,h) * 0.04
            if progress < 1 { label("Original", x: w * 0.025, y: h * 0.025, size: size) }
            if progress > 0.3 { label("Restored", x: w * 0.025, y: h * 0.10, size: size) }
            brand(width: w, height: h)
        }
    }
    private static func encode(_ url: URL, width: Int, height: Int, duration: Int64, flag: CancelFlag,
                               frame: (Int64, Double) throws -> UIImage) async throws {
        guard duration > 0 else { throw MediaProblem("exportFailed") }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(500_000, width * height * 4)]])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        guard writer.canAdd(input) else { throw MediaProblem("exportFailed") }
        writer.add(input); guard writer.startWriting() else { throw writer.error ?? MediaProblem("exportFailed") }
        writer.startSession(atSourceTime: .zero)
        let deadline = Date().addingTimeInterval(60)
        let count = max(1, Int(duration * 24 / 1000))
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
                let image = try frame(Int64(index) * 1000 / 24, Double(index) / Double(max(1, count - 1)))
                var pixel: CVPixelBuffer?
                guard let pool = adapter.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else { throw MediaProblem("memory") }
                do {
                    CVPixelBufferLockBaseAddress(pixel, []); defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
                    guard let cg = image.cgImage, let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { throw MediaProblem("exportFailed") }
                    context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                }
                guard adapter.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 24)) else { throw writer.error ?? MediaProblem("exportFailed") }
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

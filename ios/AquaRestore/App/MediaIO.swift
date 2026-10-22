import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct MediaProblem: Error { let key: String; init(_ key: String) { self.key = key } }

struct SourceMedia: Equatable {
    let url: URL
    let name: String
    let video: Bool
    let width: Int
    let height: Int
    var durationMs: Int64 = 0
    var fps: Float = 30
    var bitrate: Int = 0
    var codec: String = ""
    var hdr: HdrMode = .sdr
    var audioBitrate: Int = 0

    var isHdr: Bool { hdr != .sdr }
    var hdrName: String { hdr == .hlg ? "HLG" : "HDR10 / PQ" }
}

/// Decoded pixels as 0xAARRGGBB, the layout `ColorGrade` and `AutoGrade` work on.
final class PixelImage {
    let width: Int
    let height: Int
    let pixels: [UInt32]
    init(width: Int, height: Int, pixels: [UInt32]) { self.width = width; self.height = height; self.pixels = pixels }

    private static let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    convenience init?(_ image: CGImage) {
        let w = image.width, h = image.height
        var pixels = [UInt32](repeating: 0, count: w * h)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: PixelImage.space, bitmapInfo: PixelImage.bitmapInfo) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        self.init(width: w, height: h, pixels: pixels)
    }

    var cgImage: CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) } as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: PixelImage.space, bitmapInfo: CGBitmapInfo(rawValue: PixelImage.bitmapInfo), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

enum MediaIO {
    static func isVideo(_ url: URL) -> Bool {
        (UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .movie)) ?? false
    }

    static func inspect(_ url: URL) async throws -> SourceMedia {
        let name = url.lastPathComponent.isEmpty ? "Underwater" : url.lastPathComponent
        if !isVideo(url) {
            let (w, h) = try imageSize(url)
            return SourceMedia(url: url, name: name, video: false, width: w, height: h)
        }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaProblem("unsupported") }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let (natural, transform, nominal, rate, formats) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .formatDescriptions)
        let duration = try await asset.load(.duration)
        var audioRate = 0
        for audio in audioTracks {
            let r = Int(try await audio.load(.estimatedDataRate))
            audioRate += r > 0 ? r : 192_000
        }
        let display = GradeInstruction.displaySize(natural, transform)
        guard display.width >= 1, display.height >= 1 else { throw MediaProblem("unsupported") }

        var codec = ""
        var hdr = HdrMode.sdr
        if let format = formats.first {
            codec = fourCC(CMFormatDescriptionGetMediaSubType(format))
            // Profile 5 Dolby Vision has no HDR10 / HLG base layer; the compatible profiles (such as the
            // iPhone's) are stored as HEVC and graded from that base layer.
            if codec == "dvh1" || codec == "dvhe" { throw MediaProblem("dolbyVision") }
            let transfer = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
            if transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String { hdr = .hlg }
            else if transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String { hdr = .pq }
        }
        return SourceMedia(url: url, name: name, video: true, width: Int(display.width.rounded()), height: Int(display.height.rounded()),
                           durationMs: duration.isNumeric ? Int64((duration.seconds * 1000).rounded()) : 0,
                           fps: nominal.isFinite && nominal > 0 ? nominal : 30, bitrate: Int(rate), codec: codec, hdr: hdr, audioBitrate: audioRate)
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)], encoding: .ascii) ?? ""
    }

    private static func imageSize(_ url: URL) throws -> (Int, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
        else { throw MediaProblem("unsupported") }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? (h, w) : (w, h)
    }

    /// Decodes an upright sRGB bitmap with its long edge at most `edge` (0 = full size).
    static func bitmap(_ url: URL, edge: Int) throws -> PixelImage {
        let (width, height) = try imageSize(url)
        let (w, h) = ExportSizing.dimensions(width, height, edge)
        if UInt64(w) * UInt64(h) * 8 > Platform.physicalMemory / 4 { throw MediaProblem("memory") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: max(w, h),
              ] as CFDictionary),
              let pixels = PixelImage(image) else { throw MediaProblem("unsupported") }
        return pixels
    }

    static func analyze(_ source: SourceMedia) async throws -> Analysis {
        var frames: [[UInt32]] = []
        if source.video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 192, height: 192)
            // The nearest keyframe is enough for statistics and avoids decoding long GOPs.
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            for fraction in [0.05, 0.23, 0.41, 0.59, 0.77, 0.95] {
                try Task.checkCancellation()
                let time = CMTime(seconds: Double(source.durationMs) / 1000 * fraction, preferredTimescale: 600)
                guard let result = try? await generator.image(at: time), let pixels = PixelImage(result.image) else { continue }
                frames.append(pixels.pixels)
            }
        } else if let image = try? bitmap(source.url, edge: 192) {
            frames.append(image.pixels)
        }
        if frames.isEmpty { throw MediaProblem("analysisFailed") }
        return AutoGrade.analyze(frames, hdr: source.isHdr)
    }

    /// One frame near the middle of each of `count` equal slots, for the trim bar.
    static func filmstrip(_ url: URL, durationMs: Int64, count: Int, height: Int = 96) async throws -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: height * 16 / 9, height: height)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        var frames: [CGImage] = []
        for i in 0..<count {
            try Task.checkCancellation()
            let ms = Double(durationMs) * Double(2 * i + 1) / Double(2 * count)
            if let result = try? await generator.image(at: CMTime(seconds: ms / 1000, preferredTimescale: 600)) { frames.append(result.image) }
        }
        return frames
    }

    /// Grades every pixel, on all cores. Throws `CancellationError` when `cancelled` turns true.
    static func gradeBitmap(_ image: PixelImage, _ grade: Grade, progress: ((Int) -> Void)? = nil,
                            cancelled: () -> Bool = { false }) throws -> PixelImage {
        let effective = grade.effective()
        let gain = exp2(effective.exposure)
        var out = image.pixels
        let rows = image.height, width = image.width
        // Clarity reads neighbours of the ungraded source, so keep its luma apart from the graded rows.
        let luma = effective.clarity != 0 && effective.strength != 0 ? Clarity.luma(image.pixels) : []
        let radius = Clarity.radius(width, rows)
        let chunk = 32
        let chunks = (rows + chunk - 1) / chunk
        let lock = NSLock()
        var done = 0
        var stopped = false
        out.withUnsafeMutableBufferPointer { buffer in luma.withUnsafeBufferPointer { lumaBuffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: chunks) { index in
                if cancelled() { lock.lock(); stopped = true; lock.unlock(); return }
                for y in (index * chunk)..<min(rows, (index + 1) * chunk) {
                    for x in 0..<width {
                        let detail = lumaBuffer.isEmpty ? 0 : Clarity.detail(lumaBuffer.baseAddress!, width, rows, x, y, radius)
                        base[y * width + x] = ColorGrade.pixel(base[y * width + x], effective, gain, detail)
                    }
                }
                lock.lock(); done += 1; let percent = done * 100 / chunks; lock.unlock()
                progress?(percent)
            }
        } }
        if stopped { throw CancellationError() }
        return PixelImage(width: width, height: rows, pixels: out)
    }

    /// HEVC HDR export needs a 10-bit encoder; A10 and later have one.
    static func requireHdrEncoder(_ source: SourceMedia) throws {
        guard source.isHdr else { return }
        if !AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality) { throw MediaProblem("hdrDevice") }
    }
}

import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct MediaProblem: Error { let key: String; init(_ key: String) { self.key = key } }

struct SourceMedia: Equatable {
    var url: URL
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
    /// The longest edge the size samples are cut from. A larger photo is sampled at this scale, which keeps the picture
    /// the samples come from within a safe amount of memory.
    private static let sizeSampleEdge = 4096

    /// Graded patches from a 3×3 grid across a photo, at the export's output scale. Encoding them measures how this
    /// photo compresses, which depends on its detail far more than on its resolution.
    static func sizeSamples(_ url: URL, outWidth: Int, outHeight: Int, grade: Grade, cancelled: () -> Bool = { false }) throws -> [PixelImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: min(max(outWidth, outHeight), sizeSampleEdge),
              ] as CFDictionary) else { throw MediaProblem("unsupported") }
        let width = picture.width, height = picture.height
        let tile = max(1, min(320, width / 3, height / 3))
        let radius = Clarity.radius(outWidth, outHeight)
        var samples: [PixelImage] = []
        for i in 0..<9 {
            if cancelled() { throw CancellationError() }
            let left = min(max(Int((Double(i % 3) + 0.5) * Double(width) / 3) - tile / 2, 0), width - tile)
            let top = min(max(Int((Double(i / 3) + 0.5) * Double(height) / 3) - tile / 2, 0), height - tile)
            guard let patch = picture.cropping(to: CGRect(x: left, y: top, width: tile, height: tile)),
                  let pixels = PixelImage(patch) else { continue }
            samples.append(try gradeBitmap(pixels, grade, clarityRadius: radius))
        }
        return samples
    }

    /// Bytes per pixel of `samples` encoded as the export encodes, without each file's fixed headers.
    static func sampleBytesPerPixel(_ samples: [PixelImage], png: Bool, quality: Int) -> Double {
        func size(_ image: CGImage) -> Int {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, (png ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil) else { return 0 }
            let properties = png ? nil : [kCGImageDestinationLossyCompressionQuality: Double(quality) / 100] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
            return CGImageDestinationFinalize(destination) ? data.length : 0
        }
        let blank = PixelImage(width: 8, height: 8, pixels: [UInt32](repeating: 0xFF00_0000, count: 64)).cgImage
        let header = blank.map(size) ?? 0
        var bytes = 0, pixels = 0
        for sample in samples {
            guard let image = sample.cgImage else { continue }
            bytes += max(0, size(image) - header)
            pixels += image.width * image.height
        }
        return pixels > 0 ? Double(bytes) / Double(pixels) : 0
    }

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

    /// Calls `each` with each sampled video analysis frame and its requested time in milliseconds.
    private static func videoFrames(_ source: SourceMedia, _ each: (Int64, CGImage) throws -> Void) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 192, height: 192)
        // The nearest keyframe is enough for statistics and avoids decoding long GOPs.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        #if DEBUG
        NSLog("AquaRestore: Analysis source: \(source.name) \(source.width)x\(source.height) codec=\(source.codec) hdr=\(source.hdr) durationMs=\(source.durationMs) fps=\(source.fps)")
        #endif
        for fraction in [0.05, 0.23, 0.41, 0.59, 0.77, 0.95] {
            try Task.checkCancellation()
            let ms = Int64(Double(source.durationMs) * fraction)
            let time = CMTime(seconds: Double(source.durationMs) / 1000 * fraction, preferredTimescale: 600)
            guard let result = try? await generator.image(at: time) else { continue }
            try each(ms, result.image)
        }
    }

    static func analyze(_ source: SourceMedia) async throws -> Analysis {
        var frames: [[UInt32]] = []
        var described: [String] = []
        if source.video {
            try await videoFrames(source) { ms, image in
                guard let pixels = PixelImage(image) else { return }
                frames.append(pixels.pixels)
                #if DEBUG
                described.append("at \(ms)ms " + describe(pixels))
                #endif
            }
        } else if let image = try? bitmap(source.url, edge: 192) {
            frames.append(image.pixels)
            #if DEBUG
            NSLog("AquaRestore: Analysis source: \(source.name) \(source.width)x\(source.height) photo")
            described.append(describe(image))
            #endif
        }
        if frames.isEmpty { throw MediaProblem("analysisFailed") }
        let analysis = AutoGrade.analyze(frames, hdr: source.isHdr)
        #if DEBUG
        // One line per frame keeps each one readable in the log viewer.
        for (i, line) in described.enumerated() {
            NSLog("AquaRestore: Analysis frame \(i + 1)/\(frames.count) \(line)")
            NSLog("AquaRestore: Analysis frame \(i + 1) alone: \(describe(AutoGrade.analyze([frames[i]], hdr: source.isHdr).grade))")
        }
        NSLog("AquaRestore: Analysis grade: \(describe(analysis.grade))")
        NSLog("AquaRestore: Analysis applied: \(describe(analysis.grade.effective()))")
        NSLog("AquaRestore: Analysis cast=\(analysis.cast) confidence=\(analysis.confidence) redLoss=\(analysis.redLoss)")
        #else
        _ = described
        #endif
        return analysis
    }

    /// Saves a video's analysis frames, exactly as analyzed, to Documents/frames as NN-frame-i.png (for a clip
    /// named NN-original.mp4), replacing earlier ones, so a sample's frames can be taken from the phone with the
    /// Files app. Returns how many were saved.
    static func saveAnalysisFrames(_ source: SourceMedia) async throws -> Int {
        var stem = (source.name as NSString).deletingPathExtension
        if stem.hasSuffix("-original") { stem = String(stem.dropLast("-original".count)) }
        let folder = try DevFiles.folder("frames")
        var index = 0, saved = 0
        try await videoFrames(source) { _, decoded in
            index += 1
            let file = folder.appendingPathComponent("\(stem)-frame-\(index).png")
            try? FileManager.default.removeItem(at: file)
            // The 8-bit sRGB pixels the analysis reads, not the decoder's image, which may be HDR or Display P3.
            guard let image = PixelImage(decoded)?.cgImage,
                  let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image, nil)
            if CGImageDestinationFinalize(destination) {
                saved += 1
                NSLog("AquaRestore: Analysis frame saved: \(DevFiles.shown(file))")
            } else {
                NSLog("AquaRestore: Analysis frame not saved: \(file.lastPathComponent)")
            }
        }
        return saved
    }

    /// An analysis frame for the debug log: size and an 8×8 grid of mean colors, to compare with desktop decodes.
    static func describe(_ image: PixelImage) -> String {
        let cells = 8
        var sums = [Int](repeating: 0, count: cells * cells * 4)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image.pixels[y * image.width + x]
                let c = ((y * cells / image.height) * cells + x * cells / image.width) * 4
                sums[c] += Int((p >> 16) & 255); sums[c + 1] += Int((p >> 8) & 255); sums[c + 2] += Int(p & 255); sums[c + 3] += 1
            }
        }
        let grid = (0..<cells * cells).map { i -> String in
            let n = max(1, sums[i * 4 + 3])
            return String(format: "%02x%02x%02x", sums[i * 4] / n, sums[i * 4 + 1] / n, sums[i * 4 + 2] / n)
        }.joined()
        return "\(image.width)x\(image.height) grid=\(grid)"
    }

    static func describe(_ g: Grade) -> String {
        let values: [(String, Float)] = [("strength", g.strength), ("red", g.red), ("temperature", g.temperature), ("tint", g.tint),
            ("exposure", g.exposure), ("haze", g.haze), ("contrast", g.contrast), ("saturation", g.saturation), ("shadows", g.shadows),
            ("levels", g.levels), ("blackR", g.blackR), ("blackG", g.blackG), ("blackB", g.blackB), ("whiteR", g.whiteR),
            ("whiteG", g.whiteG), ("whiteB", g.whiteB), ("coolProtection", g.coolProtection), ("clarity", g.clarity)]
        return values.map { "\($0.0)=" + String(format: "%.4f", $0.1) }.joined(separator: " ")
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
    static func gradeBitmap(_ image: PixelImage, _ grade: Grade, clarityRadius: Int? = nil, progress: ((Int) -> Void)? = nil,
                            cancelled: () -> Bool = { false }) throws -> PixelImage {
        let effective = grade.effective()
        let gain = exp2(effective.exposure)
        var out = image.pixels
        let rows = image.height, width = image.width
        // Clarity reads neighbours of the ungraded source, so keep its luma apart from the graded rows.
        let luma = effective.clarity != 0 && effective.strength != 0 ? Clarity.luma(image.pixels) : []
        let radius = clarityRadius ?? Clarity.radius(width, rows)
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

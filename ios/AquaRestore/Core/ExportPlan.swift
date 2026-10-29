import Foundation

func exportFileName(sourceName: String, extension ext: String) -> String {
    let name = sourceName.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let stem = (trimmed as NSString).deletingPathExtension
    return "AquaRestore_\(stem.isEmpty ? "Underwater" : stem).\(ext)"
}

struct ExportOptions: Equatable {
    /// Original keeps full quality: JPEG at the encoder's maximum, PNG lossless.
    static let originalJpegQuality = 100

    var original = true
    var longEdge = 1920 // 0 = source dimensions
    var fps = 0 // 0 = original timestamps; other values cap, never invent frames
    var quality = 90
    var png = false
    var speed: Float = 1
    var startMs: Int64 = 0 // video trim in source time
    var endMs: Int64 = 0 // 0 = to the end

    func trimmedMs(_ durationMs: Int64) -> Int64 {
        max((endMs > 0 ? min(endMs, durationMs) : durationMs) - startMs, 0)
    }
}

enum ExportSizing {
    static func dimensions(_ width: Int, _ height: Int, _ longEdge: Int, even: Bool = false) -> (Int, Int) {
        precondition(width > 0 && height > 0)
        let scale = longEdge <= 0 ? 1.0 : min(1.0, Double(longEdge) / Double(max(width, height)))
        func size(_ v: Int) -> Int {
            let n = max(1, Int((Double(v) * scale).rounded()))
            return even ? max(2, n / 2 * 2) : n
        }
        return (size(width), size(height))
    }

    /// `sourcePixelRate` is the source's width × height × fps, used to scale `source` to the output.
    static func bitrate(_ width: Int, _ height: Int, _ fps: Float, _ quality: Int, _ source: Int, _ original: Bool, _ sourcePixelRate: Double = 0) -> Int {
        // Prefer the measured source rate; only estimate when metadata is unavailable.
        if original && source > 0 { return source }
        let q = Double(min(max(quality, 1), 100)) / 100
        let f = Double(min(max(fps, 1), 240))
        if source > 0 && sourcePixelRate > 0 {
            // 100% at source size and frame rate equals Original. Smaller outputs need more bits per pixel,
            // so the rate falls slower than the pixel count; it never exceeds the source. The floor guards
            // heavy downscales but stays below the quality share, so the slider always has an effect.
            let ratio = min(max(Double(width) * Double(height) * f / sourcePixelRate, 0), 1)
            let value = Double(source) * pow(ratio, 0.75) * q
            let floor = min(500_000.0, Double(source) * q)
            return Int(min(max(value, floor), Double(source)).rounded())
        }
        let value = Double(width) * Double(height) * f * (0.05 + q * 0.2)
        return Int(min(max(value, 500_000), Double(Int32.max)).rounded())
    }
}

/// Shared by the export pipeline and its size preview. Decimal MB/GB match the UI.
struct VideoExportPlan: Equatable { let bitrate: Int; let estimatedBytes: Int64? }

/// A rough encoded size from output pixels, format and JPEG quality. Image detail changes compression substantially.
func photoEstimatedBytes(width: Int, height: Int, options: ExportOptions) -> Int64 {
    let (w, h) = ExportSizing.dimensions(width, height, options.original ? 0 : options.longEdge)
    // The encoder scales its quantization tables by this percentage, and size follows the scale, not the
    // quality number: it rises steeply only near 100. Fitted to measured exports of graded photos.
    let quality = min(max(options.quality, 1), 100)
    let scale = quality < 50 ? 5000 / Double(quality) : 200 - 2 * Double(quality)
    let bytesPerPixel = options.png ? 2.5 : 1.82 * pow(scale + 5, -0.68)
    return max(1, Int64((Double(w) * Double(h) * bytesPerPixel).rounded()))
}

func videoExportPlan(width: Int, height: Int, fps: Float, sourceBitrate: Int, audioBitrate: Int,
                     durationMs: Int64, options: ExportOptions, mixedAudio: Bool = false) -> VideoExportPlan {
    let (w, h) = ExportSizing.dimensions(width, height, options.original ? 0 : options.longEdge)
    // Faster playback drops frames to stay at the source rate; slower playback spreads them out.
    let effectiveFps = fps * min(options.speed, 1)
    let outputFps = options.original || options.fps == 0 ? effectiveFps : min(effectiveFps, Float(options.fps))
    let sourceRate = Int(min(max(Double(sourceBitrate) * Double(min(options.speed, 1)), 0), Double(Int32.max)))
    let rate = ExportSizing.bitrate(w, h, outputFps, options.original ? 100 : options.quality, sourceRate, options.original,
                                    Double(width) * Double(height) * Double(min(max(effectiveFps, 1), 240)))
    // Audio is transcoded on speed changes and when mixing or changing volume. Use a conservative estimate then.
    let audioRate = mixedAudio ? max(audioBitrate, 192_000)
        : (audioBitrate > 0 && options.speed != 1 ? max(audioBitrate, 192_000) : audioBitrate)
    let length = options.trimmedMs(durationMs)
    let bytes: Int64? = length > 0 ? Int64((Double(rate) + Double(audioRate)) * Double(length) / Double(options.speed) / 8000 * 1.01) : nil
    return VideoExportPlan(bitrate: rate, estimatedBytes: bytes)
}

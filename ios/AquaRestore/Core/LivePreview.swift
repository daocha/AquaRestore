import Foundation

/// A preview that fails gets one fresh start, because what stopped it (another pipeline holding the decoder, the phone
/// resetting its media service) usually passes. Failing again soon after means it will not play here, so that is reported.
struct PlaybackRetry {
    static let windowSeconds = 30.0
    private var last: Date?

    mutating func allowed(now: Date = Date()) -> Bool {
        if let last, now.timeIntervalSince(last) < Self.windowSeconds { return false }
        last = now
        return true
    }
}

/// How the preview plays a video: the original, shrunk as it plays so it never grades above `maxEdge`, or a copy.
enum LivePreview: Equatable {
    case original, copy

    /// The largest long edge the preview grades at on every device, as on Android, and the size of the preview copy.
    /// On a phone screen this looks the same outside of zooming in, and it saves memory, heat and battery.
    static let maxEdge = 1920

    /// Up to 4K at 60 fps of pixels per second plays the original without measuring, as on Android.
    static func withinLimit(width: Int, height: Int, fps: Float) -> Bool {
        Double(width) * Double(height) * Double(fps) <= 3840.0 * 2160 * 61
    }

    /// About what one video being decoded and graded holds: 11 full-size frames, half-float for HDR. The preview of a 4K
    /// HDR video used 715 to 928 MB on an iPhone SE (3rd generation).
    static func pipelineMemory(width: Int, height: Int, hdr: Bool) -> UInt64 {
        UInt64(width) * UInt64(height) * (hdr ? 8 : 4) * 11
    }

    /// Whether a paused preview gives up its decoder and memory for an export. With the preview, the export and the
    /// comparison all open on a 4K HDR video, an iPhone SE (3rd generation) had its media service reset within seconds;
    /// without the preview the export finished. This asks whether three pipelines fit. It is checked before the preview's
    /// own use counts against it too, and asking what is free rather than which model it is lets larger iPhones keep the
    /// preview. Zero, where the system reports nothing, counts as no room.
    static func previewYields(width: Int, height: Int, hdr: Bool, availableMemory: UInt64) -> Bool {
        availableMemory < pipelineMemory(width: width, height: height, hdr: hdr) * 3
    }

    /// How long the compositor can go without being asked for a frame before playback counts as stuck. Above normal speed
    /// the decoder can fall behind for a while without being stuck, so it gets longer.
    static func stallSeconds(speed: Float) -> Double { speed > 1 ? 3 : 1.2 }

    /// iOS declares no decoder limits, so a heavier video is judged by how fast a sample of it decoded: the decoder still
    /// reads every full-size frame, so a copy is for one that cannot keep up. If the sample could not be measured, the
    /// original still plays.
    static func decide(fps: Float, measuredDecodeFps: Double?) -> LivePreview {
        guard let measured = measuredDecodeFps else { return .original }
        return measured >= Double(fps) * 1.2 ? .original : .copy
    }
}

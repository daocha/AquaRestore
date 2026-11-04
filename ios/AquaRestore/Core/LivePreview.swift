import Foundation

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

    /// Whether a comparison of a video heavier than 4K60 waits for its export to succeed. Up to a 3840px long edge it runs
    /// alongside the export, so the result is not held up. Larger frames need room for a second decoder: asking what is
    /// free rather than which model it is means later iPhones need no changes. The figures are estimates. Zero, where
    /// the system reports nothing, counts as no room.
    static func comparisonWaits(width: Int, height: Int, availableMemory: UInt64) -> Bool {
        max(width, height) > 3840 && availableMemory < max(2_500 * 1_048_576, UInt64(width) * UInt64(height) * 200)
    }

    /// iOS declares no decoder limits, so a heavier video is judged by how fast a sample of it decoded: the decoder still
    /// reads every full-size frame, so a copy is for one that cannot keep up. If the sample could not be measured, the
    /// original still plays.
    static func decide(fps: Float, measuredDecodeFps: Double?) -> LivePreview {
        guard let measured = measuredDecodeFps else { return .original }
        return measured >= Double(fps) * 1.2 ? .original : .copy
    }
}

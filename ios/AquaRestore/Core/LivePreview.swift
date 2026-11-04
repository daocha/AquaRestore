import Foundation

/// How the preview plays a video: the original with full-size grading, the original with lighter grading, or a copy.
enum LivePreview: Equatable {
    case full, reduced, copy

    /// Matches the preview copy, and the size Android grades at when it needs this.
    static let reducedEdge = 1920

    /// Up to 4K at 60 fps of pixels per second plays at full size without measuring, as on Android.
    static func withinLimit(width: Int, height: Int, fps: Float) -> Bool {
        Double(width) * Double(height) * Double(fps) <= 3840.0 * 2160 * 61
    }

    /// iOS declares no decoder limits, so a heavier video is judged by how fast a sample of it decoded. It never grades
    /// at full size: frames that large in the preview, on top of an export, ran an iPhone SE out of memory. If the sample
    /// could not be measured, the original still plays.
    static func decide(fps: Float, measuredDecodeFps: Double?) -> LivePreview {
        guard let measured = measuredDecodeFps else { return .reduced }
        return measured >= Double(fps) * 1.2 ? .reduced : .copy
    }
}

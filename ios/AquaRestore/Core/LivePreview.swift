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

    /// Whether this phone has the memory right now for a full-size preview of a video heavier than 4K60. Asks what is free
    /// rather than which model it is, so later iPhones need no changes. On an iPhone SE 3 with 4 GB, a full-size preview of
    /// 3840x3360 at 60 fps did not play smoothly and crashed with an export and comparison running. The figures are
    /// estimates, meant to exclude 4 GB phones. Zero, where the system reports nothing, counts as no room.
    static func hasRoom(width: Int, height: Int, availableMemory: UInt64 = AppLog.availableMemory) -> Bool {
        availableMemory >= max(2_500 * 1_048_576, UInt64(width) * UInt64(height) * 200)
    }

    /// Whether a comparison of a video heavier than 4K60 waits for its export to succeed. Up to a 3840px long edge it runs
    /// alongside the export, so the result is not held up. Larger frames need the room for a second decoder.
    static func comparisonWaits(width: Int, height: Int, availableMemory: UInt64 = AppLog.availableMemory) -> Bool {
        max(width, height) > 3840 && !hasRoom(width: width, height: height, availableMemory: availableMemory)
    }

    /// iOS declares no decoder limits, so a heavier video is judged by how fast a sample of it decoded. Full size also
    /// needs the memory. If the sample could not be measured, the original still plays, graded smaller.
    static func decide(fps: Float, measuredDecodeFps: Double?, hasRoom: Bool) -> LivePreview {
        guard let measured = measuredDecodeFps else { return .reduced }
        if hasRoom && measured >= Double(fps) * 2 { return .full }
        return measured >= Double(fps) * 1.2 ? .reduced : .copy
    }
}

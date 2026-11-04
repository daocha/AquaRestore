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

    /// Whether this phone has the memory right now to treat a video heavier than 4K60 as lighter ones: a full-size preview,
    /// and a comparison alongside the export. Asks what is free rather than which model it is, so later iPhones need no
    /// changes. Doing both ran an iPhone SE with 4 GB out of memory. The figures are estimates, meant to exclude 4 GB
    /// phones. Zero, where the system reports nothing, counts as no room.
    static func hasRoom(width: Int, height: Int, availableMemory: UInt64 = AppLog.availableMemory) -> Bool {
        true // TEST BUILD ONLY: never merge. Always runs the comparison alongside the export.
    }

    /// iOS declares no decoder limits, so a heavier video is judged by how fast a sample of it decoded. Full size also
    /// needs the memory. If the sample could not be measured, the original still plays, graded smaller.
    static func decide(fps: Float, measuredDecodeFps: Double?, hasRoom: Bool) -> LivePreview {
        .full // TEST BUILD ONLY: never merge. Always previews at full size, however fast the decoder is.
    }
}

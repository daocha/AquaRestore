import Foundation

enum SharingPlan {
    static func videoSize(_ width: Int, _ height: Int) -> (Int, Int) {
        let scale = min(1.0, min(1280.0 / Double(max(width, height)), 720.0 / Double(min(width, height))))
        return (max(2, Int(Double(width) * scale) / 2 * 2), max(2, Int(Double(height) * scale) / 2 * 2))
    }
    static func clip(_ durationMs: Int64) -> (start: Int64, length: Int64) {
        let length = min(10_000, durationMs)
        return ((durationMs - length) / 2, length)
    }
    static func eligible(videos: Int, photos: Int) -> Bool { videos >= 5 || photos >= 10 }
}

import Foundation

/// iOS pauses export while AquaRestore is in the background, so a batch only runs while the app stays open.
/// The limits keep a batch short enough to wait for: photos take seconds each, videos minutes.
enum BatchLimits {
    static let photos = 30
    static let videos = 5
    /// Headroom left on the device, so a batch never fills it to the last byte.
    static let spaceMargin: Int64 = 200_000_000
}

struct BatchFailure: Equatable {
    let name: String
    let error: String
}

struct BatchExportStatus: Equatable {
    let total: Int
    var saved = 0
    var failures: [BatchFailure] = []
    var currentName: String?
    var videos = false
    var completed: Int { saved + failures.count }

    func progressText(_ s: Strings) -> String {
        let current = min(completed + 1, total)
        return (videos ? s.text("Video \(current) of \(total)", "第 \(current)／\(total) 段影片")
                : s.text("Photo \(current) of \(total)", "第 \(current)／\(total) 張")) + (currentName.map { " · \($0)" } ?? "")
    }

    func resultText(_ s: Strings) -> String {
        let remaining = total - completed
        var text = videos ? s.text("\(saved) of \(total) videos saved to your Photos library.", "已將 \(saved)／\(total) 段影片儲存至相簿。")
            : s.text("\(saved) of \(total) photos saved to your Photos library.", "已將 \(saved)／\(total) 張照片儲存至相簿。")
        if !failures.isEmpty {
            text += videos ? s.text("\n\(failures.count) failed.", "\n\(failures.count) 段失敗。") : s.text("\n\(failures.count) failed.", "\n\(failures.count) 張失敗。")
        }
        if remaining > 0 {
            text += videos ? s.text("\n\(remaining) not processed. Completed videos are kept.", "\n\(remaining) 段未處理。已完成的影片會保留。")
                : s.text("\n\(remaining) not processed. Completed photos are kept.", "\n\(remaining) 張未處理。已完成的照片會保留。")
        }
        return text
    }
}

/// Storage a batch of videos of these estimated sizes needs: every finished video stays in Photos, and the one
/// being exported is written to a temporary file first and then copied in, so it briefly takes twice its size.
func batchVideoSpace(_ sizes: [Int64]) -> Int64 { sizes.reduce(0, +) + (sizes.max() ?? 0) + BatchLimits.spaceMargin }

func batchSizeText(_ bytes: Int64) -> String {
    bytes >= 1_000_000_000 ? String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
        : bytes >= 1_000_000 ? String(format: "%.1f MB", Double(bytes) / 1_000_000)
        : String(format: "%.0f KB", Double(bytes) / 1_000)
}

func batchDurationText(_ ms: Int64) -> String {
    let seconds = (ms + 500) / 1000
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        : String(format: "%d:%02d", seconds / 60, seconds % 60)
}

import SwiftUI

private struct StringsKey: EnvironmentKey { static let defaultValue = Strings(chinese: false) }
private struct CompactKey: EnvironmentKey { static let defaultValue = false }
private struct ScreenHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 800 }

extension EnvironmentValues {
    var strings: Strings {
        get { self[StringsKey.self] }
        set { self[StringsKey.self] = newValue }
    }
    /// Landscape phones: tighter spacing, like the Android layout below 500dp tall.
    var compact: Bool {
        get { self[CompactKey.self] }
        set { self[CompactKey.self] = newValue }
    }
    var screenHeight: CGFloat {
        get { self[ScreenHeightKey.self] }
        set { self[ScreenHeightKey.self] = newValue }
    }
}

/// Media3's `Util.getStringForTime`: "mm:ss", or "h:mm:ss" from an hour.
func playerTime(_ ms: Int64) -> String {
    let total = (max(ms, 0) + 500) / 1000
    let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
}

/// Media3's own strings follow the system language, not the app's language setting.
var systemChinese: Bool { (Locale.preferredLanguages.first ?? "").hasPrefix("zh") }

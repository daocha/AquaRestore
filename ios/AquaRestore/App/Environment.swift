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

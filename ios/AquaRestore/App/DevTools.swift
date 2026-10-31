import Foundation

/// Hidden developer tools, as on Android: unlocked by tapping the version in Settings ten times, and on until
/// the next install or update, or until switched off. For now they only show Batch restore videos.
@MainActor
final class DevTools: ObservableObject {
    static let shared = DevTools()
    static let unlockTaps = 10
    private static let key = "dev_tools_install"

    @Published private(set) var enabled: Bool

    private init() { enabled = UserDefaults.standard.object(forKey: Self.key) as? Double == Self.installed }

    /// Changes with every install or update, including debug builds, whose version numbers stay fixed.
    private static var installed: Double {
        let path = Bundle.main.executablePath ?? Bundle.main.bundlePath
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return (date ?? .distantPast).timeIntervalSince1970
    }

    func enable() { UserDefaults.standard.set(Self.installed, forKey: Self.key); enabled = true }
    func disable() { UserDefaults.standard.removeObject(forKey: Self.key); enabled = false }

    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "AquaRestore \(name) (\(build))"
    }
}

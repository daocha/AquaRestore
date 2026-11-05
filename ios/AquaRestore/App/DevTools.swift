import Foundation

/// Hidden developer tools, as on Android: unlocked by tapping the version in Settings ten times, and on until
/// the next install or update, or until switched off. For now they only show Batch restore videos.
@MainActor
final class DevTools: ObservableObject {
    static let shared = DevTools()
    static let unlockTaps = 10
    private static let key = "dev_tools_install"

    @Published private(set) var enabled: Bool

    private init() {
        enabled = UserDefaults.standard.string(forKey: Self.key) == Self.installed
        Self.apply(enabled)
    }

    /// The log, and the frame pictures saved beside it, follow these tools.
    private static func apply(_ on: Bool) {
        AppLog.enabled = on
        FrameProbe.enabled = on
    }

    /// Changes with every install or update, including debug builds, whose version numbers stay fixed: iOS puts
    /// each installation in a new container, so the app's path changes. A file's date would not change when the
    /// same build is installed again.
    private static var installed: String { Bundle.main.bundlePath }

    func enable() { UserDefaults.standard.set(Self.installed, forKey: Self.key); enabled = true; Self.apply(true) }
    func disable() { UserDefaults.standard.removeObject(forKey: Self.key); enabled = false; Self.apply(false) }

    nonisolated static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "AquaRestore \(name) (\(build))"
    }
}

/// Where developer tools save files: the app's Documents folder, shown by the Files app as
/// On My iPhone › AquaRestore, in separate folders so they can be copied off the phone.
enum DevFiles {
    static var root: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The file as the Files app shows it.
    static func shown(_ file: URL) -> String {
        let relative = file.path.hasPrefix(root.path) ? String(file.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : file.lastPathComponent
        return (["On My iPhone", "AquaRestore"] + relative.split(separator: "/").map(String.init)).joined(separator: " › ")
    }
}

/// This app's own log lines: everything it logged since it started and in the run before, or since the last Clear.
enum DevLog {
    /// Sharing and the clipboard pass text through the system, which slows down badly with very large text.
    static let shareLimit = 400_000
    /// Removes the log files, including what the last run left.
    static func clear() { AppLog.clear() }

    static func read() async -> String {
        await Task.detached(priority: .userInitiated) { AppLog.read() }.value
    }

    static var header: String {
        "\(DevTools.version) · \(machine) · \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"
    }

    /// The hardware model, such as iPhone15,2.
    static var machine: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// The end of the log, short enough to share or copy.
    static func shareable(_ log: String) -> String { header + String(log.suffix(shareLimit)) }

    /// Saves the whole log (no share limit) to Documents/logs, and returns where it went, or nil on failure.
    static func save(_ log: String? = nil) async -> String? {
        let text: String
        if let log { text = log } else { text = await read() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        do {
            let file = try DevFiles.folder("logs").appendingPathComponent("AquaRestore-log-\(formatter.string(from: Date())).txt")
            try (header + text).write(to: file, atomically: true, encoding: .utf8)
            return DevFiles.shown(file)
        } catch {
            NSLog("AquaRestore: log not saved: \(error)")
            return nil
        }
    }
}

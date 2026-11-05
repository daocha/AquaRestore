import Foundation
import os

/// Every `NSLog` in this module also goes to `AppLog`, without changing the places that log. Only the finished message
/// is passed on, so a stray percent sign in a file name or error cannot be read as a format specifier. The parameters have
/// to match Foundation's exactly, or calls to this become ambiguous. While developer tools are off nothing is written.
func NSLog(_ format: String, _ arguments: CVarArg...) {
    guard AppLog.enabled else { return }
    let message = arguments.isEmpty ? format : String(format: format, arguments: arguments)
    AppLog.write(message)
    Foundation.NSLog("%@", message)
}

/// This app's log, in files. The system log cannot be relied on to read back, and is gone once the app is killed, while
/// these lines remain after a crash and show on the next launch. It stays on the device unless the user shares it.
enum AppLog {
    private static let lock = NSLock()
    private static var folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AppLog", isDirectory: true)
    private static var handle: FileHandle?
    private static var size = 0
    private static var lastProgress: [String: Date] = [:]
    private static let limit = 4_000_000
    private static var on = false

    /// Follows developer tools. While it is off nothing is written or printed, as on Android.
    static var enabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return on }
        set { lock.lock(); on = newValue; lock.unlock() }
    }

    private static var current: URL { folder.appendingPathComponent("current.log") }
    private static var previous: URL { folder.appendingPathComponent("previous.log") }

    /// Starts a new run: the last run's log becomes the previous one, and uncaught exceptions are recorded.
    static func start(folder custom: URL? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let custom { folder = custom }
        close()
        lastProgress = [:]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: current.path) {
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: current, to: previous)
        }
        open()
        NSSetUncaughtExceptionHandler { exception in
            AppLog.write("AquaRestore: uncaught exception \(exception.name.rawValue): \(exception.reason ?? "no reason")\n" +
                         exception.callStackSymbols.prefix(40).joined(separator: "\n"))
        }
    }

    static func write(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        if on { append(message) }
    }

    /// At most one line every five seconds for each running export, with the free memory.
    static func progress(_ label: String, percent: Int, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard on else { return }
        if let last = lastProgress[label], now.timeIntervalSince(last) < 5 { return }
        lastProgress[label] = now
        append("AquaRestore: \(label) at \(percent)%\(memory)")
    }

    /// What this app can still use before the system ends it. Zero where the system does not report it.
    static var availableMemory: UInt64 {
        #if os(iOS)
        return UInt64(os_proc_available_memory())
        #else
        return 0
        #endif
    }

    /// The free memory, to add to a log line where it matters. Nothing where the system does not report it.
    static var memory: String {
        #if os(iOS)
        return " | free memory \(availableMemory / 1_048_576) MB"
        #else
        return ""
        #endif
    }

    /// The last run's log, if any, then this run's.
    static func read() -> String {
        lock.lock(); defer { lock.unlock() }
        var parts: [String] = []
        if let text = try? String(contentsOf: previous, encoding: .utf8), !text.isEmpty {
            parts.append("--- Previous run. If it stops partway, the app may have crashed or been stopped. ---\n" + text)
        }
        if let text = try? String(contentsOf: current, encoding: .utf8), !text.isEmpty {
            parts.append("--- This run ---\n" + text)
        }
        return parts.joined(separator: "\n")
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        close()
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.removeItem(at: current)
        open()
    }

    private static func close() {
        try? handle?.close()
        handle = nil
        size = 0
    }

    private static func open() {
        if !FileManager.default.fileExists(atPath: current.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: current.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: current)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private static func append(_ message: String) {
        if handle == nil { open() }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        guard let data = "\(formatter.string(from: Date())) \(message)\n".data(using: .utf8) else { return }
        // Written straight to the file, so the line survives the app being killed a moment later.
        try? handle?.write(contentsOf: data)
        size += data.count
        if size > limit { trim() }
    }

    /// Keeps the newest half, since the end of a long run is what explains how it ended.
    private static func trim() {
        guard let data = try? Data(contentsOf: current) else { return }
        close()
        try? data.suffix(limit / 2).write(to: current)
        open()
    }
}

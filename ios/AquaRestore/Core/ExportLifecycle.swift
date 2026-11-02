import Foundation

/// Tracks interruptions even when the app returns before an asynchronous operation reports its error.
enum AppActivity {
    private static let lock = NSLock()
    private static var _active = true
    private static var _generation = 0
    static var active: Bool { lock.lock(); defer { lock.unlock() }; return _active }
    static var generation: Int { lock.lock(); defer { lock.unlock() }; return _generation }
    static func set(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        if _active && !value { _generation += 1 }
        _active = value
    }

    private static var observers: [NSObjectProtocol] = []
    static func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: Notification.Name("UIApplicationWillResignActiveNotification"), object: nil, queue: nil) { _ in set(false) },
            center.addObserver(forName: Notification.Name("UIApplicationDidBecomeActiveNotification"), object: nil, queue: nil) { _ in set(true) },
        ]
    }
}

struct ExportInterrupted: Error {}

/// Pause callbacks update the UI directly when the caller is a batch export.
@MainActor
enum ForegroundExport {
    /// Only rendering belongs here. Publishing to Photos must happen once, after a successful attempt.
    static func run<Value>(waiting: () -> Void, operation: () async throws -> Value) async throws -> Value {
        while true {
            try Task.checkCancellation()
            while !AppActivity.active {
                waiting()
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            let generation = AppActivity.generation
            do {
                let value = try await operation()
                try Task.checkCancellation()
                if generation == AppActivity.generation && AppActivity.active { return value }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                guard error is ExportInterrupted || generation != AppActivity.generation || !AppActivity.active else { throw error }
            }
            waiting()
        }
    }
}

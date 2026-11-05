import Foundation

/// What one export is doing to the phone as it runs, for deciding about its comparison preview.
final class ExportLoad: @unchecked Sendable {
    private let lock = NSLock()
    private var began: Date?
    private var firstFrame: Date?
    private var lastFrame: Date?
    private var reached = 0.0
    private var total = 0.0
    private var warned = false
    private var fraction = 0.0

    /// Starts measuring an attempt. An export that was interrupted starts again, so only its last attempt counts. A memory
    /// warning stays counted, since the phone is no roomier for the restart.
    func begin(total seconds: Double, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        began = now; firstFrame = nil; lastFrame = nil; reached = 0; total = seconds
    }

    /// The export has read a frame this far into the video it is writing.
    func frame(at seconds: Double, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        if firstFrame == nil { firstFrame = now }
        lastFrame = now
        reached = max(reached, seconds)
    }

    var reachedSeconds: Double { lock.lock(); defer { lock.unlock() }; return reached }
    var remainingSeconds: Double { lock.lock(); defer { lock.unlock() }; return max(0, total - reached) }

    func memoryWarning() { lock.lock(); warned = true; lock.unlock() }
    var memoryWarned: Bool { lock.lock(); defer { lock.unlock() }; return warned }

    /// How much of the comparison, from 0 to 1, has been made.
    var comparisonFraction: Double {
        get { lock.lock(); defer { lock.unlock() }; return fraction }
        set { lock.lock(); fraction = newValue; lock.unlock() }
    }

    /// Whether the export has been running long enough for its decoder and buffers to be counted in the free memory.
    func settled(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let firstFrame else { return false }
        return now.timeIntervalSince(firstFrame) >= ComparisonRoom.settleSeconds
    }

    /// Seconds of video made per second of waiting, including the time spent opening the file.
    var speed: Double? {
        lock.lock(); defer { lock.unlock() }
        guard let began, let lastFrame, reached > 0 else { return nil }
        return reached / max(lastFrame.timeIntervalSince(began), 0.001)
    }
}

/// How fast a running count is rising, over a recent stretch of time.
struct SpeedWatch {
    private var samples: [(time: Date, value: Double)] = []

    mutating func add(_ value: Double, now: Date = Date()) {
        samples.append((now, value))
        samples.removeAll { now.timeIntervalSince($0.time) > 10 }
    }

    /// The rise per second over about this many seconds. Nil until that much has been watched.
    func rate(over seconds: Double) -> Double? {
        guard let newest = samples.last,
              let oldest = samples.last(where: { newest.time.timeIntervalSince($0.time) >= seconds }) else { return nil }
        return max(0, newest.value - oldest.value) / newest.time.timeIntervalSince(oldest.time)
    }
}

/// Whether a video's comparison preview can have the resources it needs, judged by what this phone reports while it
/// exports rather than by its model. The export comes first, and the comparison may cost the user a few seconds at most,
/// whether by slowing the export or by being waited for afterwards. Photos do not come through here, because they use far
/// less.
enum ComparisonRoom {
    enum Pressure: String {
        case memoryWarning = "a memory warning"
        case lowMemory = "low free memory"
        case heat = "a hot phone"
        case tooSlow = "too slow to finish in time"
        case costsTooMuch = "costing the export too much time"
    }

    static let settleSeconds = 1.5
    /// How long a comparison may take before it is stopped.
    static let timeLimitSeconds = 60.0
    /// How much waiting a comparison may add to what the export takes alone.
    static let extraSeconds = 3.0
    /// The allowance for estimates once a comparison is under way, since stopping it throws away what it has made.
    private static let runningSeconds = extraSeconds + 1
    /// Long enough for a comparison's first frames to have arrived, before its speed is judged.
    private static let measuredAfterSeconds = 10.0

    /// What, if anything, leaves no room for a comparison. `pipelines` is how many full decode-and-grade pipelines must
    /// fit in the free memory: two before it starts, for its own and a margin, and one once its own is already counted.
    /// Zero, where the system reports nothing, counts as no room.
    static func pressure(width: Int, height: Int, hdr: Bool, availableMemory: UInt64, pipelines: UInt64,
                         memoryWarned: Bool, thermal: ProcessInfo.ThermalState) -> Pressure? {
        if memoryWarned { return .memoryWarning }
        if thermal == .serious || thermal == .critical { return .heat }
        if availableMemory < LivePreview.pipelineMemory(width: width, height: height, hdr: hdr) * pipelines { return .lowMemory }
        return nil
    }

    /// Whether a running comparison is on course to miss its time limit. Stopping it early gives the rest back to the export.
    static func cannotFinish(fraction: Double, elapsed: Double) -> Bool {
        guard elapsed >= measuredAfterSeconds else { return false }
        return elapsed / max(fraction, 0.001) > timeLimitSeconds
    }

    /// How many seconds finishing this comparison would add to everything being done, compared with stopping it now. The two
    /// share the phone until the first one ends, and then the other runs as fast as the export does alone.
    static func addedSeconds(exportRemaining: Double, aloneSpeed: Double, currentSpeed: Double, comparisonRemaining: Double) -> Double {
        let current = max(min(currentSpeed, aloneSpeed), 0.001)
        let alone = exportRemaining / aloneSpeed
        let exportEnds = exportRemaining / current
        if exportEnds < comparisonRemaining {
            return exportEnds + (comparisonRemaining - exportEnds) * current / aloneSpeed - alone
        }
        return comparisonRemaining + (exportRemaining - current * comparisonRemaining) / aloneSpeed - alone
    }

    static func costsTooMuch(exportRemaining: Double, aloneSpeed: Double, currentSpeed: Double, comparisonRemaining: Double) -> Bool {
        guard aloneSpeed > 0 else { return false }
        return addedSeconds(exportRemaining: exportRemaining, aloneSpeed: aloneSpeed, currentSpeed: currentSpeed,
                            comparisonRemaining: comparisonRemaining) > runningSeconds
    }

    /// Whether to keep waiting for a comparison once the saved export is on screen. The phone is its own now, so it is judged
    /// by how fast it goes from here (`from` is how far it had got when that measuring began, `measured` how long ago).
    /// Within the first second that is unknown, so it only stops at the end of the allowance.
    static func worthFinishing(fraction: Double, from: Double, measured: Double?, waited: Double) -> Bool {
        guard let measured, measured >= 1 else { return waited <= runningSeconds }
        let rate = (fraction - from) / measured
        guard rate > 0 else { return false }
        return waited + (1 - fraction) / rate <= runningSeconds
    }

    /// Whether a comparison the phone had no room for during the export is still worth making afterwards. Decoding the
    /// clip costs about what decoding the same stretch of the export did, so this takes the export's speed as the estimate.
    static func worthMakingAfterExport(clipMs: Int64, exportSpeed: Double?) -> Bool {
        guard let exportSpeed, exportSpeed > 0 else { return false }
        return Double(clipMs) / 1000 / exportSpeed <= extraSeconds
    }
}

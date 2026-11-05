import Foundation

/// Select at most one source frame per target time slot; never invent frames or alter timestamps.
final class FrameCadence {
    private let fps: Float
    private var origin: Int64?
    private var slot: Int64 = -1
    private var last: Int64 = 0
    init(fps: Float) { precondition(fps.isFinite && fps > 0); self.fps = fps }

    func accept(timeUs: Int64) -> Bool {
        // Going back, as a preview does at each loop or seek, starts again. Otherwise no frame would fall in a new slot until
        // the time passed the furthest point reached, and the picture would hold still until then.
        if origin == nil || timeUs < last { origin = timeUs; slot = -1 }
        last = timeUs
        // Timestamps are integer microseconds: tolerate their <1us quantization at slot boundaries.
        let nextSlot = Int64(Double(timeUs - origin! + 1) * Double(fps) / 1_000_000)
        if nextSlot <= slot { return false }
        slot = nextSlot
        return true
    }
    func reset() { origin = nil; slot = -1; last = 0 }
}

/// What a frame left out by the cadence shows instead: the newest graded picture. Grading finishes later on the GPU, so
/// "the last one finished" can be older than a frame already shown, and the picture would step back and forth. A left-out
/// frame that arrives during grading therefore waits for that grading to finish.
final class FrameRepeater<Frame, Waiter> {
    final class Grading { fileprivate var waiters: [Waiter] = [] }
    enum Repeat { case now(Frame), waiting, nothing }

    private let lock = NSLock()
    private var newest: Frame?
    private var latest: Grading?

    /// A frame has started grading.
    func begin() -> Grading {
        lock.lock(); defer { lock.unlock() }
        let grading = Grading()
        latest = grading
        return grading
    }

    /// For a left-out frame. `nothing` means there is no picture to repeat, so it has to be graded itself.
    func repeatFrame(for waiter: Waiter) -> Repeat {
        lock.lock(); defer { lock.unlock() }
        if let latest { latest.waiters.append(waiter); return .waiting }
        if let newest { return .now(newest) }
        return .nothing
    }

    /// Grading has ended, with no frame if it failed. Returns who was waiting and what they should show, the older picture
    /// after a failure, if there is one.
    func finish(_ grading: Grading, frame: Frame?) -> (waiters: [Waiter], show: Frame?) {
        lock.lock(); defer { lock.unlock() }
        if let frame { newest = frame }
        if latest === grading { latest = nil }
        let waiters = grading.waiters
        grading.waiters = []
        return (waiters, newest)
    }
}

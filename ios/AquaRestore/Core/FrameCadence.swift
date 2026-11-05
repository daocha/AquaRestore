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

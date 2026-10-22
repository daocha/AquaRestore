import Foundation

/// Select at most one source frame per target time slot; never invent frames or alter timestamps.
final class FrameCadence {
    private let fps: Float
    private var origin: Int64?
    private var slot: Int64 = -1
    init(fps: Float) { precondition(fps.isFinite && fps > 0); self.fps = fps }

    func accept(timeUs: Int64) -> Bool {
        if origin == nil || timeUs < origin! { origin = timeUs; slot = -1 }
        // Timestamps are integer microseconds: tolerate their <1us quantization at slot boundaries.
        let nextSlot = Int64(Double(timeUs - origin! + 1) * Double(fps) / 1_000_000)
        if nextSlot <= slot { return false }
        slot = nextSlot
        return true
    }
    func reset() { origin = nil; slot = -1 }
}

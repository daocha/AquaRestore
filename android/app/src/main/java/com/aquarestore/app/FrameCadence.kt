package com.aquarestore.app

/** Select at most one source frame per target time slot; never invent frames or alter timestamps. */
class FrameCadence(private val fps: Float) {
    private var origin: Long? = null
    private var slot = -1L
    init { require(fps.isFinite() && fps > 0) }
    fun accept(timeUs: Long): Boolean {
        if (origin == null || timeUs < origin!!) { origin = timeUs; slot = -1 }
        // Timestamps are integer microseconds: tolerate their <1us quantization at slot boundaries.
        val nextSlot = ((timeUs - origin!! + 1) * fps.toDouble() / 1_000_000).toLong()
        if (nextSlot <= slot) return false
        slot = nextSlot
        return true
    }
    fun reset() { origin = null; slot = -1 }
}

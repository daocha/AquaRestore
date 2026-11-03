package com.aquarestore.app

import kotlin.math.*

object SharingPlan {
    fun videoSize(width: Int, height: Int): Pair<Int, Int> {
        require(width >= 2 && height >= 2)
        val scale = min(1.0, min(1280.0 / max(width, height), 720.0 / min(width, height)))
        return max(2, (width * scale).toInt() / 2 * 2) to max(2, (height * scale).toInt() / 2 * 2)
    }
    fun clip(durationMs: Long): Pair<Long, Long> {
        val length = min(10_000L, durationMs)
        return (durationMs - length) / 2 to length
    }
    fun eligible(videos: Int, photos: Int) = videos >= 5 || photos >= 10
}

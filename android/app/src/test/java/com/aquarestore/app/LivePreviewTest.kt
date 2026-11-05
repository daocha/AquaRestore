package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test

class LivePreviewTest {
    private data class Point(val width: Int, val height: Int, val fps: Int)

    /** Like PerformancePoint.covers: the frame must fit, at the frame rate and pixels per second. */
    private fun decoder(vararg points: Point): (Int, Int, Int) -> Boolean = { w, h, fps ->
        points.any { it.width.toLong() * it.height >= w.toLong() * h && it.fps >= fps && it.width.toLong() * it.height * it.fps >= w.toLong() * h * fps }
    }

    private val galaxyS10 = decoder(Point(4096, 2304, 60), Point(4096, 2160, 96), Point(3840, 2160, 120), Point(1920, 1088, 240), Point(1280, 720, 480))

    @Test fun declaredSpeedAtASmallerFramePlaysTheOriginal() {
        assertEquals(94, equivalentFps4k(3840, 3360, 60f))
        assertEquals(LivePreview.ORIGINAL, livePreview(3840, 3360, 60f, listOf(galaxyS10)))
        assertEquals(LivePreview.ORIGINAL, livePreview(3360, 3840, 60f, listOf(galaxyS10)))
    }

    @Test fun within4k60PlaysTheOriginalWithoutAnyDeclaration() {
        assertEquals(LivePreview.ORIGINAL, livePreview(3840, 2160, 60f, listOf(galaxyS10)))
        assertEquals(LivePreview.ORIGINAL, livePreview(3840, 2160, 60f, listOf(decoder())))
        assertEquals(LivePreview.ORIGINAL, livePreview(3840, 3360, 30f, listOf(galaxyS10)))
    }

    @Test fun aPointCoveringTheVideoPlaysTheOriginal() {
        assertEquals(LivePreview.ORIGINAL, livePreview(3840, 3360, 60f, listOf(decoder(Point(7680, 4320, 60)))))
        assertEquals(LivePreview.ORIGINAL, livePreview(3840, 3360, 60f, listOf(galaxyS10, decoder(Point(7680, 4320, 60)))))
    }

    @Test fun tooLittleDeclaredSpeedStillGetsACopy() {
        assertEquals(LivePreview.COPY, livePreview(3840, 3360, 60f, listOf(decoder(Point(4096, 2304, 60)))))
        assertEquals(LivePreview.COPY, livePreview(3840, 3360, 60f, listOf(decoder(Point(1920, 1088, 480)))))
        assertEquals(LivePreview.COPY, livePreview(3840, 3360, 60f, listOf(decoder())))
        assertEquals(LivePreview.COPY, livePreview(7680, 4320, 60f, listOf(galaxyS10)))
    }

    @Test fun aFailedPreviewStartsAgainAfterGrowingPauses() {
        val retry = PlaybackRetry()
        assertEquals(1_000L, retry.nextDelayMs(1_000))
        assertEquals(3_000L, retry.nextDelayMs(3_000))
        assertNull(retry.nextDelayMs(7_000))
        assertNull(retry.nextDelayMs(20_000))
        assertEquals(1_000L, retry.nextDelayMs(33_000))
    }

    @Test fun noDecoderAcceptingTheFrameGetsACopy() {
        assertEquals(LivePreview.COPY, livePreview(3840, 2160, 60f, emptyList()))
        assertEquals(LivePreview.COPY, livePreview(3840, 3360, 60f, emptyList()))
    }
}

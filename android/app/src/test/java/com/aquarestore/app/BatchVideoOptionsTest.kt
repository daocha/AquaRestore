package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test

class BatchVideoOptionsTest {
    @Test fun recommendedResolvesEachVideosSizeAndFrameRate() {
        val selection = ExportSelection()
        val phone = selection.videoOptions(3840, 2160, 60f)
        assertFalse(phone.original)
        assertEquals(1920, phone.longEdge)
        assertEquals(30, phone.fps)
        assertTrue(selection.videoOptions(1280, 720, 30f).original)
    }

    @Test fun customNeverRaisesTheFrameRateAndOriginalKeepsTheSource() {
        val custom = ExportSelection(mode = ExportMode.CUSTOM, longEdge = 1280, fps = 60, quality = 70)
        assertEquals(0, custom.videoOptions(1920, 1080, 30f).fps)
        assertEquals(60, custom.videoOptions(1920, 1080, 120f).fps)
        // After slowing down, only the remaining rate counts.
        assertEquals(0, custom.videoOptions(1920, 1080, 120f, outputFps = 30f).fps)
        assertEquals(70, custom.videoOptions(1920, 1080, 30f).quality)
        assertTrue(ExportSelection(mode = ExportMode.ORIGINAL).videoOptions(3840, 2160, 60f).original)
    }

    @Test fun spaceCountsTheVideoBeingCopiedTwice() {
        assertEquals(BATCH_VIDEO_SPACE_MARGIN, batchVideoSpace(emptyList()))
        assertEquals(100L + 300L + 300L + BATCH_VIDEO_SPACE_MARGIN, batchVideoSpace(listOf(100L, 300L)))
    }

    @Test fun batchTextsSayVideos() {
        val s = Strings(false)
        val status = BatchExportStatus(3, videos = true)
        assertEquals("Video 1 of 3 · a.mp4", status.copy(currentName = "a.mp4").progressText(s))
        val done = status.copy(failures = listOf(PhotoExportFailure("b.mp4", "videoNeedsEditor")))
        assertEquals("0 of 3 videos saved to Gallery / AquaRestore.\n1 failed.\n2 not processed. Completed videos are kept.",
            done.resultText(s))
        assertEquals("Photo 1 of 3", BatchExportStatus(3).progressText(s))
    }
}

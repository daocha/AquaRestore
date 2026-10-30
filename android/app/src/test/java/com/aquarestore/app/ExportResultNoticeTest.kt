package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test

class ExportResultNoticeTest {
    private val s = Strings(false)

    @Test fun singleExportReportsWhereItWasSaved() {
        val (title, text) = ExportStatus(progress = 100, stage = "saved").resultNotice(s)!!
        assertEquals("Saved to your gallery", title)
        assertEquals("Find your restored media in Gallery / AquaRestore.", text)
    }

    @Test fun failedExportGivesTheReason() {
        val (title, text) = ExportStatus(error = "memory").resultNotice(s)!!
        assertEquals("Export failed", title)
        assertEquals(s["memory"], text)
    }

    @Test fun batchListsEachFailedPhotoWithItsReason() {
        val batch = BatchExportStatus(3, failures = listOf(PhotoExportFailure("a.jpg", "photoUnreadable"),
            PhotoExportFailure("b.mp4", "batchPhotosOnly")))
        val (title, text) = ExportStatus(progress = 100, stage = "batchFinished", batch = batch).resultNotice(s)!!
        assertEquals("Batch export finished", title)
        val lines = text.lines()
        assertEquals("0 of 3 photos saved to Gallery / AquaRestore.", lines[0])
        assertEquals("2 failed.", lines[1])
        assertEquals("1 not processed. Completed photos are kept.", lines[2])
        assertEquals("a.jpg: ${s["photoUnreadable"]}", lines[3])
        assertEquals("b.mp4: ${s["batchPhotosOnly"]}", lines[4])
    }

    @Test fun cancellingByTheUserPostsNothing() {
        assertNull(ExportStatus(stage = "cancelled").resultNotice(s))
        assertNull(ExportStatus(stage = "cancelled", batch = BatchExportStatus(5)).resultNotice(s))
    }

    @Test fun chineseUsesChineseText() {
        val (title, _) = ExportStatus(progress = 100, stage = "saved").resultNotice(Strings(true))!!
        assertEquals("已儲存至相簿", title)
    }
}

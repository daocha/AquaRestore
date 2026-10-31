package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test

class BatchPhotoOptionsTest {
    @Test fun recommendedResolvesEachPhotosDimensionsAndFormat() {
        val selection = ExportSelection()
        val small = selection.photoOptions(1200, 800, "image/jpeg")
        val large = selection.photoOptions(6000, 4000, "image/png")
        assertTrue(small.original)
        assertFalse(small.png)
        assertEquals(95, small.quality)
        assertFalse(large.original)
        assertEquals(2560, large.longEdge)
        assertTrue(large.png)
        assertEquals(1200 to 800, ExportSizing.dimensions(1200, 800, large.longEdge))
    }

    @Test fun originalAndCustomUseTheSamePhotoPolicyAsSingleExport() {
        val original = ExportSelection(mode = ExportMode.ORIGINAL, png = true).photoOptions(6000, 4000, "image/jpeg")
        assertTrue(original.original)
        assertTrue(original.png)
        assertEquals(ORIGINAL_JPEG_QUALITY, original.quality)
        val custom = ExportSelection(mode = ExportMode.CUSTOM, longEdge = 1920, quality = 72).photoOptions(4000, 6000, "image/png")
        assertFalse(custom.original)
        assertFalse(custom.png)
        assertEquals(72, custom.quality)
        assertEquals(1280 to 1920, ExportSizing.dimensions(4000, 6000, custom.longEdge))
        assertEquals(1f, custom.speed)
        assertEquals(0L, custom.startMs)
        assertEquals(0L, custom.endMs)
    }

    @Test fun batchTotalAddsEachPhotosOwnEstimate() {
        val photos = listOf(PhotoHeader(1200, 800, "image/jpeg"), PhotoHeader(6000, 4000, "image/png"))
        val selection = ExportSelection()
        val each = photos.map { photoEstimatedBytes(it.width, it.height, selection.photoOptions(it.width, it.height, it.mime)) }
        assertEquals(each.sum(), batchPhotoBytes(photos, selection))
        assertEquals(0L, batchPhotoBytes(emptyList(), selection))
        assertTrue(batchPhotoBytes(photos, ExportSelection(mode = ExportMode.ORIGINAL, png = true)) > batchPhotoBytes(photos, selection))
    }

    @Test fun batchSizeTextPicksTheUnit() {
        assertEquals("512 KB", batchSizeText(512_000))
        assertEquals("3.5 MB", batchSizeText(3_500_000))
        assertEquals("1.25 GB", batchSizeText(1_250_000_000))
    }
}

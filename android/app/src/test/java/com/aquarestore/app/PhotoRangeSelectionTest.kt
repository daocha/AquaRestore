package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test

class PhotoRangeSelectionTest {
    private val photos = List(150) { "photo-$it" }

    @Test fun selectsForwardAndBackwardWhileKeepingOtherAlbumSelections() {
        assertEquals(listOf("other-album", "photo-2", "photo-3", "photo-4", "photo-5"),
            PhotoRangeSelection(photos, listOf("other-album"), 2).through(5))
        assertEquals(listOf("photo-5", "photo-4", "photo-3", "photo-2"),
            PhotoRangeSelection(photos, emptyList(), 5).through(2))
    }

    @Test fun reversingDirectionRestoresPhotosOutsideTheCurrentRange() {
        val gesture = PhotoRangeSelection(photos, listOf("photo-8"), 2)
        assertEquals(7, gesture.through(7).size)
        assertEquals(listOf("photo-8", "photo-2", "photo-3"), gesture.through(3))
        assertEquals(listOf("photo-8", "photo-2", "photo-1", "photo-0"), gesture.through(0))
    }

    @Test fun startingOnASelectedPhotoDeselectsTheRangeAndRestoresOnReversal() {
        val selected = listOf("other-album") + photos.take(6)
        val gesture = PhotoRangeSelection(photos, selected, 0)
        assertEquals(listOf("other-album"), gesture.through(5))
        assertEquals(listOf("other-album") + photos.subList(2, 6), gesture.through(1))
    }

    @Test fun capsAt100IncludingExistingSelectionsAndAllowsReversal() {
        assertEquals(100, MAX_BATCH_PHOTOS)
        val existing = listOf("other-1", "other-2", "other-3")
        val gesture = PhotoRangeSelection(photos, existing, 0)
        assertEquals(existing + photos.take(97), gesture.through(149))
        assertEquals(existing + photos.take(3), gesture.through(2))
        assertEquals(existing + photos.asReversed().take(97), PhotoRangeSelection(photos, existing, 149).through(0))
    }

    @Test fun aFullSelectionCanStillBeDeselected() {
        assertTrue(PhotoRangeSelection(photos, photos.take(100), 0).through(99).isEmpty())
    }
}

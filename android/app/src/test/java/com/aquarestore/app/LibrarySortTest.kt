package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test

class LibrarySortTest {
    private val files = listOf("b.mp4" to 2L, "C.jpg" to 3L, "a.mp4" to 1L, "A2.mp4" to 3L)

    private fun sorted(sort: LibrarySort) = librarySorted(files, sort, { it.first }, { it.second }).map { it.first }

    @Test fun sortsByDateEitherWay() {
        // Equal dates fall back to the name.
        assertEquals(listOf("A2.mp4", "C.jpg", "b.mp4", "a.mp4"), sorted(LibrarySort.NEWEST))
        assertEquals(listOf("a.mp4", "b.mp4", "A2.mp4", "C.jpg"), sorted(LibrarySort.OLDEST))
    }

    @Test fun sortsByNameIgnoringCaseEitherWay() {
        assertEquals(listOf("a.mp4", "A2.mp4", "b.mp4", "C.jpg"), sorted(LibrarySort.NAME_AZ))
        assertEquals(listOf("C.jpg", "b.mp4", "A2.mp4", "a.mp4"), sorted(LibrarySort.NAME_ZA))
    }
}

package com.aquarestore.app

import android.Manifest.permission.*
import org.junit.Assert.*
import org.junit.Test

class LibraryAccessTest {
    @Test fun photoGrantDoesNotCoverMixedImportOrVideoBatch() {
        for (sdk in listOf(33, 34)) {
            val granted = setOf(READ_MEDIA_IMAGES)
            val photos = libraryAccess(mediaPermissions(false, true, sdk = sdk), granted)
            assertTrue(photos.allowed)
            assertTrue(photos.full)
            val mixed = libraryAccess(mediaPermissions(false, false, sdk = sdk), granted)
            assertTrue(mixed.allowed)
            assertFalse("Import must still request video access on API $sdk", mixed.full)
            assertTrue(mixed.requestOnOpen)
            val videos = libraryAccess(mediaPermissions(false, false, videosOnly = true, sdk = sdk), granted)
            assertFalse(videos.allowed)
            assertFalse(videos.full)
        }
    }

    @Test fun videoGrantDoesNotCoverPhotosInMixedImport() {
        val mixed = libraryAccess(mediaPermissions(false, false, sdk = 33), setOf(READ_MEDIA_VIDEO))
        assertTrue(mixed.allowed)
        assertFalse(mixed.full)
    }

    @Test fun selectedFilesRemainBrowsableWithoutClaimingFullAccess() {
        val granted = setOf(READ_MEDIA_VISUAL_USER_SELECTED)
        for (permissions in listOf(mediaPermissions(false, true, sdk = 34),
            mediaPermissions(false, false, videosOnly = true, sdk = 34), mediaPermissions(false, false, sdk = 34))) {
            val access = libraryAccess(permissions, granted)
            assertTrue(access.allowed)
            assertFalse(access.full)
            assertTrue(access.limited)
            assertFalse("Opening a limited library must not start reselection", access.requestOnOpen)
        }
        val audio = libraryAccess(mediaPermissions(true, false, sdk = 34), granted)
        assertFalse(audio.allowed)
        assertTrue(audio.requestOnOpen)
    }

    @Test fun fullPhotoAccessAndSelectedVideoAccessStillRespectTheLimitedChoice() {
        val granted = setOf(READ_MEDIA_IMAGES, READ_MEDIA_VISUAL_USER_SELECTED)
        val mixed = libraryAccess(mediaPermissions(false, false, sdk = 34), granted)
        assertTrue(mixed.allowed)
        assertFalse(mixed.full)
        assertTrue(mixed.limited)
        assertFalse(mixed.requestOnOpen)
        val photos = libraryAccess(mediaPermissions(false, true, sdk = 34), granted)
        assertTrue(photos.full)
        assertFalse(photos.limited)
        assertFalse(photos.requestOnOpen)
    }

    @Test fun fullAccessDoesNotRequireTheOptionalSelectedFilesPermission() {
        val access = libraryAccess(mediaPermissions(false, false, sdk = 34), setOf(READ_MEDIA_IMAGES, READ_MEDIA_VIDEO))
        assertTrue(access.allowed)
        assertTrue(access.full)
        assertFalse(access.requestOnOpen)
    }

    @Test fun unrelatedOrMissingGrantsDoNotAllowBrowsing() {
        val permissions = mediaPermissions(false, false, sdk = 33)
        assertEquals(LibraryAccess(false, false), libraryAccess(permissions, emptySet()))
        assertTrue(libraryAccess(permissions, emptySet()).requestOnOpen)
        assertEquals(LibraryAccess(false, false), libraryAccess(permissions, setOf(READ_MEDIA_AUDIO)))
        val legacy = mediaPermissions(false, true, sdk = 32)
        assertEquals(listOf(READ_EXTERNAL_STORAGE), legacy.toList())
        assertEquals(LibraryAccess(true, true), libraryAccess(legacy, setOf(READ_EXTERNAL_STORAGE)))
    }
}

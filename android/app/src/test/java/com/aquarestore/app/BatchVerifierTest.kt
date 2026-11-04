package com.aquarestore.app
import org.junit.Assert.*
import org.junit.Test

class BatchVerifierTest {
    @Test fun acceptsUtf8BuildVerifierAndRejectsIncorrectCode() {
        val salt = "000102030405060708090a0b0c0d0e0f"
        val verifier = "384098cfd1872d7aacd8a22b8d0d7a87f898616c6e6a4a2c31c79832ac65afd3"
        assertTrue(BatchAccess.verify("sample-測試-5678", salt, verifier))
        assertFalse(BatchAccess.verify("wrong", salt, verifier))
    }
    @Test fun debugGatesUseApplicationIdForBothFeatures() {
        assertTrue(BatchAccess.verify(BuildConfig.APPLICATION_ID, BuildConfig.BATCH_PHOTO_SALT, BuildConfig.BATCH_PHOTO_VERIFIER))
        assertTrue(BatchAccess.verify(BuildConfig.APPLICATION_ID, BuildConfig.BATCH_VIDEO_SALT, BuildConfig.BATCH_VIDEO_VERIFIER))
        assertFalse(BatchAccess.verify("incorrect", BuildConfig.BATCH_PHOTO_SALT, BuildConfig.BATCH_PHOTO_VERIFIER))
        assertNotEquals(BuildConfig.BATCH_PHOTO_SALT, BuildConfig.BATCH_VIDEO_SALT)
    }
    @Test fun oneSubmissionMatchesPhotoVideoBothOrNeither() {
        val salt = "000102030405060708090a0b0c0d0e0f"
        val photo = "384098cfd1872d7aacd8a22b8d0d7a87f898616c6e6a4a2c31c79832ac65afd3"
        val video = "e40fc53d3cc8a699dbdc60329c1b3af09d9ee7af50d501c270e730d427f0ee31"
        assertEquals(true to false, BatchAccess.matchingFeatures("sample-測試-5678", salt, photo, salt, video))
        assertEquals(false to true, BatchAccess.matchingFeatures("video-only", salt, photo, salt, video))
        assertEquals(false to false, BatchAccess.matchingFeatures("wrong", salt, photo, salt, video))
        assertEquals(true to true, BatchAccess.matchingFeatures("sample-測試-5678", salt, photo, salt, photo))
        assertEquals(false to false, BatchAccess.matchingFeatures("anything", salt, "", salt, ""))
    }
}

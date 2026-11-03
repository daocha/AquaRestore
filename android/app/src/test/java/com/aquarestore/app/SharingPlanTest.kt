package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test

class SharingPlanTest {
    @Test fun capsBothAxesAndPreservesSmallSources() {
        assertEquals(1280 to 720, SharingPlan.videoSize(3840, 2160))
        assertEquals(720 to 1280, SharingPlan.videoSize(2160, 3840))
        assertEquals(720 to 720, SharingPlan.videoSize(2000, 2000))
        assertEquals(318 to 238, SharingPlan.videoSize(319, 239))
        assertEquals(1280 to 128, SharingPlan.videoSize(4000, 400))
    }
    @Test fun clipsAreCenteredAndBounded() {
        assertEquals(27_000L to 6_000L, SharingPlan.clip(60_000))
        assertEquals(0L to 3000L, SharingPlan.clip(3000))
        assertEquals(2_000L to 6_000L, SharingPlan.clip(10_000))
    }
    @Test fun eitherSuccessfulExportThresholdQualifies() {
        assertFalse(SharingPlan.eligible(4, 9))
        assertTrue(SharingPlan.eligible(5, 0))
        assertTrue(SharingPlan.eligible(0, 10))
    }
}

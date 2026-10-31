package com.aquarestore.app

import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class BatchVideoMetadataTest {
    @Test fun cancellationDuringAReadPreventsInspectingTheRemainingClips() = runBlocking {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val inspected = mutableListOf<Int>()
        val job = launch(Dispatchers.Default) {
            readBatchVideoMetadata((0 until MAX_BATCH_VIDEOS).toList()) { index ->
                inspected += index
                if (index == 0) {
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                }
                index
            }
        }
        try {
            assertTrue("The first inspection must start", entered.await(5, TimeUnit.SECONDS))
            job.cancel()
        } finally { release.countDown() }
        withTimeout(5_000) { job.join() }
        assertEquals(listOf(0), inspected)
    }

    @Test fun cancellationFromAnInspectorIsNotTreatedAsAnUnreadableClip() = runBlocking {
        val inspected = mutableListOf<Int>()
        try {
            readBatchVideoMetadata(listOf(0, 1, 2)) { index ->
                inspected += index
                if (index == 1) throw CancellationException("cancelled read")
                index
            }
            fail("Cancellation must propagate")
        } catch (_: CancellationException) { }
        assertEquals(listOf(0, 1), inspected)
    }

    @Test fun unreadableClipsAndNonVideosDoNotStopFollowingMetadataReads() = runBlocking {
        val found = readBatchVideoMetadata(listOf(0, 1, 2, 3)) { index ->
            when (index) {
                1 -> throw IOException("unreadable clip")
                2 -> null
                else -> "video-$index"
            }
        }
        assertEquals(listOf("video-0", "video-3"), found)
    }
}

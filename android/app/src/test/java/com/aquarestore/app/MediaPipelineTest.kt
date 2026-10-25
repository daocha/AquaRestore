package com.aquarestore.app

import org.junit.Assert.*
import org.junit.Test

class MediaPipelineTest {
    @Test fun equalRatePreservesEveryFrameDespiteMicrosecondRounding() {
        val cadence = FrameCadence(30f)
        assertEquals(300, (0 until 300).count { cadence.accept(it * 1_000_000L / 30) })
    }
    @Test fun thirtyToTwentyFourDoesNotStayAtThirty() {
        val cadence = FrameCadence(24f)
        val selected = (0 until 300).map { it * 1_000_000L / 30 }.filter(cadence::accept)
        assertEquals(240, selected.size)
        assertTrue(selected.zipWithNext().all { (a, b) -> b > a })
    }
    @Test fun frameCappingResetsAndDoesNotDuplicateSparseFrames() {
        val cadence = FrameCadence(30f)
        assertEquals(60, (0 until 120).count { cadence.accept(it * 1_000_000L / 60) })
        cadence.reset()
        assertEquals(10, (0 until 10).count { cadence.accept(it * 100_000L) })
    }
    @Test fun resizingPreservesPortraitAndNeverUpscales() {
        assertEquals(1080 to 1920, ExportSizing.dimensions(2160, 3840, 1920, true))
        assertEquals(640 to 480, ExportSizing.dimensions(640, 480, 1920, true))
        assertEquals(4033 to 3025, ExportSizing.dimensions(4033, 3025, 0))
    }
    @Test fun photoRecommendationKeepsSmallSourcesAndBalancesLargeOnes() {
        assertTrue(ExportRecommendation.photo(1920, 1080).original)
        assertTrue(ExportRecommendation.photo(2560, 1440).original)
        assertFalse(ExportRecommendation.photo(1920, 1080).png)
        assertEquals(95, ExportRecommendation.photo(1920, 1080).quality)
        assertTrue(ExportRecommendation.photo(1920, 1080, "image/png").png)
        val large = ExportRecommendation.photo(4032, 3024)
        assertFalse(large.original)
        assertFalse(large.png)
        assertEquals(90, large.quality)
        assertEquals(2560 to 1920, ExportSizing.dimensions(4032, 3024, large.longEdge))
        assertTrue(ExportRecommendation.photo(4032, 3024, "image/png").png)
    }

    @Test fun videoRecommendationNeverExceedsSourceDimensionsFrameRateOrBitrate() {
        assertTrue(ExportRecommendation.video(1280, 720, 24f).original)
        val smallFast = ExportRecommendation.video(1280, 720, 60f)
        assertFalse(smallFast.original)
        assertEquals(0, smallFast.longEdge)
        assertEquals(30, smallFast.fps)
        val large = ExportRecommendation.video(3840, 2160, 60f)
        assertEquals(1920 to 1080, ExportSizing.dimensions(3840, 2160, large.longEdge))
        assertEquals(30, large.fps)
        val square = ExportRecommendation.video(3840, 3840, 24f)
        assertEquals(1080 to 1080, ExportSizing.dimensions(3840, 3840, square.longEdge))
        assertEquals(0, square.fps)
        for (rate in listOf(0, 2_000_000, 20_000_000)) {
            val source = videoExportPlan(3840, 2160, 60f, rate, 128_000, 60_000, ExportOptions())
            val suggested = videoExportPlan(3840, 2160, 60f, rate, 128_000, 60_000, large)
            assertTrue("recommended bitrate must not exceed source estimate", suggested.bitrate <= source.bitrate)
            assertTrue(suggested.estimatedBytes!! <= source.estimatedBytes!!)
        }
    }
    @Test fun originalUsesSourceRateEvenBelowHeuristicAndMinimum() {
        assertEquals(8_000_000, ExportSizing.bitrate(3840, 2160, 60f, 100, 8_000_000, true))
        assertEquals(200_000, ExportSizing.bitrate(640, 360, 30f, 100, 200_000, true))
        assertTrue(ExportSizing.bitrate(1920, 1080, 30f, 100, 0, true) > 0)
    }
    @Test fun sizeIncludesAudioDurationAndSpeedWithoutOriginalInflation() {
        fun plan(o: ExportOptions, audio: Int = 128_000, duration: Long = 60_000) =
            videoExportPlan(1920, 1080, 30f, 8_000_000, audio, duration, o)
        val original = plan(ExportOptions())
        assertEquals(8_000_000, original.bitrate)
        assertEquals(61_569_600L, original.estimatedBytes)
        assertTrue(plan(ExportOptions(), 0).estimatedBytes!! < original.estimatedBytes!!)
        assertNull(plan(ExportOptions(), duration = 0).estimatedBytes)
        // Slow motion spreads the same frames over more time; fast playback keeps the source frame rate.
        val slow = plan(ExportOptions(speed = 0.5f), 0)
        assertEquals(4_000_000, slow.bitrate)
        assertEquals(plan(ExportOptions(), 0).estimatedBytes, slow.estimatedBytes)
        for (speed in listOf(2f, 4f)) {
            val fast = plan(ExportOptions(speed = speed), 0)
            assertEquals(8_000_000, fast.bitrate)
            assertEquals(plan(ExportOptions(), 0).estimatedBytes!! / speed.toDouble(), fast.estimatedBytes!!.toDouble(), 2.0)
        }
        val custom = ExportOptions(original = false)
        assertTrue(plan(custom.copy(quality = 10)).estimatedBytes!! < plan(custom.copy(quality = 100)).estimatedBytes!!)
        assertTrue(plan(custom.copy(longEdge = 640)).estimatedBytes!! < plan(custom).estimatedBytes!!)
        assertTrue(plan(custom.copy(fps = 24)).estimatedBytes!! < plan(custom).estimatedBytes!!)
    }

    @Test fun trimShortensDurationAndSizeEstimate() {
        assertEquals(60_000L, ExportOptions().trimmedMs(60_000))
        assertEquals(50_000L, ExportOptions(startMs = 10_000).trimmedMs(60_000))
        assertEquals(20_000L, ExportOptions(startMs = 10_000, endMs = 30_000).trimmedMs(60_000))
        assertEquals(0L, ExportOptions(startMs = 70_000).trimmedMs(60_000))
        fun bytes(o: ExportOptions) = videoExportPlan(1920, 1080, 30f, 8_000_000, 128_000, 60_000, o).estimatedBytes!!
        assertEquals(bytes(ExportOptions()) / 3.0, bytes(ExportOptions(startMs = 10_000, endMs = 30_000)).toDouble(), 2.0)
    }

    @Test fun musicWindowStaysInsideTheSongAndMatchesTheVideo() {
        assertEquals(30_000L..40_000L, musicWindow(180_000, 30_000, 10_000))
        assertEquals(0L..10_000L, musicWindow(180_000, -500, 10_000))
        assertEquals(170_000L..180_000L, musicWindow(180_000, 175_000, 10_000))
        assertEquals("shorter song plays whole", 0L..8_000L, musicWindow(8_000, 3_000, 20_000))
    }

    @Test fun shortSongsRepeatToFillTheVideo() {
        assertEquals(listOf(30_000L..40_000L), musicPieces(30_000L..40_000L, 10_000))
        assertEquals(listOf(0L..8_000L, 0L..8_000L, 0L..4_000L), musicPieces(0L..8_000L, 20_000))
        assertEquals(listOf(0L..8_000L), musicPieces(0L..8_000L, 8_000))
        assertEquals(emptyList<LongRange>(), musicPieces(0L..8_000L, 0))
    }

    @Test fun musicPositionFollowsOutputTimeAndLoopsShortSongs() {
        val window = musicWindow(180_000, 30_000, 10_000)
        assertEquals(30_000L, musicPosition(180_000, window, 0))
        assertEquals(35_000L, musicPosition(180_000, window, 5_000))
        assertNull("silent past the window", musicPosition(180_000, window, 10_000))
        assertNull(musicPosition(180_000, window, -1))
        assertEquals("short song loops", 2_000L, musicPosition(8_000, musicWindow(8_000, 0, 20_000), 10_000))
    }

    @Test fun audioMixReportsReencodingAndSizeEstimateAccountsForIt() {
        assertFalse(AudioMix().changesAudio)
        assertTrue(AudioMix(originalVolume = 0f).changesAudio)
        fun bytes(mixed: Boolean) = videoExportPlan(1920, 1080, 30f, 8_000_000, 96_000, 60_000, ExportOptions(), mixed).estimatedBytes!!
        assertTrue(bytes(true) > bytes(false))
    }

    @Test fun volumeBoostClipsInsteadOfWrapping() {
        val volume = VolumeProcessor(2f)
        volume.configure(androidx.media3.common.audio.AudioProcessor.AudioFormat(44_100, 1, androidx.media3.common.C.ENCODING_PCM_16BIT))
        volume.flush()
        val input = java.nio.ByteBuffer.allocateDirect(8).order(java.nio.ByteOrder.nativeOrder())
        listOf<Short>(20_000, -20_000, 1_000, 0).forEach { input.putShort(it) }
        input.flip()
        volume.queueInput(input)
        val output = volume.output
        assertEquals(listOf<Short>(32_767, -32_768, 2_000, 0), List(4) { output.short })
    }

    @Test fun customAtSourceSizeAndFullQualityMatchesOriginal() {
        fun plan(o: ExportOptions) = videoExportPlan(3840, 3360, 61f, 124_000_000, 192_000, 43_200, o)
        val original = plan(ExportOptions())
        val custom = plan(ExportOptions(original = false, longEdge = 0, quality = 100))
        assertEquals(original.bitrate, custom.bitrate)
        assertEquals(original.estimatedBytes, custom.estimatedBytes)
        assertEquals(original.bitrate, plan(ExportOptions(original = false, longEdge = 3840, quality = 100)).bitrate)
        // Downscaling, lower frame rates and quality only ever lower the rate below the source.
        val smaller = plan(ExportOptions(original = false, longEdge = 1920, quality = 100)).bitrate
        assertTrue(smaller < original.bitrate && smaller > original.bitrate / 4)
        assertTrue(plan(ExportOptions(original = false, longEdge = 0, fps = 30, quality = 100)).bitrate < original.bitrate)
        assertEquals(original.bitrate / 2.0, plan(ExportOptions(original = false, longEdge = 0, quality = 50)).bitrate.toDouble(), 1.0)
        // Low-bitrate sources: the 500 kbps floor must not pin every quality to the source rate.
        fun small(q: Int) = videoExportPlan(640, 360, 30f, 614_000, 70_000, 2_000, ExportOptions(original = false, quality = q)).bitrate
        assertTrue(small(10) < small(90))
    }

    @Test fun originalBitrateNeverUndercutsSource() {
        assertTrue(ExportSizing.bitrate(1920, 1080, 30f, 100, 80_000_000, true) >= 80_000_000)
        assertTrue(ExportSizing.bitrate(1920, 1080, 30f, 100, 0, false) > ExportSizing.bitrate(1920, 1080, 30f, 50, 0, false))
    }
    @Test fun frameRateIgnoresHiddenLeadInFrames() {
        // A trimmed GoPro clip: 59 lead-in frames before zero, then 59.94 fps.
        val times = (-59 until 62).map { it * 1_001_000L / 60 }
        assertEquals(59.94f, frameRateFromTimes(times)!!, 0.01f)
        assertEquals(60f, wholeFrameRate(frameRateFromTimes(times)!!))
    }
    @Test fun exactSixtyStaysSixtyDespiteMicrosecondRounding() {
        val times = (0 until 121).map { it * 1_000_000L / 60 }
        assertEquals(60f, wholeFrameRate(frameRateFromTimes(times)!!))
    }
    @Test fun frameRatesRoundHalfUp() {
        assertEquals(24f, wholeFrameRate(23.976f))
        assertEquals(30f, wholeFrameRate(29.97f))
        assertEquals(60f, wholeFrameRate(60.002f))
        assertEquals(13f, wholeFrameRate(12.5f))
        assertEquals(1f, wholeFrameRate(0.2f))
    }
    @Test fun tooFewFramesLeaveTheRateToAndroid() {
        assertNull(frameRateFromTimes((0 until 5).map { it * 16_683L }))
    }
}

package com.aquarestore.app

import android.Manifest
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaWorkflowTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()
    private val created = mutableListOf<Uri>()
    private lateinit var scenario: ActivityScenario<MainActivity>

    @Before fun launch() {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        Exports.status.value = ExportStatus()
    }
    @After fun clean() {
        runBlocking { withContext(Dispatchers.Main) { if (Exports.status.value.busy) Exports.cancel(app) } }
        scenario.close()
        created.forEach { app.contentResolver.delete(it, null, null) }
        Exports.status.value = ExportStatus()
    }

    private fun media(asset: String, mime: String): Uri {
        val collection = if (mime.startsWith("video")) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else if (mime.startsWith("audio")) MediaStore.Audio.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val uri = app.contentResolver.insert(collection, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "audit-${System.nanoTime()}-$asset")
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        })!!
        created += uri
        app.contentResolver.openOutputStream(uri)!!.use { out ->
            InstrumentationRegistry.getInstrumentation().context.assets.open(asset).use { it.copyTo(out) }
        }
        app.contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        return uri
    }

    private fun photo(width: Int = 640, height: Int = 360): Uri {
        val uri = app.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "audit-${System.nanoTime()}.png")
            put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
        })!!
        created += uri
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val row = IntArray(width)
        for (y in 0 until height) {
            for (x in row.indices) row[x] = (255 shl 24) or ((x % 80) shl 16) or ((60 + y % 160) shl 8) or (100 + (x + y) % 150)
            bitmap.setPixels(row, 0, width, 0, y, width, 1)
        }
        app.contentResolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        return uri
    }

    private suspend fun export(source: SourceMedia, options: ExportOptions, audio: AudioMix = AudioMix()): Uri {
        withContext(Dispatchers.Main) { Exports.start(app, ExportRequest(source, Grade.Blue, options, false, audio)) }
        val result = withTimeout(60_000) { Exports.status.first { !it.busy } }
        assertNull("Export error: ${result.error}", result.error)
        assertEquals("saved", result.stage)
        assertNotNull(result.uri)
        return result.uri!!.also { created += it }
    }

    private suspend fun batch(photos: List<Uri>, selection: ExportSelection = ExportSelection()): ExportStatus {
        withContext(Dispatchers.Main) { Exports.start(app, BatchPhotoRequest(photos, selection, false)) }
        return withTimeout(60_000) { Exports.status.first { !it.busy } }.also {
            created += it.batch!!.saved
            assertNull(it.error)
        }
    }

    @Test fun batchUsesEachPhotosDefaultRestorationAndRecommendedSize() = runBlocking {
        val photos = listOf(photo(640, 360), photo(3000, 1500))
        val result = batch(photos)
        assertEquals("saved", result.stage)
        assertEquals(2, result.batch!!.saved.size)
        assertTrue(result.batch.failures.isEmpty())
        for ((index, saved) in result.batch.saved.withIndex()) {
            val source = MediaIO.inspect(app, photos[index])
            val options = ExportSelection().photoOptions(source.width, source.height, source.mime)
            val expected = MediaIO.bitmap(app, source.uri, if (options.original) 0 else options.longEdge)
            val actual = MediaIO.bitmap(app, saved, 0)
            try {
                MediaIO.gradeBitmap(expected, MediaIO.analyze(app, source).grade) {}
                assertEquals(expected.width, actual.width)
                assertEquals(expected.height, actual.height)
                assertTrue("Batch must use the same automatic grade as importing each photo", expected.sameAs(actual))
            } finally { expected.recycle(); actual.recycle() }
        }
    }

    @Test fun batchRejectsVideoAndContinuesAfterAnUnreadablePhoto() = runBlocking {
        val bad = app.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "audit-corrupt-${System.nanoTime()}.png")
            put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
        })!!.also { created += it }
        app.contentResolver.openOutputStream(bad)!!.use { it.write(byteArrayOf(1, 2, 3)) }
        val result = batch(listOf(photo(), media("audit-video.mp4", "video/mp4"), bad, photo()),
            ExportSelection(mode = ExportMode.CUSTOM, longEdge = 320, quality = 72))
        assertEquals("batchFinished", result.stage)
        assertEquals(2, result.batch!!.saved.size)
        assertEquals(2, result.batch.failures.size)
        assertEquals(listOf("batchPhotosOnly", "photoUnreadable"), result.batch.failures.map { it.error })
        result.batch.saved.forEach {
            val saved = MediaIO.inspect(app, it)
            assertEquals(320, saved.width)
            assertEquals("image/jpeg", saved.mime)
        }
        assertTrue(app.cacheDir.listFiles()!!.none { it.name.startsWith("export-") })
    }

    @Test fun finishedExportNotifiesOnlyWhileTheAppIsInTheBackground() = runBlocking {
        if (Build.VERSION.SDK_INT >= 33) InstrumentationRegistry.getInstrumentation().uiAutomation
            .grantRuntimePermission(app.packageName, Manifest.permission.POST_NOTIFICATIONS)
        val notifications = app.getSystemService(NotificationManager::class.java)
        fun result() = notifications.activeNotifications.firstOrNull { it.id == EXPORT_RESULT_NOTIFICATION }
        // The system posts and removes notifications asynchronously, after notify() and cancel() return.
        suspend fun awaitResult(shown: Boolean) = withTimeoutOrNull(5_000) {
            while ((result() != null) != shown) delay(100)
        } != null
        batch(listOf(photo()))
        assertFalse("The app shows the result itself while it is open", awaitResult(shown = true))
        scenario.moveToState(Lifecycle.State.CREATED)
        Exports.status.value = ExportStatus()
        val result = batch(listOf(photo(), media("audit-video.mp4", "video/mp4")))
        assertEquals("batchFinished", result.stage)
        assertTrue("A finished export in the background posts its result", awaitResult(shown = true))
        val text = result()!!.notification.extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString()
        assertTrue(text, text.contains("1 of 2 photos saved") && text.contains("photos only"))
        scenario.moveToState(Lifecycle.State.RESUMED)
        assertTrue("Returning to the app clears the notification", awaitResult(shown = false))
    }

    @Test fun batchCancellationKeepsCompletedPhotosAndAllowsAnotherExport() = runBlocking {
        val photos = listOf(photo(), photo(3072, 3072), photo())
        withContext(Dispatchers.Main) {
            Exports.start(app, BatchPhotoRequest(photos, ExportSelection(mode = ExportMode.ORIGINAL), false))
        }
        withTimeout(30_000) { Exports.status.first { it.batch?.saved?.isNotEmpty() == true } }
        withContext(Dispatchers.Main) { Exports.cancel(app) }
        val result = withTimeout(30_000) { Exports.status.first { !it.busy } }
        created += result.batch!!.saved
        assertEquals("cancelled", result.stage)
        assertEquals(1, result.batch.saved.size)
        assertEquals(1, result.batch.completed)
        assertTrue(app.cacheDir.listFiles()!!.none { it.name.startsWith("export-") })
        assertEquals(640, MediaIO.inspect(app, result.batch.saved.single()).width)
        export(MediaIO.inspect(app, photos.first()), ExportOptions(original = false, longEdge = 320))
        Unit
    }

    @Test fun batchRequestEnforcesSelectionLimitAndNoDuplicates() {
        fun rejected(photos: List<Uri>) {
            assertThrows(IllegalArgumentException::class.java) { BatchPhotoRequest(photos, ExportSelection(), false) }
        }
        rejected(emptyList())
        rejected(List(MAX_BATCH_PHOTOS + 1) { Uri.parse("content://photos/$it") })
        rejected(List(2) { Uri.parse("content://photos/1") })
        assertEquals(MAX_BATCH_PHOTOS, BatchPhotoRequest(List(MAX_BATCH_PHOTOS) { Uri.parse("content://photos/$it") }, ExportSelection(), false).photos.size)
    }

    @Test fun videoBatchRestoresEachVideoWholeAndSkipsPhotos() = runBlocking {
        val videos = listOf(media("audit-video.mp4", "video/mp4"), photo(), media("audit-rotated.mp4", "video/mp4"))
        withContext(Dispatchers.Main) { Exports.start(app, BatchVideoRequest(videos, ExportSelection(), false)) }
        assertTrue(Exports.status.value.batch!!.videos)
        val result = withTimeout(180_000) { Exports.status.first { !it.busy } }
        created += result.batch!!.saved
        assertNull(result.error)
        assertEquals("batchFinished", result.stage)
        assertEquals(listOf("batchVideosOnly"), result.batch.failures.map { it.error })
        assertEquals(2, result.batch.saved.size)
        for ((saved, original) in result.batch.saved.zip(listOf(videos[0], videos[2]))) {
            val source = MediaIO.inspect(app, original)
            val output = MediaIO.inspect(app, saved)
            assertTrue(output.video)
            val options = ExportSelection().videoOptions(source.width, source.height, source.fps)
            val expected = if (options.original) source.width to source.height
                else ExportSizing.dimensions(source.width, source.height, options.longEdge, true)
            assertEquals(expected.first to expected.second, output.width to output.height)
            // The whole clip, at normal speed.
            assertEquals(source.durationMs.toDouble(), output.durationMs.toDouble(), 150.0)
        }
        assertTrue(app.cacheDir.listFiles()!!.none { it.name.startsWith("export-") })
    }

    @Test fun videoBatchRequestEnforcesSelectionLimitAndNoDuplicates() {
        fun rejected(videos: List<Uri>) {
            assertThrows(IllegalArgumentException::class.java) { BatchVideoRequest(videos, ExportSelection(), false) }
        }
        rejected(emptyList())
        rejected(List(MAX_BATCH_VIDEOS + 1) { Uri.parse("content://videos/$it") })
        rejected(List(2) { Uri.parse("content://videos/1") })
        val request = BatchVideoRequest(List(MAX_BATCH_VIDEOS) { Uri.parse("content://videos/$it") }, ExportSelection(), false)
        assertEquals(MAX_BATCH_VIDEOS, request.batchStatus()!!.total)
        val options = request.options(SourceMedia(Uri.EMPTY, "clip.mp4", true, 3840, 2160, 60_000, 60f, 40_000_000))
        assertEquals(1f, options.speed)
        assertEquals(0L, options.startMs)
        assertEquals(0L, options.endMs)
    }

    /** Durations in ms of the audio and video tracks of an exported file. */
    private fun tracks(uri: Uri): Map<String, Long> {
        val extractor = android.media.MediaExtractor()
        try {
            extractor.setDataSource(app, uri, null)
            return (0 until extractor.trackCount).map { extractor.getTrackFormat(it) }.associate {
                it.getString(android.media.MediaFormat.KEY_MIME)!!.substringBefore('/') to it.getLong(android.media.MediaFormat.KEY_DURATION) / 1000
            }
        } finally { extractor.release() }
    }

    @Test fun originalVideoExportCanBeRepeatedWithSourceName() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        repeat(2) {
            val uri = export(source, ExportOptions())
            app.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertTrue(cursor.getString(0).startsWith("AquaRestore_"))
            }
        }
    }

    @Test fun backgroundMusicReplacesMutedOriginalSound() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        val song = Soundtrack.inspect(app, media("audit-music.m4a", "audio/mp4"))
        assertEquals(5_000.0, song.durationMs.toDouble(), 100.0)
        val result = tracks(export(source, ExportOptions(), AudioMix(originalVolume = 0f, music = song, musicStartMs = 2_000)))
        assertEquals(setOf("audio", "video"), result.keys)
        assertEquals(source.durationMs.toDouble(), result["audio"]!!.toDouble(), 180.0)
    }

    @Test fun mutingWithoutMusicDropsTheAudioTrack() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        assertEquals(setOf("video"), tracks(export(source, ExportOptions(), AudioMix(originalVolume = 0f))).keys)
    }

    @Test fun originalSoundAndMusicMixIntoOneTrack() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        val song = Soundtrack.inspect(app, media("audit-music.m4a", "audio/mp4"))
        val result = tracks(export(source, ExportOptions(), AudioMix(originalVolume = 0.5f, music = song, musicVolume = 0.5f)))
        assertEquals(setOf("audio", "video"), result.keys)
        assertEquals(source.durationMs.toDouble(), result["audio"]!!.toDouble(), 180.0)
    }

    @Test fun speedingUpKeepsTheSourceFrameRate() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        for (speed in listOf(2f, 4f)) {
            val uri = export(source, ExportOptions(speed = speed))
            val extractor = android.media.MediaExtractor()
            try {
                extractor.setDataSource(app, uri, null)
                extractor.selectTrack((0 until extractor.trackCount).first { extractor.getTrackFormat(it).getString("mime")!!.startsWith("video/") })
                val timestamps = mutableListOf<Long>()
                while (extractor.sampleTime >= 0) { timestamps += extractor.sampleTime; if (!extractor.advance()) break }
                val expected = source.fps * source.durationMs / 1000 / speed
                assertTrue("speed=$speed: expected about $expected frames, got ${timestamps.size}", kotlin.math.abs(timestamps.size - expected) <= 2)
                val fps = (timestamps.size - 1) * 1_000_000.0 / (timestamps.last() - timestamps.first())
                assertEquals("speed=$speed frame rate", source.fps.toDouble(), fps, 1.5)
            } finally { extractor.release() }
        }
    }

    @Test fun boostedVolumesExport() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        val song = Soundtrack.inspect(app, media("audit-music.m4a", "audio/mp4"))
        val result = tracks(export(source, ExportOptions(), AudioMix(originalVolume = 2f, music = song, musicVolume = 1.5f)))
        assertEquals(source.durationMs.toDouble(), result["audio"]!!.toDouble(), 180.0)
    }

    @Test fun shortSongRepeatsAtNormalSpeed() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        val song = Soundtrack.inspect(app, media("audit-music-short.m4a", "audio/mp4"))
        val result = tracks(export(source, ExportOptions(), AudioMix(originalVolume = 0f, music = song)))
        assertEquals(result["video"]!!.toDouble(), result["audio"]!!.toDouble(), 250.0)
    }

    @Test fun mutedSoundWithSpeedChangeStillExports() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        val result = tracks(export(source, ExportOptions(speed = 2f), AudioMix(originalVolume = 0f)))
        assertEquals(source.durationMs / 2.0, result["video"]!!.toDouble(), 180.0)
    }

    @Test fun songShorterThanTheVideoRepeatsToTheEnd() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        val song = Soundtrack.inspect(app, media("audit-music.m4a", "audio/mp4"))
        // 0.25× turns 2 s of video into 8 s, longer than the 5 s song.
        val result = tracks(export(source, ExportOptions(speed = 0.25f), AudioMix(originalVolume = 0f, music = song)))
        assertEquals(source.durationMs / 0.25, result["video"]!!.toDouble(), 250.0)
        assertEquals(result["video"]!!.toDouble(), result["audio"]!!.toDouble(), 250.0)
    }

    @Test fun trimCutsVideoAndAudioToTheSelectedRange() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        val start = source.durationMs / 4
        val end = source.durationMs * 3 / 4
        val uri = export(source, ExportOptions(startMs = start, endMs = end, speed = 2f))
        val extractor = android.media.MediaExtractor()
        try {
            extractor.setDataSource(app, uri, null)
            val durations = (0 until extractor.trackCount).map { extractor.getTrackFormat(it) }
                .filter { it.getString(android.media.MediaFormat.KEY_MIME)!!.let { mime -> mime.startsWith("audio/") || mime.startsWith("video/") } }
                .map { it.getLong(android.media.MediaFormat.KEY_DURATION) / 1000 }
            assertEquals(2, durations.size)
            durations.forEach { assertEquals("trimmed track duration", (end - start) / 2.0, it.toDouble(), 180.0) }
        } finally { extractor.release() }
    }

    @Test fun speedChangesVideoAndAudioDurationTogether() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        for (speed in listOf(0.5f, 2f, 4f)) {
            val uri = export(source, ExportOptions(speed = speed))
            val result = MediaIO.inspect(app, uri)
            assertEquals(source.width, result.width)
            val extractor = android.media.MediaExtractor()
            try {
                extractor.setDataSource(app, uri, null)
                val durations = (0 until extractor.trackCount).map { extractor.getTrackFormat(it) }
                    .filter { it.getString(android.media.MediaFormat.KEY_MIME)!!.let { mime -> mime.startsWith("audio/") || mime.startsWith("video/") } }
                    .map { it.getLong(android.media.MediaFormat.KEY_DURATION) / 1000 }
                assertEquals(2, durations.size)
                durations.forEach { duration ->
                    assertEquals("speed=$speed track duration", source.durationMs / speed.toDouble(), duration.toDouble(), 180.0)
                }
            } finally { extractor.release() }
        }
    }

    @Test fun imageOriginalAndRepeatedCustomExportsWork() = runBlocking {
        val source = MediaIO.inspect(app, photo())
        val original = export(source, ExportOptions(quality = ORIGINAL_JPEG_QUALITY))
        assertEquals("image/jpeg", app.contentResolver.getType(original))
        val full = MediaIO.inspect(app, original)
        assertEquals(640, full.width); assertEquals(360, full.height)
        val lossless = export(source, ExportOptions(png = true))
        assertEquals("image/png", app.contentResolver.getType(lossless))
        assertEquals(640, MediaIO.inspect(app, lossless).width)
        // Start a new job immediately after success to catch foreground-service teardown races.
        val low = export(source, ExportOptions(original = false, longEdge = 320, quality = 15))
        val high = export(source, ExportOptions(original = false, longEdge = 320, quality = 98))
        val resized = MediaIO.inspect(app, high)
        assertEquals(320, resized.width); assertEquals(180, resized.height)
        assertEquals("image/jpeg", app.contentResolver.getType(high))
        fun size(uri: Uri) = app.contentResolver.openAssetFileDescriptor(uri, "r")!!.use { it.length }
        assertTrue("JPEG quality should affect actual bytes", size(high) > size(low))
    }

    @Test fun exifRotatedPhotoKeepsPortraitOrientation() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-exif.jpg", "image/jpeg"))
        assertEquals(360, source.width); assertEquals(640, source.height)
        val result = MediaIO.inspect(app, export(source, ExportOptions(original = false, longEdge = 320, png = true)))
        assertEquals(180, result.width); assertEquals(320, result.height)
    }

    @Test fun customVideoResolutionFrameRateAndAudioAreReal() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-video.mp4", "video/mp4"))
        val uri = export(source, ExportOptions(original = false, longEdge = 320, fps = 24, quality = 80))
        val result = MediaIO.inspect(app, uri)
        assertEquals(320, result.width); assertEquals(180, result.height)
        val extractor = android.media.MediaExtractor()
        try {
            extractor.setDataSource(app, uri, null)
            assertTrue((0 until extractor.trackCount).any { extractor.getTrackFormat(it).getString("mime")?.startsWith("audio/") == true })
            val video = (0 until extractor.trackCount).first { extractor.getTrackFormat(it).getString("mime")?.startsWith("video/") == true }
            extractor.selectTrack(video)
            val timestamps = mutableListOf<Long>()
            while (extractor.sampleTime >= 0) { timestamps += extractor.sampleTime; if (!extractor.advance()) break }
            assertTrue("Expected about 48 frames, got ${timestamps.size}", timestamps.size in 46..49)
            assertTrue(timestamps.zipWithNext().all { (a, b) -> b > a })
            assertTrue(kotlin.math.abs((timestamps.size - 1) * 1_000_000.0 / (timestamps.last() - timestamps.first()) - 24) < 1)
        } finally { extractor.release() }
    }

    @Test fun rotatedVideoExportPreservesDisplayedAspectRatio() = runBlocking {
        val source = MediaIO.inspect(app, media("audit-rotated.mp4", "video/mp4"))
        assertEquals(360, source.width); assertEquals(640, source.height)
        val result = MediaIO.inspect(app, export(source, ExportOptions(original = false, longEdge = 320)))
        assertEquals(180, result.width); assertEquals(320, result.height)
    }

    @Test fun cancelledExportCanBeFollowedImmediatelyByAnotherExport() = runBlocking {
        val source = MediaIO.inspect(app, photo(2048, 2048))
        withContext(Dispatchers.Main) { Exports.start(app, ExportRequest(source, Grade.Blue, ExportOptions(), false)) }
        withTimeout(20_000) { Exports.status.first { it.progress != null || !it.busy } }
        withContext(Dispatchers.Main) { Exports.cancel(app) }
        val result = withTimeout(20_000) { Exports.status.first { !it.busy } }
        assertEquals("cancelled", result.stage)
        assertNull(result.uri)
        assertTrue(app.cacheDir.listFiles()!!.none { it.name.startsWith("export-") })
        export(source, ExportOptions(original = false, longEdge = 320))
        Unit
    }

    @Test fun imageEditorCompareResetRapidChangesAndImportFailureRecover() = runBlocking {
        val uri = photo()
        val store = ViewModelStore()
        val model = withContext(Dispatchers.Main) { ViewModelProvider(store, ViewModelProvider.AndroidViewModelFactory.getInstance(app))[EditorModel::class.java] }
        try {
            withContext(Dispatchers.Main) { model.import(uri) }
            withTimeout(20_000) { model.previewGraded.first { it != null } }
            withContext(Dispatchers.Main) {
                model.setCompare(true)
                model.setGrade(model.grade.value.copy(strength = 0f))
                assertFalse(model.compare.value)
            }
            withTimeout(10_000) {
                while (model.previewGraded.value!!.getPixel(20, 20) != model.previewOriginal.value!!.getPixel(20, 20)) delay(25)
            }
            withContext(Dispatchers.Main) {
                repeat(100) { model.setGrade(model.grade.value.copy(strength = it / 99f)) }
                model.reset()
                assertEquals(model.analysis.value!!.grade, model.grade.value)
                model.import(Uri.parse("content://missing-provider/broken.jpg"))
            }
            withTimeout(10_000) { model.error.first { it != null } }
            withContext(Dispatchers.Main) { model.import(uri) }
            withTimeout(20_000) { model.previewGraded.first { it != null } }
            assertNull(model.error.value)
        } finally { withContext(Dispatchers.Main) { store.clear() } }
    }

    @Test fun preferencesPersistAcrossEditorInstances() = runBlocking {
        val first = EditorModel(app)
        first.preference("language", "zh"); first.preference("theme", "dark")
        val second = EditorModel(app)
        assertEquals("zh", second.language.value); assertEquals("dark", second.theme.value)
        second.preference("language", "system"); second.preference("theme", "system")
    }
}

package com.aquarestore.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class ShareMediaTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    @Test fun photoComparisonsEncodeAndSaveWithoutUpscaling() = runBlocking {
        for ((width, height) in listOf(160 to 240, 240 to 160, 200 to 200, 319 to 239, 1600 to 900)) {
            val input = File(context.cacheDir, "comparison-test.png")
            val source = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            source.eraseColor(Color.rgb(70, 110, 150))
            android.graphics.Canvas(source).drawRect(0f, 0f, width / 2f, height / 2f,
                android.graphics.Paint().apply { color = Color.rgb(180, 60, 80) })
            input.outputStream().use { source.compress(Bitmap.CompressFormat.PNG, 100, it) }; source.recycle()
            val media = SourceMedia(Uri.fromFile(input), input.name, false, width, height)
            val items = ShareMediaMaker.make(context, ExportRequest(media, Grade.Neutral, ExportOptions(), false))
            try {
                assertEquals(2, items.size); assertTrue(items[0].video); assertFalse(items[1].video)
                val collage = BitmapFactory.decodeFile(items[1].file.path)
                if (height > width) assertTrue(collage.width >= collage.height) else assertTrue(collage.height > collage.width)
                collage.recycle()
                MediaMetadataRetriever().use { retriever ->
                    retriever.setDataSource(items[0].file.path)
                    val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
                    assertTrue("Duration: $duration", duration in 5950..6050)
                    val rawWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt()
                    val rawHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt()
                    val rotated = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() in listOf(90, 270)
                    assertEquals(SharingPlan.videoSize(width, height).first, if (rotated) rawHeight else rawWidth)
                    assertEquals(SharingPlan.videoSize(width, height).second, if (rotated) rawWidth else rawHeight)
                    val first = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST)!!
                    val last = retriever.getFrameAtTime(5_900_000, MediaMetadataRetriever.OPTION_CLOSEST)!!
                    try {
                        for ((x, y) in listOf(first.width / 4 to first.height / 4, first.width * 3 / 4 to first.height * 3 / 4)) {
                            val a = first.getPixel(x, y); val b = last.getPixel(x, y)
                            assertTrue(kotlin.math.abs(Color.red(a) - Color.red(b)) < 15)
                            assertTrue(kotlin.math.abs(Color.blue(a) - Color.blue(b)) < 15)
                        }
                    } finally { first.recycle(); last.recycle() }
                }
                val first = ShareMediaMaker.save(context, items[0])
                try { assertEquals(first, ShareMediaMaker.save(context, items[0])) }
                finally { context.contentResolver.delete(first, null, null) }
            } finally { items.forEach { it.file.delete() }; input.delete() }
        }
    }
    @Test fun videoComparisonUsesTrimmedSourceAndCapsFrameRate() = runBlocking {
        val collection = android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val uri = context.contentResolver.insert(collection, android.content.ContentValues().apply {
            put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, "comparison-native-test.mp4")
            put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
        })!!
        context.contentResolver.openOutputStream(uri)!!.use { output ->
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().context.assets.open("audit-video.mp4").use { it.copyTo(output) }
        }
        var items: List<ShareMedia> = emptyList()
        try {
            val source = MediaIO.inspect(context, uri)
            val start = source.durationMs / 4
            val end = source.durationMs * 3 / 4
            val request = ExportRequest(source, Grade.Neutral, ExportOptions(original = false, speed = 2f, startMs = start, endMs = end), false)
            val began = android.os.SystemClock.elapsedRealtime()
            items = ShareMediaMaker.make(context, request)
            android.util.Log.i("AquaRestoreTest", "Sequential comparison: ${android.os.SystemClock.elapsedRealtime() - began} ms")
            assertEquals(1, items.size)
            assertTrue(items.single().video)
            MediaMetadataRetriever().use { retriever ->
                retriever.setDataSource(items.single().file.path)
                val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
                val expected = SharingPlan.clip(((end - start) / 2)).second
                assertTrue("$duration vs $expected", kotlin.math.abs(duration - expected) <= 100)
            }
            val extractor = android.media.MediaExtractor()
            try {
                extractor.setDataSource(items.single().file.path)
                val index = (0 until extractor.trackCount).first { extractor.getTrackFormat(it).getString(android.media.MediaFormat.KEY_MIME)!!.startsWith("video/") }
                extractor.selectTrack(index)
                var frames = 0
                var last = 0L
                do { frames++; last = maxOf(last, extractor.sampleTime) } while (extractor.advance())
                assertTrue("$frames frames in $last us", frames <= (last / 1_000_000.0 * 30 + 2).toInt())
            } finally { extractor.release() }
        } finally { items.forEach { it.file.delete() }; context.contentResolver.delete(uri, null, null) }
    }

}

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
            input.outputStream().use { source.compress(Bitmap.CompressFormat.PNG, 100, it) }; source.recycle()
            val media = SourceMedia(Uri.fromFile(input), input.name, false, width, height)
            val items = ShareMediaMaker.make(context, ExportRequest(media, Grade.Neutral, ExportOptions(), false), Uri.fromFile(input))
            try {
                assertEquals(2, items.size); assertTrue(items[0].video); assertFalse(items[1].video)
                val collage = BitmapFactory.decodeFile(items[1].file.path)
                if (height > width) assertTrue(collage.width >= collage.height) else assertTrue(collage.height > collage.width)
                collage.recycle()
                MediaMetadataRetriever().use { retriever ->
                    retriever.setDataSource(items[0].file.path)
                    val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
                    assertTrue("Duration: $duration", duration in 5950..6050)
                    assertEquals(SharingPlan.videoSize(width, height).first, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)!!.toInt())
                    assertEquals(SharingPlan.videoSize(width, height).second, retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)!!.toInt())
                }
                val first = ShareMediaMaker.save(context, items[0])
                try { assertEquals(first, ShareMediaMaker.save(context, items[0])) }
                finally { context.contentResolver.delete(first, null, null) }
            } finally { items.forEach { it.file.delete() }; input.delete() }
        }
    }
}

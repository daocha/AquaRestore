package com.aquarestore.app

import android.content.ContentUris
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest

@RunWith(AndroidJUnit4::class)
class PhotoAnalysisCaptureTest {
    @Test fun savedPhotoMatchesAnalysisPixelsAndSourceIdentity() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val stem = "photo-capture-${System.nanoTime()}"
        val photo = File(app.cacheDir, "$stem-original.png")
        val imageName = "$stem-photo-analysis.png"
        val infoName = "$stem-photo-source.txt"
        val resolver = app.contentResolver
        fun saved(name: String): Uri? = resolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID), "${MediaStore.Downloads.DISPLAY_NAME} = ?", arrayOf(name), null)?.use {
            if (it.moveToFirst()) ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, it.getLong(0)) else null
        }
        fun pixels(bitmap: Bitmap) = IntArray(bitmap.width * bitmap.height).also {
            bitmap.getPixels(it, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        }
        try {
            val input = Bitmap.createBitmap(320, 200, Bitmap.Config.ARGB_8888)
            input.setPixels(IntArray(320 * 200) { i -> 0xff000000.toInt() or
                ((i % 256) shl 16) or (((i / 320) % 256) shl 8) or 123 }, 0, 320, 0, 0, 320, 200)
            photo.outputStream().use { assertTrue(input.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            input.recycle()
            val source = SourceMedia(Uri.fromFile(photo), photo.name, false, 320, 200, mime = "image/png")
            val expected = MediaIO.bitmap(app, source.uri, 192)
            try {
                assertEquals(1, MediaIO.saveAnalysisFrames(app, source))
                val image = resolver.openInputStream(requireNotNull(saved(imageName))).use { BitmapFactory.decodeStream(it) }!!
                try {
                    assertEquals(expected.width, image.width)
                    assertEquals(expected.height, image.height)
                    assertArrayEquals(pixels(expected), pixels(image))
                } finally { image.recycle() }
            } finally { expected.recycle() }
            val info = resolver.openInputStream(requireNotNull(saved(infoName)))!!.bufferedReader().use { it.readText() }
            val hash = MessageDigest.getInstance("SHA-256").digest(photo.readBytes())
                .joinToString("") { "%02x".format(it.toInt() and 255) }
            assertTrue(info.contains("name=${photo.name}\n"))
            assertTrue(info.contains("size=320x200\n"))
            assertTrue(info.contains("bytes=${photo.length()}\n"))
            assertTrue(info.contains("sha256=$hash\n"))
        } finally {
            listOf(imageName, infoName).forEach { name -> saved(name)?.let { resolver.delete(it, null, null) } }
            photo.delete()
        }
    }
}

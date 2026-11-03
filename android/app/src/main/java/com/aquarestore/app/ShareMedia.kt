package com.aquarestore.app

import android.content.*
import android.graphics.*
import android.media.*
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import java.io.File
import java.util.UUID
import kotlin.math.*

data class ShareMedia(val file: File, val video: Boolean, var saved: Uri? = null) {
    val mime: String get() = if (video) "video/mp4" else if (file.extension == "png") "image/png" else "image/jpeg"
}

object ShareMediaMaker {
    private fun destination(context: Context, ext: String) = File(File(context.cacheDir, "share-previews").apply { mkdirs() }, "${UUID.randomUUID()}.$ext")
    suspend fun make(context: Context, request: ExportRequest): List<ShareMedia> = withContext(Dispatchers.Default) {
        val result = mutableListOf<ShareMedia>()
        var parallelMovie: Deferred<List<ShareMedia>>? = null
        try {
            if (!request.source.video) {
                val movie = async { video(context, request) }
                parallelMovie = movie
                val o = ExportRecommendation.photo(request.source.width, request.source.height, request.source.mime)
                val original = MediaIO.bitmap(context, request.source.uri, if (o.original) 0 else o.longEdge)
                try {
                    val after = original.copy(Bitmap.Config.ARGB_8888, true)
                    try {
                        MediaIO.gradeBitmap(after, request.grade)
                        val collage = collage(context, original, after)
                        try {
                            val file = destination(context, if (o.png) "png" else "jpg")
                            try { file.outputStream().use { check(collage.compress(if (o.png) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, o.quality, it)) }; result += ShareMedia(file, false) }
                            catch (e: Exception) { file.delete(); throw e }
                        } finally { collage.recycle() }
                        result.addAll(0, movie.await())
                    } finally { after.recycle() }
                } finally { original.recycle() }
            } else {
                result += video(context, request)
            }
        } catch (e: CancellationException) { result.forEach { it.file.delete() }; throw e }
        catch (e: Exception) { android.util.Log.w("AquaRestore", "Comparison preview unavailable", e) }
        catch (_: OutOfMemoryError) { android.util.Log.w("AquaRestore", "Comparison preview needs too much memory") }
        finally {
            parallelMovie?.let { movie ->
                if (result.none { it.video }) {
                    movie.cancel()
                    withContext(NonCancellable) { runCatching { movie.await() }.getOrDefault(emptyList()).forEach { it.file.delete() } }
                }
            }
        }
        result
    }

    private fun collage(context: Context, before: Bitmap, after: Bitmap): Bitmap {
        val sideBySide = before.height > before.width
        val rawW = before.width * if (sideBySide) 2 else 1
        val rawH = before.height * if (sideBySide) 1 else 2
        // Very tall and panoramic sources get padding, never a crop or a stretched photograph.
        val targetW = if (sideBySide) max(rawW, rawH) else rawW
        val targetH = if (sideBySide) rawH else max(rawH, rawW + 1)
        val scale = min(1.0, 2560.0 / max(targetW, targetH))
        val w = max(1, (targetW * scale).toInt()); val h = max(1, (targetH * scale).toInt())
        val image = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(image); canvas.drawColor(Color.rgb(12, 23, 31))
        val first = if (sideBySide) RectF(0f, 0f, w / 2f, h.toFloat()) else RectF(0f, 0f, w.toFloat(), h / 2f)
        val second = if (sideBySide) RectF(w / 2f, 0f, w.toFloat(), h.toFloat()) else RectF(0f, h / 2f, w.toFloat(), h.toFloat())
        fit(canvas, before, first); fit(canvas, after, second)
        label(canvas, "Original", first.left + w * .025f, first.top + h * .055f, min(w, h) * .035f)
        label(canvas, "Restored", second.left + w * .025f, second.top + h * .055f, min(w, h) * .035f)
        brand(context, canvas, w, h)
        return image
    }
    private fun fit(canvas: Canvas, bitmap: Bitmap, rect: RectF) {
        val scale = min(rect.width() / bitmap.width, rect.height() / bitmap.height)
        val w = bitmap.width * scale; val h = bitmap.height * scale
        canvas.drawBitmap(bitmap, null, RectF(rect.centerX() - w/2, rect.centerY() - h/2, rect.centerX() + w/2, rect.centerY() + h/2), Paint(Paint.FILTER_BITMAP_FLAG))
    }
    private fun label(c: Canvas, text: String, x: Float, y: Float, size: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = size; typeface = Typeface.DEFAULT_BOLD; setShadowLayer(size * .15f, 0f, 1f, Color.BLACK) }
        c.drawText(text, x, y, p)
    }
    private fun brand(context: Context, c: Canvas, w: Int, h: Int, scale: Float = 1f) {
        val size = max(8f, min(w, h) * .035f) * scale
        val left = w * .025f; val bottom = h - size * .5f
        val logo = ContextCompat.getDrawable(context, R.mipmap.ic_launcher)!!
        logo.setBounds(left.toInt(), (bottom - size).toInt(), (left + size).toInt(), bottom.toInt()); logo.draw(c)
        label(c, "AquaRestore", left + size * 1.25f, bottom - size * .1f, size * .7f)
    }

    private suspend fun video(context: Context, request: ExportRequest): List<ShareMedia> {
        val source = request.source
        val duration = if (source.video) (request.options.trimmedMs(source.durationMs) / request.options.speed).toLong() else 6000L
        val (offset, length) = if (source.video) SharingPlan.clip(duration) else 0L to duration
        val (w, h) = SharingPlan.videoSize(source.width, source.height)
        val start = if (source.video) request.options.startMs + (offset * request.options.speed).toLong() else 0L
        val end = if (source.video) minOf(source.durationMs, start + (length * request.options.speed).toLong()) else 0L
        val file = destination(context, "mp4")
        val mark = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        brand(context, Canvas(mark), w, h, scale = 2f)
        try {
            val effects = MediaIO.resizeEffect(source, maxOf(w, h)) + listOf<androidx.media3.common.Effect>(
                FrameRateCap(30f), ComparisonEffect(request.grade, length * 1000),
                androidx.media3.effect.OverlayEffect(java.util.ArrayList<androidx.media3.effect.TextureOverlay>().apply {
                    add(androidx.media3.effect.BitmapOverlay.createStaticBitmapOverlay(mark)) })
            )
            withTimeout(60_000) {
                MediaIO.transform(context, source, file, effects,
                    maxOf(500_000, w * h * 4), if (source.keepsHdr) "video/hevc" else "video/avc", true,
                    speed = if (source.video) request.options.speed else 1f, startMs = start, endMs = end,
                    audio = AudioMix(originalVolume = 0f), imageDurationMs = if (source.video) 0 else 6000) { }
            }
            return listOf(ShareMedia(file, true))
        } catch (e: CancellationException) { file.delete(); throw e }
        catch (e: Exception) { file.delete(); android.util.Log.w("AquaRestore", "Comparison video unavailable", e); return emptyList() }
        finally { mark.recycle() }
    }

    suspend fun save(context: Context, media: ShareMedia): Uri = withContext(Dispatchers.IO) {
        media.saved?.let { return@withContext it }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "AquaRestore_Comparison_${media.file.name}")
            put(MediaStore.MediaColumns.MIME_TYPE, media.mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, if (media.video) "Movies/AquaRestore" else "Pictures/AquaRestore")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = if (media.video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val uri = context.contentResolver.insert(collection, values) ?: error("Cannot save comparison")
        try {
            context.contentResolver.openOutputStream(uri)?.use { output -> media.file.inputStream().use { it.copyTo(output) } } ?: error("Cannot write comparison")
            withContext(NonCancellable) {
                check(context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1)
                media.saved = uri
            }
            uri
        } catch (e: Exception) { if (media.saved == null) context.contentResolver.delete(uri, null, null); throw e }
    }
}

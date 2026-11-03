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
    suspend fun make(context: Context, request: ExportRequest, restored: Uri): List<ShareMedia> = withContext(Dispatchers.Default) {
        val result = mutableListOf<ShareMedia>()
        try {
            if (!request.source.video) {
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
                        val (w, h) = SharingPlan.videoSize(original.width, original.height)
                        val file = destination(context, "mp4")
                        try {
                            encode(file, w, h, 6_000) { _, fraction -> reveal(context, original, after, w, h, fraction) }
                            result.add(0, ShareMedia(file, true))
                        } catch (e: Exception) { file.delete(); throw e }
                    } finally { after.recycle() }
                } finally { original.recycle() }
            } else {
                MediaMetadataRetriever().use { before -> MediaMetadataRetriever().use { after ->
                    before.setDataSource(context, request.source.uri); after.setDataSource(context, restored)
                    val duration = after.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: error("Missing duration")
                    val (start, length) = SharingPlan.clip(duration)
                    val output = MediaIO.inspect(context, restored)
                    val (w, h) = SharingPlan.videoSize(min(request.source.width, output.width), min(request.source.height, output.height))
                    val file = destination(context, "mp4")
                    try {
                        encode(file, w, h, length) { ms, fraction ->
                            val t = start + ms
                            val b = before.getScaledFrameAtTime((request.options.startMs + (t * request.options.speed).toLong()) * 1000,
                                MediaMetadataRetriever.OPTION_CLOSEST, w, h) ?: error("Missing original frame")
                            val a = after.getScaledFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST, w, h) ?: run { b.recycle(); error("Missing restored frame") }
                            try { reveal(context, b, a, w, h, fraction) } finally { b.recycle(); a.recycle() }
                        }
                        result += ShareMedia(file, true)
                    } catch (e: Exception) { file.delete(); throw e }
                } }
            }
        } catch (e: CancellationException) { result.forEach { it.file.delete() }; throw e }
        catch (e: Exception) { android.util.Log.w("AquaRestore", "Comparison preview unavailable", e) }
        catch (_: OutOfMemoryError) { android.util.Log.w("AquaRestore", "Comparison preview needs too much memory") }
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
    private fun reveal(context: Context, before: Bitmap, after: Bitmap, w: Int, h: Int, fraction: Float): Bitmap {
        val image = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888); val c = Canvas(image)
        c.drawColor(Color.BLACK); val bounds = RectF(0f, 0f, w.toFloat(), h.toFloat()); fit(c, before, bounds)
        val reveal = ((fraction - .25f) / .5f).coerceIn(0f, 1f)
        c.save(); c.clipRect(0f, 0f, w * reveal, h.toFloat()); fit(c, after, bounds); c.restore()
        if (reveal > 0 && reveal < 1) c.drawLine(w * reveal, 0f, w * reveal, h.toFloat(), Paint().apply { color = Color.WHITE; strokeWidth = max(1f, w / 400f) })
        val size = min(w, h) * .04f
        if (reveal < 1) label(c, "Original", w * .025f, h * .07f, size)
        if (reveal > .3f) label(c, "Restored", w * .025f, h * .14f, size)
        brand(context, c, w, h)
        return image
    }
    private fun label(c: Canvas, text: String, x: Float, y: Float, size: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = size; typeface = Typeface.DEFAULT_BOLD; setShadowLayer(size * .15f, 0f, 1f, Color.BLACK) }
        c.drawText(text, x, y, p)
    }
    private fun brand(context: Context, c: Canvas, w: Int, h: Int) {
        val size = max(8f, min(w, h) * .035f)
        val left = w * .025f; val bottom = h - size * .5f
        val logo = ContextCompat.getDrawable(context, R.mipmap.ic_launcher)!!
        logo.setBounds(left.toInt(), (bottom - size).toInt(), (left + size).toInt(), bottom.toInt()); logo.draw(c)
        label(c, "AquaRestore", left + size * 1.25f, bottom - size * .1f, size * .7f)
    }

    private suspend fun encode(file: File, w: Int, h: Int, duration: Long, frame: (Long, Float) -> Bitmap) {
        require(duration > 0)
        val codec = MediaCodec.createEncoderByType("video/avc")
        val muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var started = false; var track = -1
        try {
            codec.configure(MediaFormat.createVideoFormat("video/avc", w, h).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
                setInteger(MediaFormat.KEY_BIT_RATE, max(500_000, w * h * 4))
                setInteger(MediaFormat.KEY_FRAME_RATE, 24); setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val count = max(1, (duration * 24 / 1000).toInt()); var input = 0; var eos = false
            val info = MediaCodec.BufferInfo(); val pixels = IntArray(w * h)
            while (!eos) {
                currentCoroutineContext().ensureActive()
                if (input <= count) {
                    val index = codec.dequeueInputBuffer(10_000)
                    if (index >= 0) {
                        if (input == count) codec.queueInputBuffer(index, 0, 0, duration * 1000, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        else {
                            val bitmap = frame(input * 1000L / 24, input.toFloat() / max(1, count - 1))
                            try { bitmap.getPixels(pixels, 0, w, 0, 0, w, h) } finally { bitmap.recycle() }
                            val image = codec.getInputImage(index) ?: error("No encoder image")
                            val planes = image.planes
                            for (y in 0 until h) for (x in 0 until w) {
                                val rgb = pixels[y*w+x]; val r = (rgb shr 16) and 255; val g = (rgb shr 8) and 255; val b = rgb and 255
                                planes[0].buffer.put(y * planes[0].rowStride + x * planes[0].pixelStride, (((66*r+129*g+25*b+128) shr 8)+16).coerceIn(0,255).toByte())
                                if (x % 2 == 0 && y % 2 == 0) {
                                    planes[1].buffer.put(y/2 * planes[1].rowStride + x/2 * planes[1].pixelStride, (((-38*r-74*g+112*b+128) shr 8)+128).coerceIn(0,255).toByte())
                                    planes[2].buffer.put(y/2 * planes[2].rowStride + x/2 * planes[2].pixelStride, (((112*r-94*g-18*b+128) shr 8)+128).coerceIn(0,255).toByte())
                                }
                            }
                            codec.queueInputBuffer(index, 0, w*h*3/2, input * 1_000_000L / 24, 0)
                        }
                        input++
                    }
                }
                var out = codec.dequeueOutputBuffer(info, 10_000)
                if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) { track = muxer.addTrack(codec.outputFormat); muxer.start(); started = true }
                while (out >= 0) {
                    if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                        check(started); val bytes = codec.getOutputBuffer(out)!!; bytes.position(info.offset); bytes.limit(info.offset + info.size); muxer.writeSampleData(track, bytes, info)
                    }
                    eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    codec.releaseOutputBuffer(out, false); out = codec.dequeueOutputBuffer(info, 0)
                }
            }
        } finally {
            runCatching { codec.stop() }; codec.release()
            try { if (started) muxer.stop() } finally { muxer.release() }
        }
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

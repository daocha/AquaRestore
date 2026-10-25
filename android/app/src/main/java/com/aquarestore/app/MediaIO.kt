package com.aquarestore.app

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.Clock
import androidx.media3.datasource.DataSourceBitmapLoader
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.common.Effect
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.*
import kotlinx.coroutines.*
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.pow

class MediaProblem(val key: String) : Exception(key)

data class SourceMedia(
    val uri: Uri, val name: String, val video: Boolean,
    val width: Int, val height: Int, val durationMs: Long = 0,
    val fps: Float = 30f, val bitrate: Int = 0, val mime: String = "image/jpeg",
    val hdrTransfer: Int = 0, val colorRange: Int = C.COLOR_RANGE_LIMITED,
    val audioBitrate: Int = 0,
    /** An HDR source on a device without a 10-bit HDR encoder: graded and exported tone-mapped to SDR. */
    val toneMapped: Boolean = false,
    /** No hardware decoder could read this video's frames, so it is decoded in software. */
    val softwareDecoding: Boolean = false,
    /** The whole-number frame rate Android declares, which [fps] measures instead; for the log. */
    val declaredFps: Float? = null,
) {
    val isHdr: Boolean get() = hdrTransfer == C.COLOR_TRANSFER_ST2084 || hdrTransfer == C.COLOR_TRANSFER_HLG
    val keepsHdr: Boolean get() = isHdr && !toneMapped
    val hdrName: String get() = if (hdrTransfer == C.COLOR_TRANSFER_HLG) "HLG" else "HDR10 / PQ"
}

object MediaIO {
    fun inspect(context: Context, uri: Uri): SourceMedia {
        val resolver = context.contentResolver
        val mime = resolver.getType(uri) ?: ""
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: "Underwater"
        if (!mime.startsWith("video/")) {
            var width = 0; var height = 0
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
                width = info.size.width; height = info.size.height
                decoder.setTargetSize(1, 1)
            }.recycle()
            return SourceMedia(uri, name, false, width, height, mime = mime)
        }
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            val tracks = (0 until extractor.trackCount).map { extractor.getTrackFormat(it) }
            val audioRate = tracks.filter { it.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
                .sumOf { if (it.containsKey(MediaFormat.KEY_BIT_RATE)) it.getInteger(MediaFormat.KEY_BIT_RATE).coerceAtLeast(1) else 192_000 }
            val track = tracks.firstOrNull { it.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true }
                ?: throw MediaProblem("unsupported")
            val transfer = if (track.containsKey(MediaFormat.KEY_COLOR_TRANSFER)) track.getInteger(MediaFormat.KEY_COLOR_TRANSFER) else 0
            if (track.getString(MediaFormat.KEY_MIME) == "video/dolby-vision") throw MediaProblem("dolbyVision")
            if (track.containsKey(MediaFormat.KEY_PROFILE) && track.getInteger(MediaFormat.KEY_PROFILE) in listOf(
                    android.media.MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus,
                    android.media.MediaCodecInfo.CodecProfileLevel.VP9Profile2HDR10Plus)) throw MediaProblem("dynamicHdr")
            val range = if (track.containsKey(MediaFormat.KEY_COLOR_RANGE)) track.getInteger(MediaFormat.KEY_COLOR_RANGE) else C.COLOR_RANGE_LIMITED
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, uri)
                fun meta(key: Int) = retriever.extractMetadata(key)
                var w = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                var h = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                if (meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() in listOf(90, 270)) { val t = w; w = h; h = t }
                require(w > 0 && h > 0)
                val duration = meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
                val declaredRate = if (track.containsKey(MediaFormat.KEY_FRAME_RATE)) track.getNumber(MediaFormat.KEY_FRAME_RATE)?.toFloat() else null
                val measuredRate = measuredFrameRate(extractor, tracks.indexOf(track))
                android.util.Log.i("AquaRestore", "Frame rate: measured $measuredRate, declared $declaredRate")
                val frameRate = (measuredRate ?: declaredRate)?.takeIf { it.isFinite() && it > 0 } ?: 30f
                val trackRate = if (track.containsKey(MediaFormat.KEY_BIT_RATE)) track.getInteger(MediaFormat.KEY_BIT_RATE) else 0
                val totalRate = meta(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull() ?: 0L
                val rate = if (trackRate > 0) trackRate else (totalRate - audioRate).coerceIn(0, Int.MAX_VALUE.toLong()).toInt()
                return SourceMedia(uri, name, true, w, h, duration, frameRate, rate, track.getString(MediaFormat.KEY_MIME)!!, transfer, range, audioRate,
                    declaredFps = declaredRate)
            } finally { retriever.release() }
        } finally { extractor.release() }
    }

    fun bitmap(context: Context, uri: Uri, edge: Int): Bitmap =
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
            val (w, h) = ExportSizing.dimensions(info.size.width, info.size.height, edge)
            checkMemory(context, w.toLong() * h)
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = true
            decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
            decoder.setTargetSize(w, h)
        }

    /**
     * A bitmap's pixels (4 bytes each) live in native memory, bounded by the device's free RAM rather than the
     * Java heap. Only [gradeBitmap]'s clarity luma (1 byte each) is on the heap; allow it twice for headroom.
     */
    private fun checkMemory(context: Context, pixels: Long) {
        val runtime = Runtime.getRuntime()
        val heapFree = runtime.maxMemory() - (runtime.totalMemory() - runtime.freeMemory())
        val device = ActivityManager.MemoryInfo().also { context.getSystemService(ActivityManager::class.java).getMemoryInfo(it) }
        if (pixels * 2 > heapFree || pixels * 4 > (device.availMem - device.threshold) / 2) throw MediaProblem("memory")
    }

    suspend fun analyze(context: Context, source: SourceMedia): Analysis = withContext(Dispatchers.IO) {
        val frames = mutableListOf<IntArray>()
        if (source.video) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, source.uri)
                for (fraction in listOf(0.05, 0.23, 0.41, 0.59, 0.77, 0.95)) {
                    ensureActive()
                    val frame = retriever.getScaledFrameAtTime((source.durationMs * 1000 * fraction).toLong(),
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 192, 192) ?: continue
                    frames += pixels(frame)
                    frame.recycle()
                }
            } finally { retriever.release() }
        } else {
            val frame = bitmap(context, source.uri, 192)
            frames += pixels(frame)
            frame.recycle()
        }
        if (frames.isEmpty()) throw MediaProblem("analysisFailed")
        AutoGrade.analyze(frames, hdr = source.keepsHdr)
    }

    /**
     * The frame rate from the spacing of the first frames. Android's declared rate is a whole number, counted over
     * the edited duration: lead-in frames hidden by an edit list (a GoPro clip can have a second of them) push 59.94
     * up to 61, which a decoder declaring 7680x4320 at 60 fps does not cover.
     */
    private fun measuredFrameRate(extractor: MediaExtractor, track: Int): Float? = runCatching {
        extractor.selectTrack(track)
        val times = buildList {
            // Lead-in frames before an edit list's start have negative times, so the end is the track index, not -1.
            while (size < 121 && extractor.sampleTrackIndex >= 0) { add(extractor.sampleTime); extractor.advance() }
        }.sorted()
        val gaps = times.zipWithNext { a, b -> b - a }.filter { it > 0 }.sorted()
        if (gaps.size < 10) null else 1_000_000f / gaps[gaps.size / 2]
    }.onFailure { android.util.Log.w("AquaRestore", "Frame rate not measured", it) }.getOrNull()

    /** One frame from the middle of each of [count] equal slots, for the trim bar. */
    /** One frame near the middle of each of [count] equal slots, for the trim bar. */
    suspend fun filmstrip(context: Context, uri: Uri, durationMs: Long, count: Int, height: Int = 96): List<Bitmap> = withContext(Dispatchers.IO) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            (0 until count).mapNotNull { i ->
                ensureActive()
                // The nearest keyframe avoids decoding long GOPs of a full-resolution original.
                retriever.getScaledFrameAtTime(durationMs * 1000 * (2 * i + 1) / (2 * count),
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC, height * 16 / 9, height)
            }
        } finally { retriever.release() }
    }

    private fun pixels(bitmap: Bitmap) = IntArray(bitmap.width * bitmap.height).also {
        bitmap.getPixels(it, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
    }

    suspend fun gradeBitmap(bitmap: Bitmap, grade: Grade, progress: (Int) -> Unit = {}): Bitmap {
        val row = IntArray(bitmap.width)
        val effective = grade.effective()
        val exposureGain = 2f.pow(effective.exposure)
        // Clarity reads neighbours of the ungraded source, so take its luma before rows are overwritten.
        val luma = if (effective.clarity != 0f && effective.strength != 0f) ByteArray(bitmap.width * bitmap.height).also {
            for (y in 0 until bitmap.height) {
                bitmap.getPixels(row, 0, bitmap.width, 0, y, bitmap.width, 1)
                Clarity.luma(row, it, y * bitmap.width)
            }
        } else null
        val radius = Clarity.radius(bitmap.width, bitmap.height)
        for (y in 0 until bitmap.height) {
            currentCoroutineContext().ensureActive()
            bitmap.getPixels(row, 0, bitmap.width, 0, y, bitmap.width, 1)
            for (x in row.indices) row[x] = ColorGrade.pixel(row[x], effective, exposureGain,
                if (luma == null) 0f else Clarity.detail(luma, bitmap.width, bitmap.height, x, y, radius))
            bitmap.setPixels(row, 0, bitmap.width, 0, y, bitmap.width, 1)
            if (y % 32 == 0) progress((y + 1) * 100 / bitmap.height)
        }
        return bitmap
    }

    private fun hdrEncoderAvailable(source: SourceMedia, mime: String): Boolean {
        val color = ColorInfo.Builder().setColorSpace(C.COLOR_SPACE_BT2020)
            .setColorTransfer(source.hdrTransfer).setColorRange(source.colorRange).build()
        return EncoderUtil.getSupportedEncodersForHdrEditing(mime, color).isNotEmpty()
    }

    /** HDR stays HDR where the device can encode it (Android 13+ with a 10-bit HDR encoder); elsewhere it is tone-mapped to SDR. */
    fun withHdrSupport(source: SourceMedia): SourceMedia =
        if (source.isHdr && !hdrEncoderAvailable(source, MimeTypes.VIDEO_H265)) source.copy(toneMapped = true) else source

    fun requireHdrEncoder(source: SourceMedia, mime: String) {
        if (source.keepsHdr && !hdrEncoderAvailable(source, mime)) throw MediaProblem("hdrDevice")
    }

    /**
     * Whether a hardware decoder can play this video live. It must declare the frame size. Up to 4K at 60 fps of
     * pixels per second plays live: some decoders declare only 4K30 performance points yet sustain 4K60. Above that,
     * separately declared width, height and frame rate limits are often generous, so the decoder must declare a
     * performance point (a size and rate it sustains) that covers this video.
     */
    fun decodesLive(source: SourceMedia): Boolean = runCatching {
        val withinLimit = source.width.toLong() * source.height * source.fps <= 3840L * 2160 * 61
        val needed = android.media.MediaCodecInfo.VideoCapabilities.PerformancePoint(source.width, source.height,
            ceil(source.fps).toInt().coerceAtLeast(1))
        decoders(source, hardware = true).any { caps -> withinLimit || caps.supportedPerformancePoints?.any { it.covers(needed) } == true }
    }.getOrDefault(true)

    /** What [decodesLive] saw, decoder by decoder, for the log. */
    fun liveDecodeReport(source: SourceMedia): String = runCatching {
        val (w, h) = source.width to source.height
        val needed = android.media.MediaCodecInfo.VideoCapabilities.PerformancePoint(w, h, ceil(source.fps).toInt().coerceAtLeast(1))
        val lines = mutableListOf(
            "${w}x$h ${source.mime}",
            "Frame rate: %.3f used, %s declared".format(source.fps, source.declaredFps?.let { "%.2f".format(it) } ?: "none"),
            "Pixel rate: %.0f M/s (plays live up to %.0f M/s)".format(w.toDouble() * h * source.fps / 1e6, 3840.0 * 2160 * 61 / 1e6),
            "Needs: $needed",
        )
        val hardware = android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
            !info.isEncoder && info.isHardwareAccelerated && info.supportedTypes.any { it.equals(source.mime, true) }
        }
        if (hardware.isEmpty()) lines += "No hardware decoder for this format"
        for (info in hardware) {
            val caps = info.getCapabilitiesForType(source.mime).videoCapabilities ?: continue
            val (cw, ch) = if (caps.isSizeSupported(w, h)) w to h else h to w
            val points = caps.supportedPerformancePoints
            lines += "\n${info.name}"
            lines += "Size: ${if (caps.isSizeSupported(cw, ch)) "yes" else "no"} (max ${caps.supportedWidths.upper}x${caps.supportedHeights.upper})" +
                ", rate on paper: ${if (runCatching { caps.areSizeAndRateSupported(cw, ch, source.fps.toDouble()) }.getOrDefault(false)) "yes" else "no"}" +
                ", covered: ${when { points == null -> "no points declared"; points.any { it.covers(needed) } -> "yes"; else -> "no" }}"
            points?.forEach { lines += "  $it" }
        }
        lines.joinToString("\n")
    }.getOrElse { "Check failed: $it" }

    /** Whether a software decoder declares this video's frame size, for videos no hardware decoder can read. */
    fun softwareDecodes(source: SourceMedia): Boolean = runCatching { decoders(source, hardware = false).isNotEmpty() }.getOrDefault(false)

    private fun decoders(source: SourceMedia, hardware: Boolean) =
        android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
            !info.isEncoder && (if (hardware) info.isHardwareAccelerated else info.isSoftwareOnly) &&
                info.supportedTypes.any { it.equals(source.mime, true) }
        }.mapNotNull { it.getCapabilitiesForType(source.mime).videoCapabilities }
            .filter { it.isSizeSupported(source.width, source.height) || it.isSizeSupported(source.height, source.width) }

    fun resizeEffect(source: SourceMedia, edge: Int): List<Effect> {
        if (edge == 0 || max(source.width, source.height) <= edge) return emptyList()
        val (w, h) = ExportSizing.dimensions(source.width, source.height, edge, true)
        return listOf(Presentation.createForWidthAndHeight(w, h, Presentation.LAYOUT_SCALE_TO_FIT))
    }

    /** Reads video with software decoders only; audio keeps the usual decoders. */
    private fun softwareVideoDecoding(context: Context) = DefaultAssetLoaderFactory(context,
        DefaultDecoderFactory.Builder(context).setMediaCodecSelector { mime, secure, tunneling ->
            MediaCodecUtil.getDecoderInfos(mime, secure, tunneling).filter { !MimeTypes.isVideo(mime) || it.softwareOnly }
        }.build(),
        Clock.DEFAULT, DefaultMediaSourceFactory(context), DataSourceBitmapLoader(context))

    private fun gain(volume: Float): List<androidx.media3.common.audio.AudioProcessor> =
        if (volume == 1f) emptyList() else listOf(VolumeProcessor(volume))

    /** Runs on Main; callbacks and cancellation remain on Transformer's application looper. */
    suspend fun transform(
        context: Context, source: SourceMedia, output: File, effects: List<Effect>,
        bitrate: Int, mime: String, strict: Boolean, speed: Float = 1f, startMs: Long = 0, endMs: Long = 0,
        audio: AudioMix = AudioMix(), progress: (Int?) -> Unit,
    ): ExportResult = withContext(Dispatchers.Main.immediate) {
        requireHdrEncoder(source, mime)
        val hdrMode = if (source.toneMapped) Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL else Composition.HDR_MODE_KEEP_HDR
        coroutineScope {
            var transformer: Transformer? = null
            val poll = launch {
                val holder = ProgressHolder()
                while (isActive) {
                    transformer?.let {
                        val state = it.getProgress(holder)
                        progress(if (state == Transformer.PROGRESS_STATE_AVAILABLE) holder.progress else null)
                    }
                    delay(250)
                }
            }
            try {
                suspendCancellableCoroutine { continuation ->
                    val encoder = DefaultEncoderFactory.Builder(context)
                        .setEnableFallback(!strict)
                        .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(bitrate).build())
                        .build()
                    val active = Transformer.Builder(context).setEncoderFactory(encoder)
                        .apply { if (source.softwareDecoding) setAssetLoaderFactory(softwareVideoDecoding(context)) }
                        .setVideoMimeType(mime)
                        .addListener(object : Transformer.Listener {
                            override fun onFallbackApplied(composition: Composition, originalTransformationRequest: TransformationRequest, fallbackTransformationRequest: TransformationRequest) {
                                // Media3 may tone-map automatically even when encoder fallback is off.
                                // Reject the fallback before any SDR result can be published as HDR.
                                if ((source.isHdr && fallbackTransformationRequest.hdrMode != hdrMode) ||
                                    (strict && (fallbackTransformationRequest.videoMimeType != originalTransformationRequest.videoMimeType ||
                                        fallbackTransformationRequest.outputHeight != originalTransformationRequest.outputHeight))) {
                                    transformer?.cancel()
                                    if (continuation.isActive) continuation.resumeWithException(MediaProblem(if (source.keepsHdr) "hdrDevice" else "exportFailed"))
                                }
                            }
                            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                                if (continuation.isActive) continuation.resume(exportResult)
                            }
                            override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                                if (continuation.isActive) continuation.resumeWithException(exportException)
                            }
                        }).build()
                    transformer = active
                    continuation.invokeOnCancellation { active.cancel() }
                    try {
                        val clipping = MediaItem.ClippingConfiguration.Builder().setStartPositionMs(startMs)
                            .apply { if (endMs > 0) setEndPositionMs(endMs) }.build()
                        // Media3 stalls retiming a video-only item, so with a speed change muted sound stays in as silence.
                        val dropOriginal = audio.originalVolume == 0f && speed == 1f
                        val item = EditedMediaItem.Builder(MediaItem.Builder().setUri(source.uri).setClippingConfiguration(clipping).build())
                            .setEffects(Effects(gain(audio.originalVolume), effects))
                            .setRemoveAudio(dropOriginal)
                            .setSpeed(if (speed == 1f) androidx.media3.common.audio.SpeedProvider.DEFAULT else object : androidx.media3.common.audio.SpeedProvider {
                                override fun getSpeed(timeUs: Long): Float = speed
                                override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = androidx.media3.common.C.TIME_UNSET
                            }).build()
                        val music = audio.music
                        val sequences = if (music == null || !audio.hasMusic) listOf(EditedMediaItemSequence.Builder(item).build()) else {
                            val outputMs = (ExportOptions(startMs = startMs, endMs = endMs).trimmedMs(source.durationMs) / speed).toLong()
                            val window = musicWindow(music.durationMs, audio.musicStartMs, outputMs)
                            fun song(from: Long, to: Long) = EditedMediaItem.Builder(MediaItem.Builder().setUri(music.uri).setClippingConfiguration(
                                MediaItem.ClippingConfiguration.Builder().setStartPositionMs(from).setEndPositionMs(to).build()).build())
                                .setEffects(Effects(gain(audio.musicVolume), emptyList())).build()
                            // A song shorter than the video repeats back to back, the last copy cut to fit.
                            val songs = musicPieces(window, outputMs).map { song(it.first, it.last) }
                            listOf(
                                // Video-only when the camera's sound is muted, so the music is the only audio track.
                                if (dropOriginal) EditedMediaItemSequence.withVideoFrom(listOf(item)) else EditedMediaItemSequence.Builder(item).build(),
                                EditedMediaItemSequence.withAudioFrom(songs),
                            )
                        }
                        val composition = Composition.Builder(sequences)
                            .setHdrMode(hdrMode).build()
                        active.start(composition, output.absolutePath)
                    } catch (e: Exception) {
                        active.cancel()
                        if (continuation.isActive) continuation.resumeWithException(e)
                    }
                }
            } finally { poll.cancel() }
        }
    }
}

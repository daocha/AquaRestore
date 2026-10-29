package com.aquarestore.app

import kotlin.math.*

/** Original keeps full quality: JPEG at the encoder's maximum, PNG lossless. */
const val ORIGINAL_JPEG_QUALITY = 100

fun exportFileName(sourceName: String, extension: String): String {
    val name = sourceName.substringAfterLast('/').substringAfterLast('\\').trim()
    val stem = name.substringBeforeLast('.', name).ifBlank { "Underwater" }
    return "AquaRestore_${stem}.$extension"
}

data class ExportOptions(
    val original: Boolean = true,
    val longEdge: Int = 1920, // 0 = source dimensions
    val fps: Int = 0, // 0 = original timestamps; other values cap, never invent frames
    val quality: Int = 90,
    val png: Boolean = false,
    val speed: Float = 1f,
    val startMs: Long = 0, // video trim in source time
    val endMs: Long = 0, // 0 = to the end
) {
    fun trimmedMs(durationMs: Long): Long =
        ((if (endMs > 0) min(endMs, durationMs) else durationMs) - startMs).coerceAtLeast(0)
}

enum class ExportMode { RECOMMENDED, ORIGINAL, CUSTOM }

data class ExportSelection(
    val mode: ExportMode = ExportMode.RECOMMENDED,
    val longEdge: Int = 1920,
    val fps: Int = 0,
    val quality: Int = 90,
    val png: Boolean = false,
)

object ExportRecommendation {
    /** Small photos keep full dimensions; large photos are reduced. PNG sources stay PNG, others become JPEG. */
    fun photo(width: Int, height: Int, mime: String = "image/jpeg"): ExportOptions =
        if (max(width, height) <= 2560) ExportOptions(quality = 95, png = mime == "image/png")
        else ExportOptions(original = false, longEdge = 2560, quality = 90, png = mime == "image/png")

    /** Bound both axes to a 1080p frame, preserve lower source rates, and never enlarge the source. */
    fun video(width: Int, height: Int, fps: Float): ExportOptions {
        val long = max(width, height)
        val short = min(width, height)
        val scale = min(1.0, min(1920.0 / long, 1080.0 / short))
        val edge = if (scale == 1.0) 0 else (long * scale).toInt().coerceAtLeast(2)
        val frameCap = if (fps > 30f) 30 else 0
        return if (edge == 0 && frameCap == 0) ExportOptions()
        else ExportOptions(original = false, longEdge = edge, fps = frameCap, quality = 85)
    }
}

object ExportSizing {
    fun dimensions(width: Int, height: Int, longEdge: Int, even: Boolean = false): Pair<Int, Int> {
        require(width > 0 && height > 0)
        val scale = if (longEdge <= 0) 1.0 else min(1.0, longEdge.toDouble() / max(width, height))
        fun size(v: Int): Int {
            val n = max(1, (v * scale).roundToInt())
            return if (even) max(2, n / 2 * 2) else n
        }
        return size(width) to size(height)
    }

    /** [sourcePixelRate] is the source's width × height × fps, used to scale [source] to the output. */
    fun bitrate(width: Int, height: Int, fps: Float, quality: Int, source: Int, original: Boolean, sourcePixelRate: Double = 0.0): Int {
        // Prefer the measured source rate; only estimate when metadata is unavailable.
        if (original && source > 0) return source
        val q = quality.coerceIn(1, 100) / 100.0
        if (source > 0 && sourcePixelRate > 0) {
            // 100% at source size and frame rate equals Original. Smaller outputs need more bits per pixel,
            // so the rate falls slower than the pixel count; it never exceeds the source. The floor guards
            // heavy downscales but stays below the quality share, so the slider always has an effect.
            val ratio = (width.toDouble() * height * fps.coerceIn(1f, 240f) / sourcePixelRate).coerceIn(0.0, 1.0)
            return (source * ratio.pow(0.75) * q).coerceIn(min(500_000.0, source * q), source.toDouble()).roundToInt()
        }
        return (width.toDouble() * height * fps.coerceIn(1f, 240f) * (0.05 + q * 0.2))
            .coerceIn(500_000.0, Int.MAX_VALUE.toDouble()).roundToInt()
    }
}

/** Shared by the export pipeline and its size preview. Decimal MB/GB match the UI. */
data class VideoExportPlan(val bitrate: Int, val estimatedBytes: Long?)

/** The JPEG qualities a photo's samples are measured at. Size changes fastest near 100, so they are densest there. */
val SIZE_CURVE_QUALITIES = intArrayOf(10, 20, 30, 40, 50, 60, 70, 75, 80, 85, 88, 90, 92, 94, 95, 96, 97, 98, 99, 100)

/** Bytes per pixel at [quality] from [measured] values at [SIZE_CURVE_QUALITIES], interpolated in log space. */
fun interpolateBytesPerPixel(measured: DoubleArray, quality: Int): Double {
    val q = quality.coerceIn(SIZE_CURVE_QUALITIES.first(), SIZE_CURVE_QUALITIES.last())
    val upper = SIZE_CURVE_QUALITIES.indexOfFirst { it >= q }
    if (SIZE_CURVE_QUALITIES[upper] == q) return measured[upper]
    val (q0, q1) = SIZE_CURVE_QUALITIES[upper - 1] to SIZE_CURVE_QUALITIES[upper]
    val (b0, b1) = measured[upper - 1].coerceAtLeast(1e-6) to measured[upper].coerceAtLeast(1e-6)
    return exp(ln(b0) + (ln(b1) - ln(b0)) * (q - q0) / (q1 - q0))
}

/** A rough encoded size from output pixels, format and JPEG quality. Image detail changes compression substantially. */
fun photoEstimatedBytes(width: Int, height: Int, options: ExportOptions): Long {
    val (w, h) = ExportSizing.dimensions(width, height, if (options.original) 0 else options.longEdge)
    val bytesPerPixel = if (options.png) 2.5 else {
        // The encoder scales its quantization tables by this percentage, and size follows the scale, not the
        // quality number: it rises steeply only near 100. Fitted to measured exports of graded photos.
        val quality = options.quality.coerceIn(1, 100)
        val scale = if (quality < 50) 5000.0 / quality else 200.0 - 2 * quality
        1.82 * (scale + 5).pow(-0.68)
    }
    return (w.toDouble() * h * bytesPerPixel).roundToLong().coerceAtLeast(1)
}

/**
 * Learns how far exports land from their estimates on this device. Each export's actual size against its uncorrected
 * estimate is kept as a log ratio. A correction applies only when the ratios agree, so a steady margin is learned,
 * while one-off misses, which go either way, are not. Photos only: a video's margin depends on the clip as much as on
 * the device, so a margin learned from earlier clips does not carry over.
 */
object SizeCalibration {
    private const val HISTORY = 8

    fun record(history: List<Double>, estimatedBytes: Long, actualBytes: Long): List<Double> =
        (history + ln((actualBytes.toDouble() / estimatedBytes).coerceIn(0.5, 2.0))).takeLast(HISTORY)

    /** The factor for later estimates: 1 until at least two exports agree on a margin larger than their spread. */
    fun correction(history: List<Double>): Double {
        if (history.size < 2) return 1.0
        val mean = history.average()
        val spread = sqrt(history.sumOf { (it - mean) * (it - mean) } / (history.size - 1))
        return if (spread < abs(mean)) exp(mean) else 1.0
    }
}

fun videoExportPlan(width: Int, height: Int, fps: Float, sourceBitrate: Int,
    audioBitrate: Int, durationMs: Long, options: ExportOptions, mixedAudio: Boolean = false): VideoExportPlan {
    val (w, h) = ExportSizing.dimensions(width, height, if (options.original) 0 else options.longEdge)
    // Faster playback drops frames to stay at the source rate; slower playback spreads them out.
    val effectiveFps = fps * min(options.speed, 1f)
    val outputFps = if (options.original || options.fps == 0) effectiveFps else min(effectiveFps, options.fps.toFloat())
    val sourceRate = (sourceBitrate.toDouble() * min(options.speed, 1f)).coerceIn(0.0, Int.MAX_VALUE.toDouble()).toInt()
    val rate = ExportSizing.bitrate(w, h, outputFps, if (options.original) 100 else options.quality, sourceRate, options.original,
        width.toDouble() * height * effectiveFps.coerceIn(1f, 240f))
    // Audio is transcoded on speed changes and when mixing or changing volume. Use a conservative estimate then.
    val audioRate = if (mixedAudio) max(audioBitrate, 192_000)
        else if (audioBitrate > 0 && options.speed != 1f) max(audioBitrate, 192_000) else audioBitrate
    val length = options.trimmedMs(durationMs)
    val bytes = if (length > 0) ((rate.toDouble() + audioRate) * length / options.speed / 8000 * 1.01).toLong() else null
    return VideoExportPlan(rate, bytes)
}

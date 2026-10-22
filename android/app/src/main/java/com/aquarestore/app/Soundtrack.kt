package com.aquarestore.app

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

data class MusicTrack(val uri: Uri, val name: String, val durationMs: Long)

/** How the exported soundtrack is built: the video's own audio and an optional background track. */
data class AudioMix(
    val originalVolume: Float = 1f,
    val music: MusicTrack? = null,
    val musicStartMs: Long = 0,
    val musicVolume: Float = 1f,
) {
    val hasMusic: Boolean get() = music != null && musicVolume > 0f
    /** Anything other than the untouched original audio requires re-encoding it. */
    val changesAudio: Boolean get() = originalVolume != 1f || hasMusic
}

/**
 * The part of a song that plays under [outputMs] of video, starting near [startMs]. The start is
 * kept within the song so the window never runs past its end; a song shorter than the video
 * plays from the beginning and loops.
 */
fun musicWindow(songMs: Long, startMs: Long, outputMs: Long): LongRange {
    if (songMs <= outputMs) return 0L..songMs
    val start = startMs.coerceIn(0, songMs - outputMs)
    return start..start + outputMs
}

/** Song sections that fill [outputMs]: the window once, or repeated with the last copy cut short. */
fun musicPieces(window: LongRange, outputMs: Long): List<LongRange> {
    val length = window.last - window.first
    if (length <= 0 || outputMs <= 0) return emptyList()
    return (0 until (outputMs + length - 1) / length).map { i ->
        window.first..window.first + min(length, outputMs - i * length)
    }
}

/** Where the song should be for [elapsedMs] of output, or null when it is silent. */
fun musicPosition(songMs: Long, window: LongRange, elapsedMs: Long): Long? = when {
    elapsedMs < 0 || songMs <= 0 -> null
    songMs <= window.last - window.first -> elapsedMs % songMs
    window.first + elapsedMs < window.last -> window.first + elapsedMs
    else -> null
}

/**
 * Volume from 0 to 200%, clipping loud samples instead of wrapping them: Media3's GainProcessor
 * casts 16-bit results without clamping, which crackles above 100%. [gain] may change live.
 */
class VolumeProcessor(@Volatile var gain: Float = 1f) : BaseAudioProcessor() {
    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT && inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT)
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining == 0) return
        val output = replaceOutputBuffer(remaining)
        val g = gain
        if (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT) {
            while (inputBuffer.hasRemaining()) output.putShort((inputBuffer.short * g).roundToInt().coerceIn(-32768, 32767).toShort())
        } else {
            while (inputBuffer.hasRemaining()) output.putFloat((inputBuffer.float * g).coerceIn(-1f, 1f))
        }
        output.flip()
    }
}

object Soundtrack {
    fun inspect(context: Context, uri: Uri): MusicTrack {
        val name = context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: "Music"
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri, null)
            val format = (0 until extractor.trackCount).map { extractor.getTrackFormat(it) }
                .firstOrNull { it.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true } ?: throw MediaProblem("noAudio")
            val duration = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) / 1000 else 0
            if (duration <= 0) throw MediaProblem("noAudio")
            return MusicTrack(uri, name, duration)
        } finally { extractor.release() }
    }

    /** Loudness per slot (0–1, normalized to the loudest), decoded from the real audio for the music bar. */
    suspend fun envelope(context: Context, track: MusicTrack, slots: Int = 120): FloatArray = withContext(Dispatchers.IO) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(context, track.uri, null)
            val index = (0 until extractor.trackCount).first { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
            extractor.selectTrack(index)
            val format = extractor.getTrackFormat(index)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
            val durationUs = track.durationMs * 1000
            val sums = DoubleArray(slots)
            val counts = IntArray(slots)
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            while (true) {
                ensureActive()
                if (!inputDone) {
                    val input = decoder.dequeueInputBuffer(10_000)
                    if (input >= 0) {
                        val size = extractor.readSampleData(decoder.getInputBuffer(input)!!, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(input, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val output = decoder.dequeueOutputBuffer(info, 10_000)
                if (output < 0) continue
                val samples = decoder.getOutputBuffer(output)!!.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                val slot = (info.presentationTimeUs * slots / max(1, durationUs)).toInt().coerceIn(0, slots - 1)
                // Every 8th 16-bit sample is plenty for a visual envelope.
                var i = 0
                while (i < samples.limit()) { sums[slot] += abs(samples.get(i).toInt()).toDouble(); counts[slot]++; i += 8 }
                decoder.releaseOutputBuffer(output, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            }
            val levels = FloatArray(slots) { if (counts[it] == 0) 0f else (sums[it] / counts[it]).toFloat() }
            val loudest = levels.maxOrNull()?.takeIf { it > 0f } ?: 1f
            FloatArray(slots) { min(1f, levels[it] / loudest) }
        } finally {
            runCatching { codec?.stop() }
            codec?.release()
            extractor.release()
        }
    }
}

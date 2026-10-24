package com.aquarestore.app

import android.app.Application
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MimeTypes
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import java.io.File

/** Long edge of the sharper photo shown in full screen: about full size for a 12 MP phone photo, within memory. */
private const val DETAIL_EDGE = 3840

class EditorModel(application: Application) : AndroidViewModel(application) {
    private val context get() = getApplication<Application>().applicationContext
    private val prefs = context.getSharedPreferences("preferences", 0)
    val language = MutableStateFlow(prefs.getString("language", "system")!!)
    val theme = MutableStateFlow(prefs.getString("theme", "system")!!)
    val photoExportSelection = MutableStateFlow(readExportSelection(false))
    val videoExportSelection = MutableStateFlow(readExportSelection(true))
    val source = MutableStateFlow<SourceMedia?>(null)
    val analysis = MutableStateFlow<Analysis?>(null)
    val grade = MutableStateFlow(Grade.Neutral)
    val gradeState = GradeState(Grade.Neutral)
    val previewUri = MutableStateFlow<Uri?>(null)
    val previewOriginal = MutableStateFlow<Bitmap?>(null)
    val previewGraded = MutableStateFlow<Bitmap?>(null)
    /**
     * A sharper copy of the photo for full screen, where the 720 px preview turns soft when zoomed: the original
     * at up to [DETAIL_EDGE] and its graded version, with the grade it shows. Built in the background once the
     * settings stop changing; until then full screen shows the fast preview.
     */
    val detailOriginal = MutableStateFlow<Bitmap?>(null)
    val detailGraded = MutableStateFlow<Pair<Grade, Bitmap>?>(null)
    val phase = MutableStateFlow<String?>(null)
    val progress = MutableStateFlow<Int?>(null)
    val error = MutableStateFlow<String?>(null)
    val compare = MutableStateFlow(false)
    val speed = MutableStateFlow(1f)
    /** Video trim in source milliseconds. [trimming] is true while a handle is being dragged. */
    val trim = MutableStateFlow(0L..0L)
    val trimming = MutableStateFlow(false)
    /** Ungraded thumbnails spread over the clip for the trim bar, and the preview's play position. */
    val filmstrip = MutableStateFlow<List<Bitmap>>(emptyList())
    val playhead = MutableStateFlow(0L)
    /** Positions picked on the trim bar. The Boolean marks a tap or the end of a drag. */
    val scrub = MutableSharedFlow<Pair<Long, Boolean>>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    /** Soundtrack: original-audio and music volumes, the music file, and where in the song the video starts. */
    val originalVolume = MutableStateFlow(1f)
    val music = MutableStateFlow<MusicTrack?>(null)
    val musicStartMs = MutableStateFlow(0L)
    val musicVolume = MutableStateFlow(1f)
    val musicEnvelope = MutableStateFlow<FloatArray?>(null)
    val musicLoading = MutableStateFlow(false)
    /** Emitted after the song window moves: replay the video from the trim start to hear it. */
    val audition = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private var musicJob: Job? = null
    private var importJob: Job? = null
    private var gradeJob: Job? = null
    private var detailJob: Job? = null
    private var proxy: File? = null
    var playbackPositionMs = 0L
    var playbackWanted = true

    fun preference(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
        if (key == "language") language.value = value else theme.value = value
    }

    private fun readExportSelection(video: Boolean): ExportSelection {
        val prefix = if (video) "export_video_" else "export_photo_"
        val mode = runCatching { ExportMode.valueOf(prefs.getString(prefix + "mode", "RECOMMENDED")!!) }
            .getOrDefault(ExportMode.RECOMMENDED)
        return ExportSelection(mode, prefs.getInt(prefix + "edge", 1920), prefs.getInt(prefix + "fps", 0),
            prefs.getInt(prefix + "quality", 90).coerceIn(10, 100), prefs.getBoolean(prefix + "png", false))
    }

    fun setExportSelection(video: Boolean, selection: ExportSelection) {
        (if (video) videoExportSelection else photoExportSelection).value = selection
        val prefix = if (video) "export_video_" else "export_photo_"
        prefs.edit().putString(prefix + "mode", selection.mode.name).putInt(prefix + "edge", selection.longEdge)
            .putInt(prefix + "fps", selection.fps).putInt(prefix + "quality", selection.quality)
            .putBoolean(prefix + "png", selection.png).apply()
    }

    /** Forgets the saved Custom settings, so the dialog shows the defaults again. */
    fun resetCustomExport(video: Boolean) {
        val prefix = if (video) "export_video_" else "export_photo_"
        prefs.edit().remove(prefix + "edge").remove(prefix + "fps").remove(prefix + "quality").remove(prefix + "png").apply()
        (if (video) videoExportSelection else photoExportSelection).value = readExportSelection(video)
    }

    fun import(uri: Uri) {
        if (Exports.status.value.busy) return
        speed.value = 1f
        trim.value = 0L..0L
        filmstrip.value = emptyList()
        removeMusic()
        originalVolume.value = 1f
        playbackPositionMs = 0L
        playbackWanted = true
        val previousImport = importJob
        previousImport?.cancel()
        gradeJob?.cancel()
        error.value = null
        previewUri.value = null
        previewOriginal.value = null
        previewGraded.value = null
        setDetailWanted(false)
        source.value = null
        analysis.value = null
        setCompare(false)
        importJob = viewModelScope.launch {
            previousImport?.join()
            try {
                phase.value = "analyzing"
                progress.value = null
                // Retain only the current source grant. No library-wide storage permission.
                withContext(Dispatchers.IO) {
                    runCatching { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                    context.contentResolver.persistedUriPermissions.filter { it.uri != uri }.forEach {
                        runCatching { context.contentResolver.releasePersistableUriPermission(it.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                    }
                }
                val media = withContext(Dispatchers.IO) { MediaIO.inspect(context, uri) }
                if (media.isHdr) MediaIO.requireHdrEncoder(media, MimeTypes.VIDEO_H265)
                val recommended = MediaIO.analyze(context, media)
                trim.value = 0L..media.durationMs
                source.value = media
                analysis.value = recommended
                setGrade(recommended.grade)
                if (media.video) {
                    // Play the original straight away; the grade is a live GPU effect, so no re-encode is needed.
                    proxy?.delete()
                    proxy = null
                    previewUri.value = media.uri
                    // Thumbnails and any proxy are built in the background and never hold up the editor.
                    launch {
                        try { filmstrip.value = MediaIO.filmstrip(context, media.uri, media.durationMs, 10) }
                        catch (e: CancellationException) { throw e }
                        catch (e: Exception) { android.util.Log.w("AquaRestore", "Filmstrip unavailable", e) }
                    }
                    if (needsProxy(media)) launch { buildProxy(media) }
                } else {
                    previewOriginal.value = withContext(Dispatchers.IO) { MediaIO.bitmap(context, uri, 720) }
                    setGrade(recommended.grade)
                }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) {
                android.util.Log.e("AquaRestore", "Import failed", e)
                source.value = null
                analysis.value = null
                error.value = (e as? MediaProblem)?.key ?: "importFailed"
            }
            finally { phase.value = null; progress.value = null }
        }
    }

    /** Above 4K at 30 fps, live decoding plus grading can stutter on mid-range phones. */
    private fun needsProxy(media: SourceMedia) = media.width.toLong() * media.height * media.fps > 3840L * 2160 * 31

    /**
     * Re-encodes a lighter 1280px copy for smooth preview of heavy footage, then swaps the player to it
     * at the same position. The copy keeps the original timeline, so trim and music stay aligned.
     */
    private suspend fun buildProxy(media: SourceMedia) {
        val file = File(context.cacheDir, "preview-${System.nanoTime()}.mp4")
        try {
            // Generous bitrate: auto levels can stretch hazy footage 3–4×, which exposes proxy blocking.
            val effects = MediaIO.resizeEffect(media, 1280) + FrameRateCap(30f)
            MediaIO.transform(context, media, file, effects, 8_000_000,
                if (media.isHdr) MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264, media.isHdr) { }
            if (source.value?.uri != media.uri) { file.delete(); return }
            playbackPositionMs = playhead.value
            proxy = file
            previewUri.value = Uri.fromFile(file)
        } catch (e: CancellationException) { file.delete(); throw e }
        catch (e: Exception) {
            // The original keeps playing; a proxy is only an optimization.
            file.delete()
            android.util.Log.w("AquaRestore", "Preview proxy unavailable", e)
        }
    }

    fun addMusic(uri: Uri) {
        musicJob?.cancel()
        musicJob = viewModelScope.launch {
            musicLoading.value = true
            try {
                val track = withContext(Dispatchers.IO) {
                    runCatching { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                    Soundtrack.inspect(context, uri)
                }
                musicEnvelope.value = null
                musicStartMs.value = 0L
                music.value = track
                musicLoading.value = false
                musicEnvelope.value = try { Soundtrack.envelope(context, track) }
                    catch (e: CancellationException) { throw e }
                    catch (e: Exception) { android.util.Log.w("AquaRestore", "Waveform unavailable", e); null }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) {
                android.util.Log.e("AquaRestore", "Music import failed", e)
                error.value = (e as? MediaProblem)?.key ?: "noAudio"
            } finally { musicLoading.value = false }
        }
    }

    fun removeMusic() {
        musicJob?.cancel()
        music.value = null
        musicEnvelope.value = null
        musicStartMs.value = 0L
        musicVolume.value = 1f
    }

    fun audioMix() = AudioMix(originalVolume.value, music.value, musicStartMs.value, musicVolume.value)

    fun cancelImport() { importJob?.cancel(); source.value = null; analysis.value = null }

    /** Leave the editor for the home screen, discarding the edit. A running export keeps its own copy. */
    fun closeMedia() {
        importJob?.cancel()
        gradeJob?.cancel()
        removeMusic()
        setCompare(false)
        source.value = null
        analysis.value = null
        previewUri.value = null
        previewOriginal.value = null
        previewGraded.value = null
        setDetailWanted(false)
        filmstrip.value = emptyList()
        trim.value = 0L..0L
        speed.value = 1f
        originalVolume.value = 1f
        playbackPositionMs = 0L
        playbackWanted = true
        proxy?.delete()
        proxy = null
    }

    fun setGrade(value: Grade) {
        setCompare(false)
        grade.value = value
        gradeState.grade = value
        val original = previewOriginal.value ?: return
        if (gradeJob?.isActive == true) return
        gradeJob = viewModelScope.launch {
            var rendered: Grade? = null
            // Finish each small preview, then consume the newest settings. Continuous dragging
            // must not indefinitely cancel/debounce every render before it can reach the screen.
            while (previewOriginal.value === original) {
                val snapshot = grade.value
                if (snapshot == rendered) break
                val bitmap = withContext(Dispatchers.Default) {
                    val copy = original.copy(Bitmap.Config.ARGB_8888, true)
                    try { MediaIO.gradeBitmap(copy, snapshot) }
                    catch (e: Exception) { copy.recycle(); throw e }
                }
                previewGraded.value = bitmap
                rendered = snapshot
                delay(16)
            }
        }
    }

    /** Full screen asks for the sharper photo; leaving it frees the memory again. */
    fun setDetailWanted(wanted: Boolean) {
        detailJob?.cancel()
        detailJob = null
        if (!wanted) {
            detailOriginal.value = null
            detailGraded.value = null
            return
        }
        val media = source.value?.takeIf { !it.video } ?: return
        detailJob = viewModelScope.launch {
            try {
                val original = detailOriginal.value ?: withContext(Dispatchers.IO) {
                    MediaIO.bitmap(context, media.uri, DETAIL_EDGE)
                }.also { detailOriginal.value = it }
                grade.collectLatest { snapshot ->
                    if (detailGraded.value?.first == snapshot) return@collectLatest
                    // Wait for the sliders to settle: a full-size grade takes far longer than the preview's.
                    delay(300)
                    val bitmap = withContext(Dispatchers.Default) {
                        val copy = original.copy(Bitmap.Config.ARGB_8888, true)
                        try { MediaIO.gradeBitmap(copy, snapshot) }
                        catch (e: Exception) { copy.recycle(); throw e }
                    }
                    detailGraded.value = snapshot to bitmap
                }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) {
                // Full screen keeps the preview; a sharper copy is only an improvement.
                android.util.Log.w("AquaRestore", "Full-screen detail unavailable", e)
            }
        }
    }

    fun setCompare(value: Boolean) { compare.value = value; gradeState.compare = value }
    fun reset() { analysis.value?.let { setGrade(it.grade) } }
    override fun onCleared() { super.onCleared(); proxy?.delete() }
}

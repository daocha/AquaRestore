package com.aquarestore.app

import kotlin.math.min
import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.net.Uri
import android.os.*
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media3.common.Effect
import androidx.media3.common.MimeTypes
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import java.io.File

// The request holds a frozen grade and the original URI, never the proxy URI.
data class ExportRequest(val source: SourceMedia, val grade: Grade, val options: ExportOptions, val chinese: Boolean,
    val audio: AudioMix = AudioMix())
data class ExportStatus(val busy: Boolean = false, val progress: Int? = null,
    val stage: String = "exporting", val uri: Uri? = null, val error: String? = null)

object Exports {
    val status = MutableStateFlow(ExportStatus())
    internal var request: ExportRequest? = null
    fun start(context: Context, request: ExportRequest) {
        if (status.value.busy) return
        this.request = request
        status.value = ExportStatus(busy = true)
        try { ContextCompat.startForegroundService(context, Intent(context, ExportService::class.java)) }
        catch (e: Exception) { this.request = null; status.value = ExportStatus(error = "exportFailed") }
    }
    fun cancel(context: Context) { context.startService(Intent(context, ExportService::class.java).setAction("cancel")) }
}

fun exportVideoMime(source: SourceMedia, options: ExportOptions): String =
    if (options.original) source.mime else if (source.keepsHdr) MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264

class ExportService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var lastNotification = 0L
    private var chinese = false
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "cancel") {
            job?.cancel()
            if (job == null) {
                Exports.request = null
                Exports.status.value = ExportStatus(stage = "cancelled")
                stopSelf(startId)
            }
            return START_NOT_STICKY
        }
        if (job != null) return START_NOT_STICKY
        val request = Exports.request ?: run { stopSelf(); return START_NOT_STICKY }
        chinese = request.chinese
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("exports", "AquaRestore", NotificationManager.IMPORTANCE_LOW))
        try {
            // Android 15 added mediaProcessing for transcoding; older versions only have dataSync.
            val type = if (Build.VERSION.SDK_INT >= 35) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
                else ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            startForeground(7, notification(null), type)
            wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AquaRestore:Export").apply { acquire(6 * 60 * 60 * 1000L) }
        } catch (e: Exception) {
            android.util.Log.e("AquaRestore", "Could not start export service", e)
            Exports.request = null
            Exports.status.value = ExportStatus(error = "exportFailed")
            stopSelf(startId)
            return START_NOT_STICKY
        }
        job = scope.launch {
            var terminal = ExportStatus(error = "exportFailed")
            try {
                val uri = export(request)
                terminal = ExportStatus(progress = 100, uri = uri, stage = "saved")
            } catch (e: CancellationException) {
                terminal = ExportStatus(stage = "cancelled")
            } catch (e: Exception) {
                android.util.Log.e("AquaRestore", "Export failed", e)
                terminal = ExportStatus(error = (e as? MediaProblem)?.key ?: "exportFailed")
            } finally {
                Exports.request = null
                if (wakeLock?.isHeld == true) wakeLock?.release()
                stopForeground(STOP_FOREGROUND_REMOVE)
                job = null
                stopSelf(startId)
                Exports.status.value = terminal
            }
        }
        return START_NOT_STICKY
    }

    private fun notification(progress: Int?): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val cancel = PendingIntent.getService(this, 1, Intent(this, ExportService::class.java).setAction("cancel"), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, "exports").setSmallIcon(R.drawable.ic_notification).setColor(0xFF3EDBC0.toInt())
            .setContentTitle("AquaRestore")
            .setContentText(if (chinese) "正在匯出修復作品…" else "Exporting your restored media…")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setProgress(100, progress ?: 0, progress == null)
            .addAction(0, if (chinese) "取消" else "Cancel", cancel).build()
    }

    private fun update(value: Int?, stage: String = "exporting") {
        Exports.status.value = ExportStatus(busy = true, progress = value, stage = stage)
        if (SystemClock.elapsedRealtime() - lastNotification > 800) {
            getSystemService(NotificationManager::class.java).notify(7, notification(value))
            lastNotification = SystemClock.elapsedRealtime()
        }
    }

    private suspend fun export(request: ExportRequest): Uri {
        val source = request.source
        val o = request.options
        val losslessImage = o.png
        val extension = if (source.video) "mp4" else if (losslessImage) "png" else "jpg"
        val temp = File(cacheDir, "export-${System.nanoTime()}.$extension")
        var pending: Uri? = null
        var published = false
        try {
            if (source.video) {
                val edge = if (o.original) 0 else o.longEdge
                val effects = mutableListOf<Effect>()
                effects += MediaIO.resizeEffect(source, edge)
                // Speeding up keeps the source frame rate by dropping frames, rather than multiplying it.
                val fpsLimit = if (!o.original && o.fps > 0) min(o.fps.toFloat(), source.fps) else source.fps
                if (fpsLimit < source.fps * o.speed) effects += FrameRateCap(fpsLimit)
                effects += UnderwaterEffect(GradeState(request.grade))
                val mime = exportVideoMime(source, o)
                val plan = videoExportPlan(source.width, source.height, source.fps, source.bitrate,
                    source.audioBitrate, source.durationMs, o, request.audio.changesAudio)
                MediaIO.transform(this, source, temp, effects, plan.bitrate, mime, true, speed = o.speed, startMs = o.startMs, endMs = o.endMs,
                    audio = request.audio) { update(it?.let { p -> p * 90 / 100 }) }
            } else {
                withContext(Dispatchers.Default) {
                    // The memory check is an estimate; running out anyway still reports it instead of crashing.
                    val bitmap = try { MediaIO.bitmap(this@ExportService, source.uri, if (o.original) 0 else o.longEdge) }
                        catch (_: OutOfMemoryError) { throw MediaProblem("memory") }
                    try {
                        MediaIO.gradeBitmap(bitmap, request.grade) { update(it * 80 / 100) }
                        update(82, "encoding")
                        temp.outputStream().use {
                            check(bitmap.compress(if (losslessImage) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, o.quality, it))
                        }
                    } catch (_: OutOfMemoryError) { throw MediaProblem("memory") }
                    finally { bitmap.recycle() }
                }
            }
            currentCoroutineContext().ensureActive()
            update(90, "saving")
            val savedUri = withContext(Dispatchers.IO) {
                val collection = if (source.video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                val mime = if (source.video) "video/mp4" else if (losslessImage) "image/png" else "image/jpeg"
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, exportFileName(source.name, extension))
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, if (source.video) "Movies/AquaRestore" else "Pictures/AquaRestore")
                    // A restoration is a new picture: file it under when it was made, not when the source was taken.
                    put(MediaStore.MediaColumns.DATE_TAKEN, System.currentTimeMillis())
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(collection, values) ?: error("Cannot create destination")
                pending = uri
                contentResolver.openOutputStream(uri)?.use { out ->
                    temp.inputStream().use { input ->
                        val buffer = ByteArray(256 * 1024)
                        var written = 0L
                        while (true) {
                            ensureActive()
                            val count = input.read(buffer)
                            if (count < 0) break
                            out.write(buffer, 0, count)
                            written += count
                            update(90 + (written * 9 / temp.length().coerceAtLeast(1)).toInt(), "saving")
                        }
                    }
                } ?: error("Cannot write destination")
                ensureActive()
                uri
            }
            // Once publication starts, finish the short transaction and report success. Otherwise
            // cancelling at 99% could leave a saved file while the UI incorrectly says "cancelled".
            return withContext(NonCancellable) {
                withContext(Dispatchers.IO) {
                    check(contentResolver.update(savedUri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1)
                }
                published = true
                savedUri
            }
        } finally {
            temp.delete()
            if (!published) pending?.let { withContext(NonCancellable + Dispatchers.IO) { contentResolver.delete(it, null, null) } }
        }
    }

    override fun onTimeout(startId: Int, fgsType: Int) { job?.cancel(); stopSelf() }
    override fun onDestroy() {
        scope.cancel()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        super.onDestroy()
    }
}

package com.aquarestore.app

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

/**
 * Each video is a full re-encode, so a batch takes minutes per clip, not seconds. The service still handles one
 * at a time, so memory use does not grow with the batch; the limit keeps time, heat and storage in check.
 */
const val MAX_BATCH_VIDEOS = 20

/** Headroom left on the device, so a batch never fills it to the last byte. */
const val BATCH_VIDEO_SPACE_MARGIN = 200_000_000L

data class BatchVideoRequest(val videos: List<Uri>, val selection: ExportSelection,
    override val chinese: Boolean) : ExportWork {
    init {
        require(videos.size in 1..MAX_BATCH_VIDEOS)
        require(videos.distinct().size == videos.size)
    }
}

/**
 * Storage a batch of videos of these estimated sizes needs: every finished video stays in the gallery, and the
 * one being exported is written to the cache first and then copied, so it briefly takes twice its size.
 */
fun batchVideoSpace(sizes: List<Long>): Long = sizes.sum() + (sizes.maxOrNull() ?: 0L) + BATCH_VIDEO_SPACE_MARGIN

/** The options a batch exports this video with: the whole clip, at normal speed, with its own audio. */
fun ExportSelection.batchVideoOptions(source: SourceMedia): ExportOptions = videoOptions(source.width, source.height, source.fps)
fun BatchVideoRequest.options(source: SourceMedia): ExportOptions = selection.batchVideoOptions(source)

fun estimatedVideoBytes(source: SourceMedia, options: ExportOptions): Long? = videoExportPlan(source.width, source.height,
    source.fps, source.bitrate, source.audioBitrate, source.durationMs, options).estimatedBytes

private fun durationText(ms: Long): String {
    val seconds = (ms + 500) / 1000
    return if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
        else "%d:%02d".format(seconds / 60, seconds % 60)
}

/** A closed dialog stops inspecting the remaining clips, including when the current read finishes late. */
internal suspend fun <Item, Metadata : Any> readBatchVideoMetadata(videos: List<Item>, inspect: (Item) -> Metadata?): List<Metadata> =
    withContext(Dispatchers.IO) {
        videos.mapNotNull { video ->
            ensureActive()
            try { inspect(video) }
            catch (e: CancellationException) { throw e }
            catch (_: Exception) { null }
        }
    }

@Composable
fun BatchVideoExportDialog(videos: List<Uri>, selection: ExportSelection, s: Strings,
    onSelectionChange: (ExportSelection) -> Unit, onResetCustom: () -> Unit,
    onDismiss: () -> Unit, onExport: () -> Unit) {
    val context = LocalContext.current
    // Only the metadata is read here; frames are decoded later, one video at a time, by the export service.
    val sources by produceState<List<SourceMedia>?>(null, videos) {
        value = readBatchVideoMetadata(videos) { MediaIO.inspect(context, it).takeIf { source -> source.video } }
    }
    val free = remember { context.cacheDir.usableSpace }
    AlertDialog(onDismissRequest = onDismiss,
        title = { Text(s.text("Export ${videos.size} videos", "匯出 ${videos.size} 段影片")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(s.text("Developer tools · experimental", "開發者工具 · 實驗功能"), fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Text(s.text("Each video gets its own intelligent restoration automatically and is exported whole, with its own audio: no trim, speed or music. Videos are processed one at a time.",
                    "每段影片會自動套用個別的智慧還原設定，並以原聲完整匯出，不剪輯、不變速、不加音樂。影片會逐段處理。"))
                Choices(listOf(ExportMode.RECOMMENDED to s.text("Recommended", "建議"),
                    ExportMode.ORIGINAL to s.text("Original", "原始"), ExportMode.CUSTOM to s.text("Custom", "自訂")),
                    selection.mode) { onSelectionChange(selection.copy(mode = it)) }
                when (selection.mode) {
                    ExportMode.RECOMMENDED -> Text(s.text(
                        "Keeps lower source dimensions and frame rates; caps larger video at 1080p and 30 fps with a balanced bitrate. The fastest choice for a batch.",
                        "保留較低的原始尺寸與幀率；較大的影片最多輸出 1080p、30 幀，並平衡位元率。批次處理最快的選擇。"), fontSize = 12.sp)
                    ExportMode.ORIGINAL -> Text(s.text(
                        "Keeps each video's dimensions, frames, codec and bitrate. Large or high-frame-rate video takes much longer and makes larger files.",
                        "保留每段影片的尺寸、影格、編碼格式與位元率。大尺寸或高幀率影片會花費更長時間，檔案也更大。"), fontSize = 12.sp)
                    ExportMode.CUSTOM -> {
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Text(s.text("Resolution · longest edge", "解析度 · 最長邊"), Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                            TextButton(onClick = onResetCustom, enabled = selection != ExportSelection(mode = ExportMode.CUSTOM)) {
                                Text(s.text("Reset to defaults", "恢復預設值"), fontSize = 12.sp)
                            }
                        }
                        Choices(listOf(0 to s.text("Source", "原尺寸"), 3840 to "3840", 2560 to "2560", 1920 to "1920",
                            1280 to "1280", 960 to "960", 640 to "640"), selection.longEdge) { onSelectionChange(selection.copy(longEdge = it)) }
                        Text(s.text("Frame rate", "幀率"), fontWeight = FontWeight.SemiBold)
                        Choices(listOf(0 to s.text("Original", "原始")) + listOf(24, 25, 30, 50, 60).map { it to "$it fps" }, selection.fps) {
                            onSelectionChange(selection.copy(fps = it))
                        }
                        Text(s.text("Never enlarges a video or adds frames: a video already smaller or slower keeps its own size and rate.",
                            "不會放大影片或插幀：已較小或幀率較低的影片保留原尺寸與幀率。"), fontSize = 11.sp)
                        Text(s.text("Quality", "畫質") + " · ${selection.quality}%", fontWeight = FontWeight.SemiBold)
                        Slider(selection.quality.toFloat(), { onSelectionChange(selection.copy(quality = it.roundToInt())) }, valueRange = 10f..100f)
                    }
                }
                val found = sources
                if (found == null) Text(s.text("Reading the videos…", "正在讀取影片…"), fontSize = 12.sp)
                else {
                    val sizes = found.map { estimatedVideoBytes(it, selection.batchVideoOptions(it)) ?: 0L }
                    val needed = batchVideoSpace(sizes)
                    Text(s.text("Total length ${durationText(found.sumOf { it.durationMs })} · about ${batchSizeText(sizes.sum())}",
                        "總長度 ${durationText(found.sumOf { it.durationMs })} · 約 ${batchSizeText(sizes.sum())}"),
                        Modifier.testTag("batchVideoEstimate"), fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    Text(s.text("Needs about ${batchSizeText(needed)} free while exporting; ${batchSizeText(free)} is free.",
                        "匯出期間約需 ${batchSizeText(needed)} 可用空間；目前可用 ${batchSizeText(free)}。"), fontSize = 12.sp,
                        color = if (needed > free) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                    if (needed > free) Text(s.text("Not enough space for every video. Videos that do not fit are skipped.",
                        "空間不足以容納所有影片，放不下的影片會略過。"), fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
                    if (found.size < videos.size) Text(s.text("${videos.size - found.size} could not be read and will be reported as failed.",
                        "${videos.size - found.size} 段無法讀取，將列為失敗。"), fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
                }
                Text(s.text("Long batches take a while and warm the phone. Exporting pauses between videos while it is too hot. Keep it plugged in for large batches.",
                    "大量影片需要較長時間，手機也會發熱；過熱時會在影片之間暫停。大量匯出時建議接上電源。"), fontSize = 11.sp)
                Text(s.text("Saved to Gallery / AquaRestore. The original files are never overwritten.",
                    "儲存至相簿／AquaRestore，不覆蓋原始檔案。"), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = { Button(onClick = onExport, enabled = sources != null) { Text(s.text("Start export", "開始匯出")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(s.text("Cancel", "取消")) } })
}

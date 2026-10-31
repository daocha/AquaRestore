package com.aquarestore.app

import android.content.Context
import android.graphics.BitmapFactory
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
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

// The service only decodes one photo at a time, so a larger batch does not multiply image memory use.
const val MAX_BATCH_PHOTOS = 100

data class BatchPhotoRequest(val photos: List<Uri>, val selection: ExportSelection,
    override val chinese: Boolean) : ExportWork {
    init {
        require(photos.size in 1..MAX_BATCH_PHOTOS)
        require(photos.distinct().size == photos.size)
    }
}

data class PhotoExportFailure(val name: String, val error: String)
data class BatchExportStatus(val total: Int, val saved: List<Uri> = emptyList(),
    val failures: List<PhotoExportFailure> = emptyList(), val currentName: String? = null, val videos: Boolean = false) {
    val completed: Int get() = saved.size + failures.size
}

@Composable
fun BatchPhotoExportDialog(photos: List<Uri>, selection: ExportSelection, s: Strings,
    onSelectionChange: (ExportSelection) -> Unit, onResetCustom: () -> Unit,
    onDismiss: () -> Unit, onExport: () -> Unit) {
    val count = photos.size
    val context = LocalContext.current
    // Only the file headers are read, so even a full batch is quick; the photos themselves are not decoded.
    val headers by produceState<List<PhotoHeader>?>(null, photos) {
        value = withContext(Dispatchers.IO) { photos.mapNotNull { ensureActive(); photoHeader(context, it) } }
    }
    AlertDialog(onDismissRequest = onDismiss,
        title = { Text(s.text("Export $count photos", "匯出 $count 張照片")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(s.text("Each photo gets its own intelligent restoration automatically. Photos are processed one at a time.",
                    "每張照片會自動套用個別的智慧還原設定，並逐張處理。"))
                Choices(listOf(ExportMode.RECOMMENDED to s.text("Recommended", "建議"),
                    ExportMode.ORIGINAL to s.text("Original", "原始"), ExportMode.CUSTOM to s.text("Custom", "自訂")),
                    selection.mode) { onSelectionChange(selection.copy(mode = it)) }
                when (selection.mode) {
                    ExportMode.RECOMMENDED -> Text(s.text(
                        "Keeps smaller photos at full size; caps larger photos at a 2560 px long edge. PNG sources stay PNG; others use high-quality JPEG.",
                        "較小照片保留原尺寸，較大照片的最長邊限制為 2560 像素。PNG 來源維持 PNG，其餘使用高畫質 JPEG。"), fontSize = 12.sp)
                    ExportMode.ORIGINAL -> {
                        Choices(listOf(false to "JPEG", true to "PNG"), selection.png) { onSelectionChange(selection.copy(png = it)) }
                        Text(if (selection.png) s.text(
                            "Full source dimensions, saved as lossless PNG after color correction. Files are several times larger than JPEG. Metadata is not copied.",
                            "保留原始尺寸，調色後儲存為無損 PNG。檔案比 JPEG 大數倍，不複製中繼資料。")
                        else s.text("Full source dimensions, saved as full-quality JPEG after color correction. Metadata is not copied.",
                            "保留原始尺寸，調色後儲存為最高畫質 JPEG，不複製中繼資料。"), fontSize = 12.sp)
                    }
                    ExportMode.CUSTOM -> {
                        Text(s.text("Resolution · longest edge", "解析度 · 最長邊"), fontWeight = FontWeight.SemiBold)
                        Choices(listOf(0 to s.text("Source", "原尺寸"), 3840 to "3840", 2560 to "2560", 1920 to "1920",
                            1280 to "1280", 960 to "960", 640 to "640"), selection.longEdge) {
                            onSelectionChange(selection.copy(longEdge = it))
                        }
                        Text(s.text("Keeps each photo's aspect ratio; never enlarges smaller photos.", "保留每張照片的比例，不放大較小的照片。"), fontSize = 12.sp)
                        Choices(listOf(false to "JPEG", true to "PNG"), selection.png) { onSelectionChange(selection.copy(png = it)) }
                        TextButton(onClick = onResetCustom, enabled = selection != ExportSelection(mode = ExportMode.CUSTOM)) {
                            Text(s.text("Reset to defaults", "恢復預設值"))
                        }
                        if (!selection.png) {
                            Text(s.text("Quality", "畫質") + " · ${selection.quality}%", fontWeight = FontWeight.SemiBold)
                            Slider(selection.quality.toFloat(), { onSelectionChange(selection.copy(quality = it.roundToInt())) }, valueRange = 10f..100f)
                            Text(s.text("JPEG compression quality.", "JPEG 壓縮畫質。"), fontSize = 11.sp)
                        }
                    }
                }
                val found = headers
                Text(s.text("Estimated total size", "預估總大小") + " · " + (found?.let { "≈ " + batchSizeText(batchPhotoBytes(it, selection)) }
                    ?: s.text("measuring…", "測量中…")), Modifier.testTag("estimatedSize"),
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                Text(s.text("Based on each photo's resolution, format and quality. Actual size varies with image detail.",
                    "依每張照片的解析度、格式與畫質估算；實際大小會隨影像細節而變。"), fontSize = 11.sp)
                if (found != null && found.size < count) Text(s.text("${count - found.size} could not be read and are not counted.",
                    "${count - found.size} 張無法讀取，未計入。"), fontSize = 11.sp, color = MaterialTheme.colorScheme.error)
                Text(s.text("Saved to Gallery / AquaRestore. The original files are never overwritten.",
                    "儲存至相簿／AquaRestore，不覆蓋原始檔案。"), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = { Button(onClick = onExport) { Text(s.text("Start export", "開始匯出")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(s.text("Cancel", "取消")) } })
}

data class PhotoHeader(val width: Int, val height: Int, val mime: String)

/** A photo's dimensions from its header alone, or null if it cannot be read. */
private fun photoHeader(context: Context, uri: Uri): PhotoHeader? = runCatching {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    PhotoHeader(bounds.outWidth, bounds.outHeight, context.contentResolver.getType(uri) ?: bounds.outMimeType ?: "image/jpeg")
        .takeIf { it.width > 0 && it.height > 0 }
}.getOrNull()

/** The batch's total from each photo's own export options, as the service will resolve them. */
fun batchPhotoBytes(photos: List<PhotoHeader>, selection: ExportSelection): Long =
    photos.sumOf { photoEstimatedBytes(it.width, it.height, selection.photoOptions(it.width, it.height, it.mime)) }

fun batchSizeText(bytes: Long): String = when {
    bytes >= 1_000_000_000L -> "%.2f GB".format(bytes / 1_000_000_000.0)
    bytes >= 1_000_000L -> "%.1f MB".format(bytes / 1_000_000.0)
    else -> "%.0f KB".format(bytes / 1_000.0)
}

fun BatchExportStatus.progressText(s: Strings): String {
    val current = (completed + 1).coerceAtMost(total)
    return (if (videos) s.text("Video $current of $total", "第 $current／$total 段影片")
        else s.text("Photo $current of $total", "第 $current／$total 張")) + (currentName?.let { " · $it" } ?: "")
}

fun BatchExportStatus.resultText(s: Strings): String {
    val remaining = total - completed
    return (if (videos) s.text("${saved.size} of $total videos saved to Gallery / AquaRestore.", "已將 ${saved.size}／$total 段影片儲存至相簿／AquaRestore。")
        else s.text("${saved.size} of $total photos saved to Gallery / AquaRestore.", "已將 ${saved.size}／$total 張照片儲存至相簿／AquaRestore。")) +
        (if (failures.isEmpty()) "" else if (videos) s.text("\n${failures.size} failed.", "\n${failures.size} 段失敗。")
            else s.text("\n${failures.size} failed.", "\n${failures.size} 張失敗。")) +
        (if (remaining == 0) "" else if (videos) s.text("\n$remaining not processed. Completed videos are kept.", "\n$remaining 段未處理。已完成的影片會保留。")
            else s.text("\n$remaining not processed. Completed photos are kept.", "\n$remaining 張未處理。已完成的照片會保留。"))
}

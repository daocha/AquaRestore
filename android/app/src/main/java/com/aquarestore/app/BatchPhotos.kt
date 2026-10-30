package com.aquarestore.app

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

// Keep sessions manageable on midrange phones. The service only decodes one photo at a time.
const val MAX_BATCH_PHOTOS = 20

data class BatchPhotoRequest(val photos: List<Uri>, val selection: ExportSelection,
    override val chinese: Boolean) : ExportWork {
    init {
        require(photos.size in 1..MAX_BATCH_PHOTOS)
        require(photos.distinct().size == photos.size)
    }
}

data class PhotoExportFailure(val name: String, val error: String)
data class BatchExportStatus(val total: Int, val saved: List<Uri> = emptyList(),
    val failures: List<PhotoExportFailure> = emptyList(), val currentName: String? = null) {
    val completed: Int get() = saved.size + failures.size
}

@Composable
fun BatchPhotoExportDialog(count: Int, selection: ExportSelection, s: Strings,
    onSelectionChange: (ExportSelection) -> Unit, onResetCustom: () -> Unit,
    onDismiss: () -> Unit, onExport: () -> Unit) {
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
                Text(s.text("Saved to Gallery / AquaRestore. The original files are never overwritten.",
                    "儲存至相簿／AquaRestore，不覆蓋原始檔案。"), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = { Button(onClick = onExport) { Text(s.text("Start export", "開始匯出")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(s.text("Cancel", "取消")) } })
}

fun BatchExportStatus.progressText(s: Strings): String =
    s.text("Photo ${(completed + 1).coerceAtMost(total)} of $total", "第 ${(completed + 1).coerceAtMost(total)}／$total 張") +
        (currentName?.let { " · $it" } ?: "")

fun BatchExportStatus.resultText(s: Strings): String {
    val remaining = total - completed
    return s.text("${saved.size} of $total photos saved to Gallery / AquaRestore.", "已將 ${saved.size}／$total 張照片儲存至相簿／AquaRestore。") +
        (if (failures.isEmpty()) "" else s.text("\n${failures.size} failed.", "\n${failures.size} 張失敗。")) +
        (if (remaining == 0) "" else s.text("\n$remaining not processed. Completed photos are kept.", "\n$remaining 張未處理。已完成的照片會保留。"))
}

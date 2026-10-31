package com.aquarestore.app

class Strings(val chinese: Boolean) {
    fun text(en: String, zh: String) = if (chinese) zh else en
    operator fun get(key: String): String {
        val pair = values[key] ?: return key
        return text(pair.first, pair.second)
    }
    companion object {
        private val values = mapOf(
            "preparing" to ("Decoding in software…" to "正在以軟體解碼…"),
            "analyzing" to ("Reading the water’s colors…" to "正在分析水下色彩…"),
            "exporting" to ("Restoring at full quality…" to "正在以匯出畫質還原…"),
            "encoding" to ("Encoding your image…" to "正在編碼圖片…"),
            "saving" to ("Saving to your gallery…" to "正在儲存至相簿…"),
            "saved" to ("Saved to your gallery" to "已儲存至相簿"),
            "cancelled" to ("Export cancelled" to "已取消匯出"),
            "cooling" to ("Letting the phone cool down…" to "正在讓手機降溫…"),
            "batchFinished" to ("Batch export finished" to "批次匯出已完成"),
            "photoUnreadable" to ("Could not read this photo. It may have been deleted, moved, or saved in an unsupported format." to "無法讀取此照片，可能已被刪除、移動，或為不支援的格式。"),
            "batchPhotosOnly" to ("Batch restore supports photos only. Videos cannot be processed in a batch." to "批次還原僅支援照片，無法批次處理影片。"),
            "batchVideosOnly" to ("This batch takes videos only." to "此批次僅處理影片。"),
            "videoUnreadable" to ("Could not read this video. It may have been deleted, moved, or saved in an unsupported format." to "無法讀取此影片，可能已被刪除、移動，或為不支援的格式。"),
            "videoNeedsEditor" to ("This video needs software decoding on this device. Open it in the editor to restore it." to "此影片在此裝置上需要以軟體解碼，請在編輯器中開啟以進行還原。"),
            "timedOut" to ("Android stopped the export after its time limit for background work. Items already saved are kept; export the rest later." to "Android 已因背景工作時間上限停止匯出。已儲存的項目會保留，其餘請稍後再匯出。"),
            "storageFull" to ("Not enough free storage for this video. Free up space, or export with a lower resolution." to "剩餘空間不足以匯出此影片。請釋放空間，或以較低解析度匯出。"),
            "hdrDevice" to ("HDR preservation requires Android 13+ and a compatible 10-bit HDR encoder. This device cannot provide that export. No automatic SDR conversion was performed." to "保留 HDR 需要 Android 13 以上及相容的 10-bit HDR 編碼器。此裝置無法提供該匯出，沒有自動轉換成 SDR。"),
            "dolbyVision" to ("Dolby Vision needs dynamic metadata processing that is not implemented yet. Standard HDR10 / PQ and HLG are supported on compatible devices." to "Dolby Vision 需要尚未實作的動態中繼資料處理。標準 HDR10／PQ 與 HLG 可在相容裝置上處理。"),
            "dynamicHdr" to ("HDR10+ dynamic metadata cannot currently be preserved. Please use a standard HDR10 or HLG source." to "目前無法保留 HDR10+ 動態中繼資料，請使用標準 HDR10 或 HLG 素材。"),
            "tooLarge" to ("This video's frame size is larger than this device can decode." to "此影片的畫面尺寸超出此裝置可解碼的範圍。"),
            "unsupported" to ("This media format is not supported." to "尚不支援此媒體格式。"),
            "memory" to ("This image is too large for the available memory. Choose a smaller export size." to "此圖片超過可用記憶體，請選擇較小的匯出尺寸。"),
            "analysisFailed" to ("Could not read sample frames. Please try another file." to "無法讀取抽樣畫面，請嘗試其他檔案。"),
            "importFailed" to ("Could not prepare this file. Check available storage and try another video or image." to "無法準備此檔案，請檢查剩餘空間或嘗試其他影片與圖片。"),
            "exportFailed" to ("Export failed. Check free storage and try Custom with a lower resolution. Original requires a compatible encoder; it never silently reduces quality." to "匯出失敗。請檢查剩餘空間，或選擇自訂並降低解析度。Original 需要相容編碼器，不會自動降低畫質。"),
            "playbackFailed" to ("Preview playback failed on this device. Please import the file again." to "此裝置無法播放預覽，請重新匯入檔案。"),
            "noAudio" to ("This file has no playable audio. Please choose a music file." to "此檔案沒有可播放的音訊，請選擇音樂檔案。"),
            "insufficient" to ("Not enough color information" to "畫面缺乏可判斷的色彩資訊"),
            "openFailed" to ("No app could open this file. It is saved in your gallery’s AquaRestore folder." to "沒有可開啟此檔案的 App，作品已儲存在相簿的 AquaRestore 資料夾。"),
            "blue" to ("Blue cast detected" to "偵測到偏藍色調"),
            "green" to ("Green cast detected" to "偵測到偏綠色調"),
            "hazy" to ("Washed-out, hazy water detected" to "偵測到泛白、混濁的水色"),
            "dark" to ("Deep, low-light water detected" to "偵測到深水低光環境"),
            "balanced" to ("Mostly balanced colors" to "色彩大致均衡"),
        )
    }
}

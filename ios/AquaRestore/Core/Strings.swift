import Foundation

struct Strings {
    let chinese: Bool
    func text(_ en: String, _ zh: String) -> String { chinese ? zh : en }
    subscript(_ key: String) -> String {
        guard let pair = Strings.values[key] else { return key }
        return text(pair.0, pair.1)
    }

    private static let values: [String: (String, String)] = [
        "analyzing": ("Reading the water’s colors…", "正在分析水下色彩…"),
        "exporting": ("Restoring at full quality…", "正在以匯出畫質還原…"),
        "encoding": ("Encoding your image…", "正在編碼圖片…"),
        "saving": ("Saving to your gallery…", "正在儲存至相簿…"),
        "saved": ("Saved to your gallery", "已儲存至相簿"),
        "cancelled": ("Export cancelled", "已取消匯出"),
        "hdrDevice": ("HDR preservation requires a compatible 10-bit HDR encoder. This device cannot provide that export. No automatic SDR conversion was performed.", "保留 HDR 需要相容的 10-bit HDR 編碼器。此裝置無法提供該匯出，沒有自動轉換成 SDR。"),
        "dolbyVision": ("Dolby Vision needs dynamic metadata processing that is not implemented yet. Standard HDR10 / PQ and HLG are supported on compatible devices.", "Dolby Vision 需要尚未實作的動態中繼資料處理。標準 HDR10／PQ 與 HLG 可在相容裝置上處理。"),
        "dynamicHdr": ("HDR10+ dynamic metadata cannot currently be preserved. Please use a standard HDR10 or HLG source.", "目前無法保留 HDR10+ 動態中繼資料，請使用標準 HDR10 或 HLG 素材。"),
        "unsupported": ("This media format is not supported.", "尚不支援此媒體格式。"),
        "originalCodec": ("Original cannot preserve this video codec in MP4. Choose Custom to export as H.264 or HEVC.", "Original 無法在 MP4 中保留此影片編碼格式。請選擇「自訂」，以 H.264 或 HEVC 匯出。"),
        "memory": ("This image is too large for the available memory. Choose a smaller export size.", "此圖片超過可用記憶體，請選擇較小的匯出尺寸。"),
        "analysisFailed": ("Could not read sample frames. Please try another file.", "無法讀取抽樣畫面，請嘗試其他檔案。"),
        "importFailed": ("Could not prepare this file. Check available storage and try another video or image.", "無法準備此檔案，請檢查剩餘空間或嘗試其他影片與圖片。"),
        "exportFailed": ("Export failed. Check free storage and try Custom with a lower resolution. Original requires a compatible encoder; it never silently reduces quality.", "匯出失敗。請檢查剩餘空間，或選擇自訂並降低解析度。Original 需要相容編碼器，不會自動降低畫質。"),
        "playbackFailed": ("Preview playback failed on this device. Please import the file again.", "此裝置無法播放預覽，請重新匯入檔案。"),
        "noAudio": ("This file has no playable audio. Please choose a music file.", "此檔案沒有可播放的音訊，請選擇音樂檔案。"),
        "insufficient": ("Not enough color information", "畫面缺乏可判斷的色彩資訊"),
        "photosDenied": ("AquaRestore needs permission to add photos. Allow it in Settings › AquaRestore › Photos.", "AquaRestore 需要新增照片的權限，請至「設定 › AquaRestore › 照片」允許。"),
        "blue": ("Blue cast detected", "偵測到偏藍色調"),
        "green": ("Green cast detected", "偵測到偏綠色調"),
        "hazy": ("Washed-out, hazy water detected", "偵測到泛白、混濁的水色"),
        "dark": ("Deep, low-light water detected", "偵測到深水低光環境"),
        "balanced": ("Mostly balanced colors", "色彩大致均衡"),
    ]
}

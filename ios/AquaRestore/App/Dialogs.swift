import SwiftUI

// Texts inside a Material AlertDialog inherit body-medium (14sp) in on-surface-variant, so a SemiBold label
// without a size is 14sp here, as in the Android dialogs.

struct SettingsDialog: View {
    @ObservedObject var model: EditorModel
    let dismiss: () -> Void
    @Environment(\.strings) private var s

    var body: some View {
        M3Dialog(title: s.text("Make it yours", "個人化設定"), dismiss: dismiss) {
            VStack(alignment: .leading, spacing: 12) {
                MText(s.text("Language", "語言"), weight: .semibold)
                Choices(items: [("system", s.text("System", "跟隨系統")), ("zh", "中文"), ("en", "English")], selected: model.language) { model.preference("language", $0) }
                MText(s.text("Appearance", "外觀"), weight: .semibold)
                Choices(items: [("system", s.text("System", "跟隨系統")), ("light", s.text("Light", "淺色")), ("dark", s.text("Dark", "深色"))], selected: model.theme) { model.preference("theme", $0) }
            }
        } buttons: {
            M3TextButton(title: s.text("Done", "完成"), action: dismiss)
        }
    }
}

struct ExportDialog: View {
    let source: SourceMedia
    let speed: Float
    let trim: MsRange
    let audio: AudioMix
    let onDismiss: () -> Void
    let export: (ExportOptions) -> Void

    @Environment(\.palette) private var c
    @Environment(\.strings) private var s
    @Environment(\.screenHeight) private var screenHeight
    @State private var original = true
    @State private var edge = 1920
    @State private var fps = 0
    @State private var quality: Float = 90
    @State private var png = false

    var body: some View {
        // Only a real cut is passed on, so an untrimmed export keeps the source's exact end.
        let startMs = trim.lowerBound
        let endMs: Int64 = trim.upperBound > 0 && trim.upperBound < source.durationMs ? trim.upperBound : 0
        let lengthMs = ExportOptions(startMs: startMs, endMs: endMs).trimmedMs(source.durationMs)
        M3Dialog(title: s.text("Export your restoration", "匯出還原作品"), dismiss: onDismiss) {
            ScrollIfNeeded(maxHeight: screenHeight * 0.55) {
                VStack(alignment: .leading, spacing: 10) {
                    Choices(items: [(true, "Original"), (false, s.text("Custom", "自訂"))], selected: original) { original = $0 }
                    if source.isHdr {
                        MText("\(source.hdrName) · 10-bit · BT.2020\n" + s.text("HDR is preserved in both modes. Preview brightness depends on your display.", "兩種模式均保留 HDR，預覽亮度取決於螢幕能力。"),
                              size: 12, color: c.primary)
                        if source.hdr == .pq {
                            MText(s.text("HDR10+ dynamic metadata, if present, is not preserved. The result keeps static HDR10 color.",
                                         "若來源包含 HDR10+ 動態中繼資料，匯出後不會保留；結果會維持靜態 HDR10 色彩。"),
                                  size: 12, color: c.onSurfaceVariant)
                        }
                    }
                    if source.video { MText(summary(startMs, endMs, lengthMs), size: 12) }
                    if source.video && audio.changesAudio { MText(audioSummary, size: 12) }
                    if original { originalInfo } else { customOptions }
                    if source.video { sizeEstimate(startMs, endMs) }
                    MText(s.text("Saved to your Photos library. The original file is never overwritten.", "儲存至相簿，不覆蓋原始檔案。"),
                          size: 11, color: c.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } buttons: {
            M3TextButton(title: s.text("Cancel", "取消"), action: onDismiss)
            M3Button(title: s.text("Start export", "開始匯出")) {
                export(ExportOptions(original: original, longEdge: edge, fps: fps, quality: Int(quality.rounded()), png: png, startMs: startMs, endMs: endMs))
            }
        }
    }

    private func summary(_ startMs: Int64, _ endMs: Int64, _ lengthMs: Int64) -> String {
        let seconds = String(format: "%.1f", Double(lengthMs) / Double(speed) / 1000)
        var text = s.text("Speed: \(speed)× · duration: \(seconds) s", "速度：\(speed)× · 時長：\(seconds) 秒")
        if endMs > 0 || startMs > 0 {
            text += s.text(" · trimmed \(clock(startMs))–\(clock(startMs + lengthMs))", " · 已剪輯 \(clock(startMs))–\(clock(startMs + lengthMs))")
        }
        return text
    }

    private var audioSummary: String {
        var text = s.text("Audio: original \(Int((audio.originalVolume * 100).rounded()))%", "音訊：原聲 \(Int((audio.originalVolume * 100).rounded()))%")
        if audio.hasMusic { text += s.text(" + music \(Int((audio.musicVolume * 100).rounded()))%", " ＋ 音樂 \(Int((audio.musicVolume * 100).rounded()))%") }
        return text
    }

    @ViewBuilder private var originalInfo: some View {
        MText("\(source.width) × \(source.height)" + (source.video ? " · \(String(format: "%.2f", source.fps * min(speed, 1))) fps" : " · PNG"), weight: .semibold)
        MText(source.video
              ? s.text("Keeps source dimensions, frame times and codec (AVC or HEVC). Selected speed retimes frames and audio. Targets the source video bitrate, adjusted for speed; estimates it only when unavailable. Color correction requires re-encoding, so it is not bit-for-bit lossless.",
                       "保留原尺寸、影格時間與編碼格式（AVC 或 HEVC）。所選速度會調整影格及音訊時間。優先沿用來源影片位元率並依速度調整，缺少資料時才估算。色彩校正需要重新編碼，無法完全無損。")
              : s.text("Full source dimensions, saved as lossless PNG after color correction. File size may increase. Metadata is not copied.",
                       "保留原始尺寸，調色後儲存為無損 PNG。檔案可能變大，不複製中繼資料。"), size: 12)
    }

    @ViewBuilder private var customOptions: some View {
        MText(s.text("Resolution · longest edge", "解析度 · 最長邊"), weight: .semibold)
        Choices(items: [(0, s.text("Source", "原尺寸")), (3840, "3840"), (2560, "2560"), (1920, "1920"), (1280, "1280"), (960, "960"), (640, "640")], selected: edge) { edge = $0 }
        let size = ExportSizing.dimensions(source.width, source.height, edge, even: source.video)
        MText("\(size.0) × \(size.1) px", size: 12, color: c.primary)
        if source.video {
            MText(s.text("Frame rate", "幀率"), weight: .semibold)
            Choices(items: [(0, "Original")] + [24, 25, 30, 50, 60].filter { Float($0) <= source.fps * min(speed, 1) }.map { ($0, "\($0) fps") }, selected: fps) { fps = $0 }
            MText(s.text("Lower frame rates drop frames; no interpolation. Output is H.264 for SDR or 10-bit HEVC for HDR. Untouched AAC audio is kept; edited audio is encoded as AAC.",
                         "較低幀率會抽幀，不插幀。SDR 輸出為 H.264，HDR 為 10-bit HEVC。未編輯的 AAC 音訊會保留，已編輯的音訊會編碼為 AAC。"), size: 11)
        } else {
            Choices(items: [(false, "JPEG"), (true, "PNG")], selected: png) { png = $0 }
        }
        if source.video || !png {
            MText(s.text("Quality", "畫質") + " · \(Int(quality.rounded()))%", weight: .semibold)
            M3Slider(value: quality, range: 10...100, onChange: { quality = $0 }, accessibility: s.text("Quality", "畫質"))
            MText(source.video
                  ? s.text("Controls target bitrate; higher values create larger files. 100% at source resolution and frame rate matches Original.", "調整目標位元率，數值越高，檔案越大。原尺寸、原幀率配合 100% 等同「Original」。")
                  : s.text("JPEG compression quality.", "JPEG 壓縮畫質。"), size: 11)
        }
    }

    @ViewBuilder private func sizeEstimate(_ startMs: Int64, _ endMs: Int64) -> some View {
        let plan = videoExportPlan(width: source.width, height: source.height, fps: source.fps, sourceBitrate: source.bitrate,
            audioBitrate: source.audioBitrate, durationMs: source.durationMs,
            options: ExportOptions(original: original, longEdge: edge, fps: fps, quality: Int(quality.rounded()), png: png, speed: speed, startMs: startMs, endMs: endMs),
            mixedAudio: audio.changesAudio)
        let size = plan.estimatedBytes.map { bytes in
            bytes >= 1_000_000_000 ? String(format: "%.2f GB", Double(bytes) / 1_000_000_000) : String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } ?? s.text("Unavailable", "無法估算")
        MText(s.text("Estimated file size", "預估檔案大小") + " · ≈ " + size, weight: .semibold, color: c.primary)
            .accessibilityIdentifier("estimatedSize")
        MText(s.text("Based on target bitrate, audio and duration. Actual size varies with the encoder and scene detail; this is not a size limit.",
                     "依目標位元率、音訊與時長估算；實際大小受編碼器及畫面複雜度影響，不是檔案大小上限。"), size: 11)
    }
}

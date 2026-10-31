import SwiftUI

/// Settings for a batch of photos or videos, chosen once and resolved for each item, as on Android.
struct BatchExportDialog: View {
    let draft: BatchDraft
    let onDismiss: () -> Void
    let onStart: (ExportSelection) -> Void

    @Environment(\.palette) private var c
    @Environment(\.strings) private var s
    @Environment(\.screenHeight) private var screenHeight
    @State private var selection = ExportSelection()

    private var videos: Bool { draft.videos }

    var body: some View {
        M3Dialog(title: videos ? s.text("Export \(draft.total) videos", "匯出 \(draft.total) 段影片")
                 : s.text("Export \(draft.total) photos", "匯出 \(draft.total) 張照片"), dismiss: onDismiss) {
            ScrollIfNeeded(maxHeight: screenHeight * 0.55) {
                VStack(alignment: .leading, spacing: 10) {
                    keepOpenWarning
                    if videos {
                        MText(s.text("Developer tools · experimental", "開發者工具 · 實驗功能"), size: 12, weight: .semibold, color: c.primary)
                    }
                    MText(videos
                          ? s.text("Each video gets its own intelligent restoration automatically and is exported whole, with its own audio: no trim, speed or music. Videos are processed one at a time.",
                                   "每段影片會自動套用個別的智慧還原設定，並以原聲完整匯出，不剪輯、不變速、不加音樂。影片會逐段處理。")
                          : s.text("Each photo gets its own intelligent restoration automatically. Photos are processed one at a time.",
                                   "每張照片會自動套用個別的智慧還原設定，並逐張處理。"))
                    Choices(items: [(ExportMode.recommended, s.text("Recommended", "建議")), (.original, s.text("Original", "原始")), (.custom, s.text("Custom", "自訂"))],
                            selected: selection.mode) { selection.mode = $0 }
                    modeOptions
                    if draft.ready {
                        if !draft.sources.isEmpty { estimate }
                    } else { preparing }
                    preparationFailures
                    MText(s.text("Saved to your Photos library. The original files are never overwritten.", "儲存至相簿，不覆蓋原始檔案。"),
                          size: 11, color: c.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } buttons: {
            M3TextButton(title: s.text("Cancel", "取消"), action: onDismiss)
            M3Button(title: s.text("Start export", "開始匯出")) { onStart(selection) }
                .disabled(!draft.ready || draft.sources.isEmpty)
        }
    }

    /// iOS pauses the export whenever AquaRestore is not on screen, so the batch only runs while it stays open.
    private var keepOpenWarning: some View {
        MText(s.text("Keep AquaRestore open until the batch finishes. Don't switch apps or lock the screen: iOS pauses the batch while AquaRestore is in the background, and it continues only when you return.",
                     "批次完成前請保持 AquaRestore 開啟，不要切換 App 或鎖定螢幕：App 在背景時 iOS 會暫停批次，返回後才會繼續。"),
              size: 13, weight: .semibold, color: c.error)
            .accessibilityIdentifier("keepOpenWarning")
    }

    @ViewBuilder private var modeOptions: some View {
        switch selection.mode {
        case .recommended:
            MText(videos
                  ? s.text("Keeps lower source dimensions and frame rates; caps larger video at 1080p and 30 fps with a balanced bitrate. The fastest choice for a batch.",
                           "保留較低的原始尺寸與幀率；較大的影片最多輸出 1080p、30 幀，並平衡位元率。批次處理最快的選擇。")
                  : s.text("Keeps smaller photos at full size; caps larger photos at a 2560 px long edge. PNG sources stay PNG; others use high-quality JPEG.",
                           "較小照片保留原尺寸，較大照片的最長邊限制為 2560 像素。PNG 來源維持 PNG，其餘使用高畫質 JPEG。"), size: 12)
        case .original:
            if videos {
                MText(s.text("Keeps each video's dimensions, frames and codec (AVC or HEVC). Large or high-frame-rate video takes much longer and makes larger files.",
                             "保留每段影片的尺寸、影格與編碼格式（AVC 或 HEVC）。大尺寸或高幀率影片會花費更長時間，檔案也更大。"), size: 12)
            } else {
                Choices(items: [(false, "JPEG"), (true, "PNG")], selected: selection.png) { selection.png = $0 }
                MText(selection.png
                      ? s.text("Full source dimensions, saved as lossless PNG after color correction. Files are several times larger than JPEG. Metadata is not copied.",
                               "保留原始尺寸，調色後儲存為無損 PNG。檔案比 JPEG 大數倍，不複製中繼資料。")
                      : s.text("Full source dimensions, saved as full-quality JPEG after color correction. Metadata is not copied.",
                               "保留原始尺寸，調色後儲存為最高畫質 JPEG，不複製中繼資料。"), size: 12)
            }
        case .custom:
            HStack {
                MText(s.text("Resolution · longest edge", "解析度 · 最長邊"), weight: .semibold)
                Spacer()
                M3TextButton(title: s.text("Reset to defaults", "恢復預設值")) { selection = ExportSelection(mode: .custom) }
                    .disabled(selection == ExportSelection(mode: .custom))
            }
            Choices(items: [(0, s.text("Source", "原尺寸")), (3840, "3840"), (2560, "2560"), (1920, "1920"), (1280, "1280"), (960, "960"), (640, "640")],
                    selected: selection.longEdge) { selection.longEdge = $0 }
            if videos {
                MText(s.text("Frame rate", "幀率"), weight: .semibold)
                Choices(items: [(0, s.text("Original", "原始"))] + [24, 25, 30, 50, 60].map { ($0, "\($0) fps") }, selected: selection.fps) { selection.fps = $0 }
                MText(s.text("Never enlarges a video or adds frames: a video already smaller or slower keeps its own size and rate.",
                             "不會放大影片或插幀：已較小或幀率較低的影片保留原尺寸與幀率。"), size: 11)
            } else {
                MText(s.text("Keeps each photo's aspect ratio; never enlarges smaller photos.", "保留每張照片的比例，不放大較小的照片。"), size: 12)
                Choices(items: [(false, "JPEG"), (true, "PNG")], selected: selection.png) { selection.png = $0 }
            }
            if videos || !selection.png {
                MText(s.text("Quality", "畫質") + " · \(selection.quality)%", weight: .semibold)
                M3Slider(value: Float(selection.quality), range: 10...100, onChange: { selection.quality = Int($0.rounded()) },
                         accessibility: s.text("Quality", "畫質"))
            }
        }
    }

    private var preparing: some View {
        VStack(alignment: .leading, spacing: 6) {
            MText(s["preparing"] + " \(draft.prepared) / \(draft.total)", size: 12)
            Progress(value: draft.total > 0 ? draft.prepared * 100 / draft.total : nil)
        }
    }

    @ViewBuilder private var estimate: some View {
        if videos {
            let sizes = draft.sources.map { source in
                BatchRun.estimatedBytes(source, selection.videoOptions(width: source.width, height: source.height,
                                                                       fps: source.fps, codec: source.codec, hdr: source.isHdr)) ?? 0
            }
            let needed = batchVideoSpace(sizes)
            let free = BatchRun.freeSpace
            MText(s.text("Total length \(batchDurationText(draft.sources.reduce(0) { $0 + $1.durationMs })) · about \(batchSizeText(sizes.reduce(0, +)))",
                         "總長度 \(batchDurationText(draft.sources.reduce(0) { $0 + $1.durationMs })) · 約 \(batchSizeText(sizes.reduce(0, +)))"),
                  weight: .semibold, color: c.primary)
                .accessibilityIdentifier("estimatedSize")
            if let free {
                MText(s.text("Needs about \(batchSizeText(needed)) free while exporting; \(batchSizeText(free)) is free.",
                             "匯出期間約需 \(batchSizeText(needed)) 可用空間；目前可用 \(batchSizeText(free))。"),
                      size: 12, color: needed > free ? c.error : c.onSurfaceVariant)
                if needed > free {
                    MText(s.text("Not enough space for every video. Videos that do not fit are skipped.", "空間不足以容納所有影片，放不下的影片會略過。"),
                          size: 12, color: c.error)
                }
            }
            MText(s.text("Long batches take a while and warm the phone. Exporting pauses between videos while it is too hot. Keep it plugged in for large batches.",
                         "大量影片需要較長時間，手機也會發熱；過熱時會在影片之間暫停。大量匯出時建議接上電源。"), size: 11)
        } else {
            let bytes = draft.sources.reduce(Int64(0)) { total, source in
                total + photoEstimatedBytes(width: source.width, height: source.height, options: selection.photoOptions(
                    width: source.width, height: source.height, pngSource: source.url.pathExtension.lowercased() == "png"))
            }
            MText(s.text("Estimated total size", "預估總大小") + " · ≈ " + batchSizeText(bytes), weight: .semibold, color: c.primary)
                .accessibilityIdentifier("estimatedSize")
            MText(s.text("Based on each photo's resolution, format and quality. Actual size varies with image detail.",
                         "依每張照片的解析度、格式與畫質估算；實際大小會隨影像細節而變。"), size: 11)
        }
    }

    @ViewBuilder private var preparationFailures: some View {
        if !draft.failures.isEmpty {
            MText(videos ? s.text("Could not prepare \(draft.failures.count) videos.", "無法準備 \(draft.failures.count) 段影片。")
                  : s.text("Could not prepare \(draft.failures.count) photos.", "無法準備 \(draft.failures.count) 張照片。"), size: 12, color: c.error)
            ForEach(draft.failures.indices, id: \.self) { i in
                MText("\(draft.failures[i].name)\n\(s[draft.failures[i].error])", size: 12, color: c.error)
                    .accessibilityIdentifier("batchPreparationFailure-\(i)")
            }
        }
    }
}

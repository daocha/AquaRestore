import SwiftUI

// Texts inside a Material AlertDialog inherit body-medium (14sp) in on-surface-variant, so a SemiBold label
// without a size is 14sp here, as in the Android dialogs.

struct SettingsDialog: View {
    @ObservedObject var model: EditorModel
    let dismiss: () -> Void
    @Environment(\.strings) private var s
    @Environment(\.palette) private var c
    @ObservedObject private var devTools = DevTools.shared
    @State private var versionTaps = 0
    @State private var showLog = false
    @State private var showUnlock = false
    @State private var referralError: String?
    @State private var savingFrames = false
    /// Android shows these as toasts.
    @State private var notice: String?

    var body: some View {
        ZStack {
            dialog
            if showLog { DevLogPanel { showLog = false } }
            if showUnlock { UnlockCodeDialog { showUnlock = false } }
            if let referralError {
                M3Dialog(title: s.text("Referral code", "推薦碼"), dismiss: { self.referralError = nil }) {
                    ReferralNoticeText(text: referralError)
                } buttons: {
                    M3TextButton(title: s.text("OK", "知道了")) { self.referralError = nil }
                }
            }
        }
    }

    private var dialog: some View {
        M3Dialog(title: s.text("Make it yours", "個人化設定"), dismiss: dismiss) {
            // As on Android, at most 480 tall; the developer tools scroll.
            ScrollIfNeeded(maxHeight: 480) { settingsColumn }
        } buttons: {
            M3TextButton(title: s.text("Done", "完成"), action: dismiss)
        }
    }

    private var settingsColumn: some View {
            VStack(alignment: .leading, spacing: 12) {
                MText(s.text("Language", "語言"), weight: .semibold)
                Choices(items: [("system", s.text("System", "跟隨系統")), ("zh", "中文"), ("en", "English")], selected: model.language) { model.preference("language", $0) }
                MText(s.text("Appearance", "外觀"), weight: .semibold)
                Choices(items: [("system", s.text("System", "跟隨系統")), ("light", s.text("Light", "淺色")), ("dark", s.text("Dark", "深色"))], selected: model.theme) { model.preference("theme", $0) }
                // Like Android's build number: ten taps on the version unlock the developer tools.
                MText(DevTools.version, size: 12, color: c.onSurfaceVariant)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if devTools.enabled { return }
                        versionTaps += 1
                        if versionTaps >= DevTools.unlockTaps { devTools.enable() }
                    }
                    .accessibilityIdentifier("version")
                if BatchAccess.shared.referralActive { ReferralSettings { referralError = $0 } }
                if devTools.enabled {
                    Rectangle().fill(c.outlineVariant).frame(height: 1)
                    HStack {
                        MText(s.text("Developer tools", "開發者工具"), weight: .semibold)
                        Spacer()
                        // Turning them off locks them again; ten taps on the version unlock them.
                        Toggle("", isOn: Binding(get: { true }, set: { on in if !on { devTools.disable(); versionTaps = 0 } }))
                            .labelsHidden().tint(c.primary)
                            .accessibilityLabel(s.text("Developer tools", "開發者工具"))
                    }
                    if BatchAccess.shared.gateConfigured {
                        M3Button(title: s.text("Unlock Code", "解鎖碼"), style: .outlined) { showUnlock = true }
                    }
                    M3Button(title: s.text("Developer logs", "開發者日誌"), style: .outlined) { showLog = true }
                    M3Button(title: s.text("Save logs", "儲存日誌"), style: .outlined) {
                        Task { notice = await DevLog.save().map { s.text("Saved to \($0)", "已儲存至 \($0)") } ?? s.text("Could not save the log", "無法儲存日誌") }
                    }
                    M3Button(title: s.text("Save analysis frames", "儲存分析畫面"), style: .outlined, spinner: savingFrames) { saveFrames() }
                        .disabled(model.source == nil || savingFrames)
                    if model.source == nil {
                        MText(s.text("Open a photo or video to save its analysis input.", "開啟照片或影片後，可儲存用於分析調色的畫面。"),
                              size: 12, color: c.onSurfaceVariant)
                    }
                    MText(s.text("Saved files are in the Files app: On My iPhone › AquaRestore.",
                                 "儲存的檔案位於「檔案」App：我的 iPhone › AquaRestore。"), size: 12, color: c.onSurfaceVariant)
                    if let notice { MText(notice, size: 12, color: c.primary) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveFrames() {
        guard let media = model.source else { return }
        savingFrames = true
        Task {
            let saved = (try? await MediaIO.saveAnalysisFrames(media)) ?? 0
            savingFrames = false
            notice = saved > 0 ? s.text("Saved \(saved) frames to On My iPhone › AquaRestore › frames", "已儲存 \(saved) 張畫面至「我的 iPhone › AquaRestore › frames」")
                : s.text("Could not save the frames", "無法儲存畫面")
        }
    }
}

private struct UnlockCodeDialog: View {
    let dismiss: () -> Void
    @Environment(\.strings) private var s
    @Environment(\.palette) private var c
    @State private var code = ""
    @State private var unlocking = false
    @State private var error: String?

    var body: some View {
        M3Dialog(title: s.text("Unlock Code", "解鎖碼"), dismiss: { if !unlocking { dismiss() } }) {
            VStack(alignment: .leading, spacing: 12) {
                MText(s.text("Redeeming sends an app-specific device identifier. The server stores it with the redemption record.",
                             "兌換時會傳送此 App 專用的裝置識別碼，伺服器會將其與兌換紀錄一起儲存。"), size: 12)
                SecureField(s.text("Code", "輸入解鎖碼"), text: Binding(get: { code }, set: { code = $0; error = nil }))
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(unlocking)
                if let error { MText(error, color: c.error) }
            }
        } buttons: {
            M3TextButton(title: s.text("Cancel", "取消"), action: dismiss).disabled(unlocking)
            M3Button(title: s.text("Unlock", "解鎖"), spinner: unlocking) {
                unlocking = true; error = nil
                Task {
                    defer { unlocking = false }
                    do {
                        try await ReferralCampaign.shared.request(unlockCode: code.trimmingCharacters(in: .whitespacesAndNewlines))
                        code = ""; dismiss()
                    } catch ReferralFailure.api(let reason) {
                        switch reason {
                        case "invalid_unlock_code": error = s.text("Incorrect unlock code", "解鎖碼不正確")
                        case "unlock_code_exhausted": error = s.text("Unlock code has reached its maximum uses.", "此解鎖碼已達使用次數上限。")
                        default: error = s.text("Could not redeem the code. Check your connection and try again.", "無法兌換解鎖碼。請檢查網路連線後重試。")
                        }
                    } catch {
                        if !Task.isCancelled { self.error = s.text("Could not redeem the code. Check your connection and try again.", "無法兌換解鎖碼。請檢查網路連線後重試。") }
                    }
                }
            }.disabled(unlocking || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

/// Measures a photo's export size the way Android does: patches of the photo, graded and encoded at the output scale,
/// give its bytes per pixel. JPEG is measured once at every quality on the curve, so moving the slider only reads it off.
@MainActor
final class PhotoSizeMeter: ObservableObject {
    struct Key: Equatable {
        let url: URL
        let width: Int
        let height: Int
        let grade: Grade
    }

    @Published private(set) var curve: [Double]?
    @Published private(set) var pngBytesPerPixel: Double?
    /// The photo could not be sampled, so the estimate falls back to the formula.
    @Published private(set) var failed = false
    private var key: Key?
    private var samples: [PixelImage] = []
    private var wantsPng = false
    private var task: Task<Void, Never>?
    private var pngTask: Task<Void, Never>?

    func measure(_ key: Key) {
        guard key != self.key else { return }
        self.key = key
        task?.cancel(); pngTask?.cancel()
        curve = nil; pngBytesPerPixel = nil; failed = false; samples = []
        task = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> ([PixelImage], [Double])? in
                guard let tiles = try? MediaIO.sizeSamples(key.url, outWidth: key.width, outHeight: key.height, grade: key.grade),
                      !tiles.isEmpty, !Task.isCancelled else { return nil }
                return (tiles, sizeCurveQualities.map { MediaIO.sampleBytesPerPixel(tiles, png: false, quality: $0) })
            }.value
            guard let self, !Task.isCancelled, self.key == key else { return }
            guard let result else { self.failed = true; return }
            self.samples = result.0
            self.curve = result.1
            if self.wantsPng { self.measurePng() }
        }
    }

    func setPng(_ png: Bool) {
        wantsPng = png
        if png { measurePng() }
    }

    private func measurePng() {
        guard pngBytesPerPixel == nil, !samples.isEmpty else { return }
        let tiles = samples, key = key
        pngTask?.cancel()
        pngTask = Task { [weak self] in
            let value = await Task.detached(priority: .userInitiated) { MediaIO.sampleBytesPerPixel(tiles, png: true, quality: 100) }.value
            guard let self, !Task.isCancelled, self.key == key else { return }
            self.pngBytesPerPixel = value
        }
    }
}

struct ExportDialog: View {
    let source: SourceMedia
    let grade: Grade
    let speed: Float
    let trim: MsRange
    let audio: AudioMix
    let selection: ExportSelection
    let onSelectionChange: (ExportSelection) -> Void
    let onResetCustom: () -> Void
    let onDismiss: () -> Void
    let export: (ExportOptions) -> Void

    @Environment(\.palette) private var c
    @Environment(\.strings) private var s
    @Environment(\.screenHeight) private var screenHeight
    @StateObject private var meter = PhotoSizeMeter()

    // Only a real cut is passed on, so an untrimmed export keeps the source's exact end.
    private var startMs: Int64 { trim.lowerBound }
    private var endMs: Int64 { trim.upperBound > 0 && trim.upperBound < source.durationMs ? trim.upperBound : 0 }
    private var lengthMs: Int64 { ExportOptions(startMs: startMs, endMs: endMs).trimmedMs(source.durationMs) }
    private var sourceFps: Float { source.fps * min(speed, 1) }
    private var customFps: Int { selection.fps == 0 || Float(selection.fps) <= sourceFps ? selection.fps : 0 }

    /// What Start export runs with: the chosen mode resolved for this media, with the speed and trim.
    private var options: ExportOptions {
        var resolved = source.video
            ? selection.videoOptions(width: source.width, height: source.height, fps: source.fps, outputFps: sourceFps,
                                     codec: source.codec, hdr: source.isHdr)
            : selection.photoOptions(width: source.width, height: source.height, pngSource: source.url.pathExtension.lowercased() == "png")
        resolved.speed = speed
        resolved.startMs = startMs
        resolved.endMs = endMs
        return resolved
    }

    private var dimensions: (Int, Int) {
        options.original ? (source.width, source.height)
            : ExportSizing.dimensions(source.width, source.height, options.longEdge, even: source.video)
    }

    private func change(_ edit: (inout ExportSelection) -> Void) {
        var next = selection
        edit(&next)
        onSelectionChange(next)
    }

    var body: some View {
        M3Dialog(title: s.text("Export your restoration", "匯出還原作品"), dismiss: onDismiss) {
            ScrollIfNeeded(maxHeight: screenHeight * 0.55) {
                VStack(alignment: .leading, spacing: 10) {
                    Choices(items: [(ExportMode.recommended, s.text("Recommended", "建議")), (.original, s.text("Original", "原始")),
                                    (.custom, s.text("Custom", "自訂"))], selected: selection.mode) { mode in change { $0.mode = mode } }
                    if source.isHdr {
                        MText("\(source.hdrName) · 10-bit · BT.2020\n" + s.text("HDR is preserved in every mode. Preview brightness depends on your display.", "所有模式均保留 HDR，預覽亮度取決於螢幕能力。"),
                              size: 12, color: c.primary)
                        if source.hdr == .pq {
                            MText(s.text("HDR10+ dynamic metadata, if present, is not preserved. The result keeps static HDR10 color.",
                                         "若來源包含 HDR10+ 動態中繼資料，匯出後不會保留；結果會維持靜態 HDR10 色彩。"),
                                  size: 12, color: c.onSurfaceVariant)
                        }
                    }
                    if source.video { MText(summary, size: 12) }
                    if source.video && audio.changesAudio { MText(audioSummary, size: 12) }
                    if selection.mode == .custom { customOptions } else { modeInfo }
                    if source.video { sizeEstimate } else { photoSizeEstimate }
                    MText(s.text("Saved to your Photos library. The original file is never overwritten.", "儲存至相簿，不覆蓋原始檔案。"),
                          size: 11, color: c.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear { measure() }
                .onChange(of: sizeKey) { _ in measure() }
                .onChange(of: options.png) { png in meter.setPng(png) }
            }
        } buttons: {
            M3TextButton(title: s.text("Cancel", "取消"), action: onDismiss)
            M3Button(title: s.text("Start export", "開始匯出")) { export(options) }
        }
    }

    private var summary: String {
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

    /// Recommended and Original: what the export will produce, and why.
    @ViewBuilder private var modeInfo: some View {
        let shownFps = options.fps == 0 ? sourceFps : min(sourceFps, Float(options.fps))
        MText("\(dimensions.0) × \(dimensions.1)" + (source.video ? " · \(Int(shownFps.rounded())) fps" : options.png ? " · PNG" : " · JPEG \(options.quality)%"),
              weight: .semibold)
        if selection.mode == .original && !source.video {
            Choices(items: [(false, "JPEG"), (true, "PNG")], selected: selection.png) { png in change { $0.png = png } }
        }
        if selection.mode == .recommended {
            MText(recommendedText, size: 12)
        } else {
            MText(source.video
                  ? s.text("Keeps source dimensions, frame times and codec (AVC or HEVC). Selected speed retimes frames and audio. Targets the source video bitrate, adjusted for speed; estimates it only when unavailable. Color correction requires re-encoding, so it is not bit-for-bit lossless.",
                           "保留原尺寸、影格時間與編碼格式（AVC 或 HEVC）。所選速度會調整影格及音訊時間。優先沿用來源影片位元率並依速度調整，缺少資料時才估算。色彩校正需要重新編碼，無法完全無損。")
                  : options.png ? s.text("Full source dimensions, saved as lossless PNG after color correction. Files are several times larger than JPEG. Metadata is not copied.",
                                         "保留原始尺寸，調色後儲存為無損 PNG。檔案比 JPEG 大數倍，不複製中繼資料。")
                  : s.text("Full source dimensions, saved as full-quality JPEG after color correction. Metadata is not copied.",
                           "保留原始尺寸，調色後儲存為最高畫質 JPEG，不複製中繼資料。"), size: 12)
        }
    }

    private var recommendedText: String {
        if options.original {
            return source.video
                ? s.text("This video is already within the suggested size and frame-rate limits, so source settings are kept.",
                         "影片的尺寸與幀率已在建議範圍內，因此保留原始設定。")
                : s.text("This photo is already within the suggested size range, so source settings are kept.",
                         "照片的尺寸已在建議範圍內，因此保留原始設定。")
        }
        if source.video {
            return s.text("Keeps lower source dimensions and frame rates; caps larger video at 1080p and 30 fps with a balanced bitrate.",
                          "保留較低的原始尺寸與幀率；較大的影片最多輸出 1080p、30 幀，並平衡位元率。")
        }
        return options.png
            ? s.text("Large PNG photos are resized while keeping their lossless format.", "高解析度 PNG 照片會縮小尺寸，同時保留無損格式。")
            : s.text("Large photos use a smaller, high-quality JPEG to balance detail and file size.", "高解析度照片使用較小的高畫質 JPEG，兼顧細節與檔案大小。")
    }

    // Sits at the end of the photo format row, or of the video frame-rate heading, to save a row.
    private var resetButton: some View {
        M3TextButton(title: s.text("Reset to defaults", "恢復預設值"), fontSize: 12, action: onResetCustom)
            .disabled(selection == ExportSelection(mode: .custom))
    }

    @ViewBuilder private var customOptions: some View {
        MText(s.text("Resolution · longest edge", "解析度 · 最長邊"), weight: .semibold)
        Choices(items: [(0, s.text("Source", "原尺寸")), (3840, "3840"), (2560, "2560"), (1920, "1920"), (1280, "1280"), (960, "960"), (640, "640")],
                selected: selection.longEdge) { edge in change { $0.longEdge = edge } }
        let size = ExportSizing.dimensions(source.width, source.height, selection.longEdge, even: source.video)
        MText("\(size.0) × \(size.1) px", size: 12, color: c.primary)
        if source.video {
            HStack {
                MText(s.text("Frame rate", "幀率"), weight: .semibold)
                Spacer()
                resetButton
            }
            Choices(items: [(0, s.text("Original", "原始"))] + [24, 25, 30, 50, 60].filter { Float($0) <= sourceFps }.map { ($0, "\($0) fps") },
                    selected: customFps) { fps in change { $0.fps = fps } }
            MText(s.text("Lower frame rates drop frames; no interpolation. Output is H.264 for SDR or 10-bit HEVC for HDR. Untouched AAC audio is kept; edited audio is encoded as AAC.",
                         "較低幀率會抽幀，不插幀。SDR 輸出為 H.264，HDR 為 10-bit HEVC。未編輯的 AAC 音訊會保留，已編輯的音訊會編碼為 AAC。"), size: 11)
        } else {
            HStack {
                Choices(items: [(false, "JPEG"), (true, "PNG")], selected: selection.png) { png in change { $0.png = png } }
                Spacer()
                resetButton
            }
        }
        if source.video || !selection.png {
            MText(s.text("Quality", "畫質") + " · \(selection.quality)%", weight: .semibold)
            M3Slider(value: Float(selection.quality), range: 10...100, onChange: { value in change { $0.quality = Int(value.rounded()) } },
                     accessibility: s.text("Quality", "畫質"))
            MText(source.video
                  ? s.text("Controls target bitrate; higher values create larger files. 100% at source resolution and frame rate matches Original.", "調整目標位元率，數值越高，檔案越大。原尺寸、原幀率配合 100% 等同「原始」。")
                  : s.text("JPEG compression quality.", "JPEG 壓縮畫質。"), size: 11)
        }
    }

    // MARK: Estimated size

    @ViewBuilder private var sizeEstimate: some View {
        let plan = videoExportPlan(width: source.width, height: source.height, fps: source.fps, sourceBitrate: source.bitrate,
                                   audioBitrate: source.audioBitrate, durationMs: source.durationMs, options: options,
                                   mixedAudio: audio.changesAudio)
        let size = plan.estimatedBytes.map { bytes in
            bytes >= 1_000_000_000 ? String(format: "%.2f GB", Double(bytes) / 1_000_000_000) : String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } ?? s.text("Unavailable", "無法估算")
        MText(s.text("Estimated file size", "預估檔案大小") + " · ≈ " + size, weight: .semibold, color: c.primary)
            .accessibilityIdentifier("estimatedSize")
        MText(s.text("Based on target bitrate, audio and duration. Actual size varies with the encoder and scene detail; this is not a size limit.",
                     "依目標位元率、音訊與時長估算；實際大小受編碼器及畫面複雜度影響，不是檔案大小上限。"), size: 11)
    }

    private var sizeKey: PhotoSizeMeter.Key { PhotoSizeMeter.Key(url: source.url, width: dimensions.0, height: dimensions.1, grade: grade) }

    private func measure() {
        guard !source.video else { return }
        meter.measure(sizeKey)
        meter.setPng(options.png)
    }

    /// Measured by encoding samples of the photo; the formula only stands in when it cannot be sampled.
    @ViewBuilder private var photoSizeEstimate: some View {
        let bytesPerPixel: Double? = options.png ? meter.pngBytesPerPixel : meter.curve.map { interpolateBytesPerPixel($0, options.quality) }
        let measured = bytesPerPixel.map { Int64((Double(dimensions.0) * Double(dimensions.1) * $0).rounded()) }
        let bytes = measured ?? (meter.failed ? photoEstimatedBytes(width: source.width, height: source.height, options: options) : nil)
        MText(s.text("Estimated file size", "預估檔案大小") + " · " + (bytes.map { "≈ " + batchSizeText($0) } ?? s.text("measuring…", "測量中…")),
              weight: .semibold, color: c.primary)
            .accessibilityIdentifier("estimatedSize")
        MText(meter.failed
              ? s.text("Based on resolution, format and quality. Actual size varies with image detail.", "依解析度、格式與畫質估算；實際大小會隨影像細節而變。")
              : s.text("Measured by encoding samples of this photo with these settings. Actual size may differ slightly.",
                       "以所選設定編碼此照片的取樣測得；實際大小可能略有差異。"), size: 11)
    }
}

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A photo or video chosen in the picker, copied into this app's own folder.
struct PickedFile: Transferable {
    let url: URL
    let folder: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { try PickedFile.copy($0.file) }
        FileRepresentation(importedContentType: .image) { try PickedFile.copy($0.file) }
    }
    private static func copy(_ file: URL) throws -> PickedFile {
        let (url, folder) = try EditorModel.adopt(file)
        return PickedFile(url: url, folder: folder)
    }
}

/// The Android `Editor` composable: the top app bar, then the home screen, the analysis screen, or the
/// pinned preview with the scrolling adjustments, plus the dialogs.
struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var exports = Exports.shared
    @ObservedObject private var devTools = DevTools.shared
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s
    @Environment(\.compact) private var compact

    @State private var settings = false
    @State private var showExport = false
    @State private var showProgress = false
    @State private var speedExpanded = false
    @State private var restoreExpanded = false
    @State private var trimExpanded = false
    @State private var audioExpanded = false
    @State private var confirmClose = false
    @State private var maximized = false
    @State private var showPicker = false
    @State private var showMusicPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var showBatchPicker = false
    @State private var batchVideos = false
    @State private var batchItems: [PhotosPickerItem] = []
    @State private var scrollToTop = 0

    private var export: ExportStatus { exports.status }
    private var busy: Bool { model.phase != nil || export.busy }
    private var hasEditor: Bool { model.source != nil && model.phase == nil }
    private var spacing: CGFloat { compact ? 4 : 12 }

    var body: some View {
        ZStack {
            (maximized ? Color.black : Color.clear).ignoresSafeArea()
            VStack(spacing: 0) {
                if !maximized { topBar }
                content
            }
            // Its own view, so it does not share a modifier slot with the single-item picker.
            .photosPicker(isPresented: $showBatchPicker, selection: $batchItems,
                          maxSelectionCount: batchVideos ? BatchLimits.videos : BatchLimits.photos, selectionBehavior: .ordered,
                          matching: batchVideos ? .videos : .images, preferredItemEncoding: .current)
            dialogs
        }
        .animation(.easeOut(duration: 0.15), value: dialogKey)
        .hideSystemBars(maximized)
        .photosPicker(isPresented: $showPicker, selection: $pickedItem, matching: .any(of: [.videos, .images]))
        .onChange(of: pickedItem) { item in
            guard let item else { return }
            pickedItem = nil
            model.importPicked(item)
        }
        .fileImporter(isPresented: $showMusicPicker, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let (copy, folder) = try EditorModel.adopt(url)
                model.addMusic(copy, folder: folder)
            } catch { model.error = "noAudio" }
        }
        // Full screen ends with the edit or a new analysis; a new source or phase scrolls back to the top.
        .onChange(of: model.source) { value in
            if value == nil || model.phase != nil { maximized = false }
            scrollToTop += 1
        }
        .onChange(of: model.phase) { value in
            if value != nil { maximized = false }
            scrollToTop += 1
        }
        .onChange(of: export.busy) { value in if value { showProgress = true } }
        .onChange(of: batchItems) { items in
            guard !items.isEmpty else { return }
            batchItems = []
            model.prepareBatch(items, videos: batchVideos, strings: s)
        }
        // Back from another app mid-batch: show the progress again, with its reminder to stay.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UIApplicationDidBecomeActiveNotification"))) { _ in
            if export.busy && export.batch != nil { showProgress = true }
        }
    }

    private func pickBatch(videos: Bool) {
        batchVideos = videos
        showBatchPicker = true
    }

    /// The batch's own reminder: iOS pauses the export whenever AquaRestore is not on screen.
    private var keepOpenText: String {
        s.text("Keep AquaRestore open and the screen on until the batch finishes. Leaving the app pauses it; it continues when you return.",
               "批次完成前請保持 AquaRestore 開啟並維持螢幕亮著。離開 App 會暫停批次，返回後才會繼續。")
    }

    private var dialogKey: String {
        "\(export.busy && showProgress)\(model.error ?? "")\(export.saved)\(export.error ?? "")\(export.stage)\(settings)\(confirmClose)\(showExport)\(model.batchDraft != nil)"
    }

    // While exporting, closing just leaves the editor: the export keeps its own copy of the file.
    private func requestClose() { if export.busy { model.closeMedia() } else { confirmClose = true } }

    // MARK: Top bar

    /// CenterAlignedTopAppBar: 64dp, transparent; the navigation icon in on-surface, actions in on-surface-variant.
    private var topBar: some View {
        TopAppBarLayout {
            HStack(spacing: 0) {
                // Editing actions live in the bar so the editor keeps the full height for preview and controls.
                if hasEditor {
                    M3IconButton(icon: .close, label: s.text("Close", "關閉"), color: c.onSurface, action: requestClose)
                }
            }
            HStack(spacing: 9) {
                AppLogo(size: 30)
                MText("AquaRestore", size: 22, weight: .bold, color: c.onSurface, maxLines: 1).textBase(.titleLarge)
            }
            HStack(spacing: 0) {
                if hasEditor {
                    M3IconButton(icon: .swapHoriz, label: s.text("Change media", "更換素材"), color: c.onSurfaceVariant) { showPicker = true }
                        .disabled(busy)
                    M3IconButton(icon: .fileDownload, label: s.text("Export", "匯出"), filled: true) { showExport = true }
                        .disabled(busy)
                }
                M3IconButton(icon: .settings, label: s.text("Settings", "設定"), color: c.onSurfaceVariant) { settings = true }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 64)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if hasEditor, let source = model.source {
            VStack(alignment: .leading, spacing: spacing) {
                PreviewView(model: model, exporting: export.busy, maximized: $maximized)
                    .frame(maxHeight: maximized ? .infinity : nil)
                if !maximized {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) { adjustments(source) }
                                .id("top")
                        }
                        .onChange(of: scrollToTop) { _ in proxy.scrollTo("top", anchor: .top) }
                    }
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier("adjustments")
                }
                exportPanel
                Spacer().frame(height: 8)
            }
            .padding(.horizontal, maximized ? 0 : 20)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: spacing) {
                        if model.phase == nil { welcome } else { analyzing }
                        exportPanel
                        Spacer().frame(height: 8)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("top")
                }
                .onChange(of: scrollToTop) { _ in proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    @ViewBuilder private var exportPanel: some View {
        if export.busy {
            Panel {
                MText(s[export.stage], weight: .semibold)
                if let batch = export.batch { MText(batch.progressText(s), maxLines: 2) }
                Progress(value: export.progress)
                if export.batch != nil {
                    MText(keepOpenText, size: 12, weight: .semibold, color: c.error)
                } else {
                    MText(s.text("Keep AquaRestore open until the export finishes. It pauses while the app is in the background.",
                                 "匯出完成前請保持 AquaRestore 開啟；App 在背景時匯出會暫停。"), size: 12)
                }
                M3TextButton(title: s.text("Cancel export", "取消匯出")) { exports.cancel() }
            }
        }
    }

    // MARK: Welcome / analyzing

    /// The Android `Welcome` items sit directly in the screen's column, so they share its spacing.
    @ViewBuilder private var welcome: some View {
        Spacer().frame(height: 16)
        MText(s.text("Your underwater studio", "你的水下影像工作室"), weight: .semibold, color: c.primary)
        MText(s.text("Bring the ocean’s\ntrue colors back.", "讓海底的真實色彩\n再次浮現。"), size: 36, weight: .bold, lineHeight: 43)
        MText(s.text("Less blue. More life. Intelligent color restoration for your underwater videos and photos.",
                     "找回被海水吸收的紅色，還原你的水下影片與照片。"), color: c.onSurfaceVariant, lineHeight: 23)
        OceanArt().frame(height: 230)
        M3Button(title: s.text("Import video or photo", "匯入影片或照片"), icon: .addPhotoAlternate, iconSize: 24, iconSpacing: 10,
                 height: 56, corner: 16, fontSize: 16, fullWidth: true) { showPicker = true }
            .disabled(busy)
        M3Button(title: s.text("Batch restore photos", "批次還原照片"), icon: .photoLibrary, iconSize: 24, iconSpacing: 10, style: .outlined,
                 height: 56, corner: 16, fontSize: 16, fullWidth: true) { pickBatch(videos: false) }
            .disabled(busy)
        MText(s.text("Up to \(BatchLimits.photos) photos · automatic restoration · keep the app open", "最多 \(BatchLimits.photos) 張照片 · 自動智慧還原 · 請保持 App 開啟"),
              size: 12, color: c.onSurfaceVariant)
        // Batch videos is a developer tool for now, as on Android: ten taps on the version in Settings.
        if devTools.enabled {
            M3Button(title: s.text("Batch restore videos", "批次還原影片"), icon: .videoLibrary, iconSize: 24, iconSpacing: 10, style: .outlined,
                     height: 56, corner: 16, fontSize: 16, fullWidth: true) { pickBatch(videos: true) }
                .disabled(busy)
            MText(s.text("Developer tools · up to \(BatchLimits.videos) videos · keep the app open", "開發者工具 · 最多 \(BatchLimits.videos) 段影片 · 請保持 App 開啟"),
                  size: 12, color: c.onSurfaceVariant)
        }
        Panel {
            FeatureRow(icon: .autoAwesome, text: s.text("Automatic color recommendations", "自動分析並推薦調色"))
            FeatureRow(icon: .tune, text: s.text("One slider. Your perfect balance.", "一條強度滑桿，調出自然效果"))
            FeatureRow(icon: .highQuality, text: s.text("Smooth preview · original-quality export", "流暢預覽 · 原始畫質匯出"))
        }
        MText(s.text("On-device processing. Your memories stay with you.", "所有處理都在裝置上完成，素材無需上傳。"),
              size: 12, color: c.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var analyzing: some View {
        Spacer().frame(height: 36)
        OceanArt().frame(height: 210)
        MText(s[model.phase ?? "analyzing"]).textBase(.titleLarge)
        MText(s.text("We sample colors across your media to recommend a restoration. Your original stays untouched.",
                     "正在分析素材色彩以推薦還原設定；原始檔案會完整保留。"), color: c.onSurfaceVariant)
        Progress(value: model.progress)
        M3Button(title: s.text("Cancel", "取消"), style: .outlined) { model.cancelImport() }
    }

    // MARK: Adjustments

    @ViewBuilder private func adjustments(_ source: SourceMedia) -> some View {
        let enabled = !export.busy
        if source.video {
            SpeedPanel(model: model, expanded: $speedExpanded, enabled: enabled)
            if source.durationMs > 0 {
                TrimPanel(model: model, player: model.player, duration: source.durationMs, expanded: $trimExpanded, enabled: enabled)
            }
            AudioPanel(model: model, expanded: $audioExpanded, enabled: enabled) { showMusicPicker = true }
        }
        if let result = model.analysis {
            RestorePanel(model: model, result: result, expanded: $restoreExpanded, enabled: enabled)
        }
        AdvancedPanel(model: model, enabled: enabled)
        Spacer().frame(height: 8)
    }

    // MARK: Dialogs

    @ViewBuilder private var dialogs: some View {
        if export.busy && showProgress {
            M3Dialog(title: s[export.stage], dismiss: { showProgress = false }) {
                VStack(alignment: .leading, spacing: 16) {
                    if let batch = export.batch { MText(batch.progressText(s), maxLines: 2) }
                    Progress(value: export.progress)
                    if export.batch != nil {
                        MText(keepOpenText, weight: .semibold, color: c.error)
                    } else {
                        MText(s.text("Processing the original file. Keep the app open until it finishes.", "正在處理原始檔案，請保持 App 開啟直到完成。"))
                    }
                }
            } buttons: {
                M3TextButton(title: s.text("Cancel export", "取消匯出")) { exports.cancel() }
                M3TextButton(title: s.text("Hide", "隱藏")) { showProgress = false }
            }
        }
        if let key = model.error {
            M3Dialog(title: s.text("Unable to continue", "無法完成操作"), dismiss: { model.error = nil }) {
                MText(s[key])
            } buttons: {
                M3TextButton(title: s.text("OK", "知道了")) { model.error = nil }
            }
        }
        if !export.busy && (export.saved || export.error != nil || export.stage == "cancelled" || export.batch != nil) {
            M3Dialog(title: export.error != nil ? s.text("Export failed", "匯出失敗") : s[export.stage], dismiss: { exports.dismissResult() }) {
                if let batch = export.batch {
                    ScrollIfNeeded(maxHeight: 320) {
                        VStack(alignment: .leading, spacing: 12) {
                            MText(batch.resultText(s))
                            ForEach(batch.failures.indices, id: \.self) { i in
                                MText("\(batch.failures[i].name)\n\(s[batch.failures[i].error])", size: 12)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    MText(export.error.map { s[$0] } ?? (export.saved
                        ? s.text("Find your restored media in Photos.", "還原作品已儲存至相簿。")
                        : s.text("No unfinished file was added to your Photos library.", "相簿不會留下未完成的檔案。")))
                }
            } buttons: {
                if export.saved {
                    M3TextButton(title: s.text("Open", "開啟")) { Platform.openPhotos(); exports.dismissResult() }
                }
                M3TextButton(title: s.text("Done", "完成")) { exports.dismissResult() }
            }
        }
        if settings { SettingsDialog(model: model) { settings = false } }
        if let draft = model.batchDraft {
            BatchExportDialog(draft: draft, onDismiss: { model.discardBatch() }) { selection in
                guard let prepared = model.takeBatch() else { return }
                exports.startBatch(BatchRequest(sources: prepared.sources, failures: prepared.failures, selection: selection,
                                                videos: prepared.videos, chinese: s.chinese, folders: prepared.folders))
            }
        }
        if confirmClose {
            M3Dialog(title: s.text("Discard this edit?", "放棄這次編輯？"), dismiss: { confirmClose = false }) {
                MText(s.text("Your color, trim and music settings will be lost. The original file is not changed.",
                             "調色、剪輯與音樂設定將不會保留，原始檔案不受影響。"))
            } buttons: {
                M3TextButton(title: s.text("Keep editing", "繼續編輯")) { confirmClose = false }
                M3TextButton(title: s.text("Discard", "放棄")) { confirmClose = false; model.closeMedia() }
            }
        }
        if showExport, let source = model.source {
            ExportDialog(source: source, speed: model.speed, trim: model.trim, audio: model.audioMix(), onDismiss: { showExport = false }) { options in
                showExport = false
                var chosen = options
                chosen.speed = model.speed
                exports.start(ExportRequest(source: source, grade: model.grade, options: chosen, chinese: s.chinese, audio: model.audioMix()))
            }
        }
    }
}

private struct FeatureRow: View {
    @Environment(\.palette) private var c
    let icon: MaterialIcon
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            MIcon(icon, size: 20, color: c.primary)
            MText(text, size: 13)
        }
    }
}

/// CenterAlignedTopAppBar's layout: the title is centred in the bar, but moved aside (and limited to the room
/// between them) so it never overlaps the navigation icon or the actions. Subviews: navigation, title, actions.
struct TopAppBarLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 64)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let nav = subviews[0].sizeThatFits(.unspecified)
        let actions = subviews[2].sizeThatFits(.unspecified)
        let room = max(bounds.width - nav.width - actions.width, 0)
        let title = subviews[1].sizeThatFits(ProposedViewSize(width: room, height: bounds.height))
        var x = (bounds.width - title.width) / 2
        if x < nav.width { x = nav.width }
        if x + title.width > bounds.width - actions.width { x = bounds.width - actions.width - title.width }
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.minX + x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: min(title.width, room), height: bounds.height))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
    }
}

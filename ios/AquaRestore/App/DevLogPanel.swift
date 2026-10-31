import SwiftUI

/// The Android `DevLogPanel`: this app's recent log, to read, copy, share or save when reporting a problem.
/// Nothing leaves the device unless the user shares it.
struct DevLogPanel: View {
    let dismiss: () -> Void
    @Environment(\.palette) private var c
    @Environment(\.strings) private var s
    @State private var log: String?
    @State private var notice: String?

    private var hasLines: Bool { log?.split(separator: "\n").contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MText(s.text("Developer logs", "開發者日誌"), size: 18, weight: .semibold, color: c.onSurface)
            MText("\(DevTools.version) · \(DevLog.machine) · \(ProcessInfo.processInfo.operatingSystemVersionString)",
                  size: 11, color: c.onSurfaceVariant)
            Spacer().frame(height: 8)
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(hasLines ? log ?? "" : log == nil ? s.text("Reading…", "讀取中…") : s.text("No log lines yet.", "尚無日誌。"))
                            .font(.system(size: 9, design: .monospaced))
                            .lineSpacing(2)
                            .foregroundColor(c.onSurface)
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding(8)
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .onChange(of: log) { _ in proxy.scrollTo("end", anchor: .bottomLeading) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(c.surfaceVariant))
            .accessibilityIdentifier("devLog")
            Spacer().frame(height: 8)
            if let notice { MText(notice, size: 12, color: c.primary) }
            FlowLayout(spacing: 4) {
                M3TextButton(title: s.text("Refresh", "重新整理")) { refresh() }
                M3TextButton(title: s.text("Clear", "清除")) { DevLog.clear(); refresh() }
                M3TextButton(title: s.text("Copy", "複製")) {
                    guard let log else { return }
                    Platform.copy(DevLog.shareable(log))
                    notice = s.text("Copied", "已複製")
                }
                .disabled(log == nil)
                ShareLink(item: DevLog.shareable(log ?? ""), subject: Text("AquaRestore log")) {
                    Text(s.text("Share", "分享")).sp(nil, nil, lineHeight: TypeScale.labelLarge.lineHeight)
                        .foregroundColor(log == nil ? c.disabledContent : c.primary)
                        .textBase(.labelLarge)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 58, minHeight: 48)
                }
                .disabled(log == nil)
                M3TextButton(title: s.text("Save", "儲存")) {
                    guard let log else { return }
                    Task { notice = await DevLog.save(log).map { s.text("Saved to \($0)", "已儲存至 \($0)") } ?? s.text("Could not save the log", "無法儲存日誌") }
                }
                .disabled(log == nil)
                M3TextButton(title: s.text("Close", "關閉"), action: dismiss)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c.surface.ignoresSafeArea())
        .task { refresh() }
    }

    private func refresh() {
        Task { log = await DevLog.read() }
    }
}

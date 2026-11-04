import Foundation

@MainActor
enum ComparisonWork {
    final class Entry {
        var expected = 2
        var accepted = false
        var rejected = false
        var done = false
        var assets: [ShareMedia] = []
        var task: Task<Void, Never>?
        var previewAssets: [ShareMedia] {
            let ordered = assets.sorted { $0.video && !$1.video }
            return !done && !ordered.contains(where: \.video) ? [] : ordered
        }
    }
    private final class Session {
        var entries: [Entry] = []
        var terminal: ExportStatus?
    }
    private static var session: Session?
    private static var previousWorker: Task<Void, Never>?
    static func reset() { dismiss(); session = Session() }
    static func dismiss() {
        let old = session; session = nil
        old?.entries.forEach { $0.task?.cancel(); ShareMediaMaker.remove($0.assets) }
        if !Exports.shared.status.busy { Platform.keepScreenAwake(false) }
    }
    static func submit(_ request: ExportRequest) -> Entry? {
        guard let owner = session, owner.entries.filter({ !$0.rejected }).count < 2 else { return nil }
        let entry = Entry(); entry.expected = request.source.video ? 1 : 2; owner.entries.append(entry)
        // A hard link keeps batch imports alive without copying a potentially large video.
        let url = ShareMediaMaker.root.appendingPathComponent("source-\(UUID().uuidString).\(request.source.url.pathExtension)")
        do {
            try FileManager.default.createDirectory(at: ShareMediaMaker.root, withIntermediateDirectories: true)
            try FileManager.default.linkItem(at: request.source.url, to: url)
        } catch { entry.done = true; return entry }
        var source = request.source; source.url = url
        let input = ExportRequest(source: source, grade: request.grade, options: request.options, chinese: request.chinese)
        let predecessor = previousWorker
        // A second full-size decoder beside the export can run a phone out of memory on heavy video, so that waits for
        // the export to succeed. A rejected or dismissed entry is cancelled.
        let heavy = source.video && !LivePreview.withinLimit(width: source.width, height: source.height, fps: source.fps)
        let task = Task {
            defer { try? FileManager.default.removeItem(at: url) }
            await predecessor?.value
            while heavy && !entry.accepted && !Task.isCancelled { try? await Task.sleep(nanoseconds: 200_000_000) }
            if !Task.isCancelled {
                entry.assets = await ShareMediaMaker.make(input, onAsset: { item in
                    Task { @MainActor in
                        if session !== owner || entry.rejected { ShareMediaMaker.remove([item]); return }
                        if !entry.done && !entry.assets.contains(where: { $0.id == item.id }) {
                            entry.assets.append(item)
                            refresh(owner)
                        }
                    }
                })
            }
            entry.done = true
            if session !== owner || entry.rejected { ShareMediaMaker.remove(entry.assets) }
            else { refresh(owner) }
        }
        entry.task = task; previousWorker = task
        return entry
    }
    static func accept(_ entry: Entry?) { entry?.accepted = true }
    static func reject(_ entry: Entry?) {
        entry?.rejected = true; entry?.task?.cancel()
        if let entry { ShareMediaMaker.remove(entry.assets) }
    }
    static func finish(_ terminal: ExportStatus) {
        guard let owner = session else { Exports.shared.status = terminal; return }
        owner.terminal = terminal; refresh(owner)
    }
    private static func refresh(_ owner: Session) {
        guard session === owner, var terminal = owner.terminal else { return }
        let entries = owner.entries.filter { $0.accepted && !$0.rejected }
        terminal.comparisons = entries.flatMap(\.previewAssets)
        terminal.comparisonsBusy = entries.contains { !$0.done }
        terminal.comparisonUnavailable = entries.contains { $0.done && $0.assets.count < $0.expected }
        Platform.keepScreenAwake(terminal.busy || terminal.comparisonsBusy)
        Exports.shared.status = terminal
    }
}

import Foundation
import UIKit

@MainActor
enum ComparisonWork {
    final class Entry {
        var accepted = false
        var rejected = false
        var done = false
        /// Left out on purpose, so the user does not wait for it. The result then shows only the saved export.
        var skipped = false
        /// It will not run during the export, so `accept` decides at once whether it runs afterwards.
        var postponed = false
        var clipMs: Int64 = 0
        /// The export's speed before the comparison started.
        var aloneSpeed: Double?
        var assets: [ShareMedia] = []
        var task: Task<Void, Never>?
        let load = ExportLoad()
        private var memoryWatch: NSObjectProtocol?
        init() {
            let load = self.load
            memoryWatch = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                 object: nil, queue: nil) { _ in load.memoryWarning() }
        }
        deinit { if let memoryWatch { NotificationCenter.default.removeObserver(memoryWatch) } }
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
        let entry = Entry(); owner.entries.append(entry)
        if request.source.video {
            entry.clipMs = SharingPlan.clip(Int64(Double(request.options.trimmedMs(request.source.durationMs)) / Double(request.options.speed))).length
        }
        // A hard link keeps batch imports alive without copying a potentially large video.
        let url = ShareMediaMaker.root.appendingPathComponent("source-\(UUID().uuidString).\(request.source.url.pathExtension)")
        do {
            try FileManager.default.createDirectory(at: ShareMediaMaker.root, withIntermediateDirectories: true)
            try FileManager.default.linkItem(at: request.source.url, to: url)
        } catch { entry.done = true; return entry }
        var source = request.source; source.url = url
        let input = ExportRequest(source: source, grade: request.grade, options: request.options, chinese: request.chinese)
        let predecessor = previousWorker
        let task = Task {
            defer { try? FileManager.default.removeItem(at: url) }
            await predecessor?.value
            if !Task.isCancelled {
                if input.source.video {
                    entry.assets = await video(input, entry)
                } else {
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
            }
            entry.done = true
            if session !== owner || entry.rejected { ShareMediaMaker.remove(entry.assets) }
            else { refresh(owner) }
        }
        entry.task = task; previousWorker = task
        return entry
    }

    private static func pressure(_ source: SourceMedia, _ load: ExportLoad, availableMemory: UInt64, pipelines: UInt64) -> ComparisonRoom.Pressure? {
        ComparisonRoom.pressure(width: source.width, height: source.height, hdr: source.isHdr, availableMemory: availableMemory,
                                pipelines: pipelines, memoryWarned: load.memoryWarned, thermal: ProcessInfo.processInfo.thermalState)
    }

    /// A video's comparison can take what its export needs, so this watches the running export before starting one. If the
    /// phone has room, the comparison runs alongside, and stops if that changes. If not, the export finishes alone, and
    /// the comparison follows only when it should add a few seconds at most. A rejected or dismissed entry is cancelled
    /// while it waits.
    private static func video(_ input: ExportRequest, _ entry: Entry) async -> [ShareMedia] {
        let load = entry.load
        var lowest = AppLog.availableMemory
        var pace = SpeedWatch()
        while !entry.accepted && !load.settled() && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
            lowest = min(lowest, AppLog.availableMemory)
            pace.add(load.reachedSeconds)
        }
        if Task.isCancelled { return [] }
        entry.aloneSpeed = pace.rate(over: 1)
        if let reason = pressure(input.source, load, availableMemory: lowest, pipelines: 2) {
            NSLog("AquaRestore: comparison not started during the export, because of \(reason.rawValue); lowest free memory \(lowest / 1_048_576) MB")
        } else {
            NSLog("AquaRestore: comparison starting; export alone at \(describe(entry.aloneSpeed)), lowest free memory \(lowest / 1_048_576) MB")
            switch await watched(input, entry) {
            case .made(let assets): return assets
            case .stoppedAfterExport: entry.skipped = true; return []
            case .stoppedDuringExport: break
            }
        }
        entry.postponed = true
        if entry.accepted { decideAfterExport(entry) }
        while !entry.accepted && !Task.isCancelled { try? await Task.sleep(nanoseconds: 100_000_000) }
        if Task.isCancelled || entry.skipped { return [] }
        NSLog("AquaRestore: comparison starting after the export: a \(entry.clipMs) ms clip")
        if case .made(let assets) = await watched(input, entry) { return assets }
        entry.skipped = true
        return []
    }

    private static func describe(_ speed: Double?) -> String { speed.map { String(format: "%.2fx", $0) } ?? "unknown speed" }

    /// Uses the export's speed before the comparison started if there was one, since running together will have slowed it.
    private static func decideAfterExport(_ entry: Entry) {
        let speed = [entry.load.speed, entry.aloneSpeed].compactMap { $0 }.max()
        if ComparisonRoom.worthMakingAfterExport(clipMs: entry.clipMs, exportSpeed: speed) { return }
        NSLog("AquaRestore: comparison skipped: a \(entry.clipMs) ms clip at \(describe(speed)) would add more than \(Int(ComparisonRoom.extraSeconds)) s")
        entry.skipped = true
    }

    private enum Outcome { case made([ShareMedia]), stoppedDuringExport, stoppedAfterExport }

    /// Makes the comparison while watching what it costs: the phone's room and the export's time while an export runs, then
    /// how long the user would wait for it once the saved export is on screen.
    private static func watched(_ input: ExportRequest, _ entry: Entry) async -> Outcome {
        let source = input.source, load = entry.load
        load.comparisonFraction = 0
        let maker = Task { await ShareMediaMaker.make(input, progress: { load.comparisonFraction = $0 }) }
        let watcher = Task<Outcome?, Never> { @MainActor in
            var started = Date()
            var exportPace = SpeedWatch(), comparisonPace = SpeedWatch()
            var exportOver: Date?
            var measuring: (at: Date, fraction: Double)?
            while !Task.isCancelled {
                let now = Date(), fraction = load.comparisonFraction
                if !AppActivity.active {
                    // Everything starts again when the app returns, so nothing measured so far still applies.
                    load.comparisonFraction = 0
                    started = now; exportPace = SpeedWatch(); comparisonPace = SpeedWatch(); exportOver = nil; measuring = nil
                } else if Exports.shared.status.busy {
                    exportPace.add(load.reachedSeconds, now: now)
                    if fraction > 0 { comparisonPace.add(fraction, now: now) }
                    var reason = pressure(source, load, availableMemory: AppLog.availableMemory, pipelines: 1)
                    if reason == nil, ComparisonRoom.cannotFinish(fraction: fraction, elapsed: now.timeIntervalSince(started)) { reason = .tooSlow }
                    if reason == nil, !entry.accepted, let alone = entry.aloneSpeed, let current = exportPace.rate(over: 3),
                       let rate = comparisonPace.rate(over: 3),
                       ComparisonRoom.costsTooMuch(exportRemaining: load.remainingSeconds, aloneSpeed: alone, currentSpeed: current,
                                                   comparisonRemaining: (1 - fraction) / max(rate, 0.0001)) {
                        NSLog("AquaRestore: comparison at \(Int(rate * 100))% per second with the export at \(describe(current))")
                        reason = .costsTooMuch
                    }
                    if let reason {
                        NSLog("AquaRestore: comparison stopped during the export, because of \(reason.rawValue), at \(Int(fraction * 100))%\(AppLog.memory)")
                        maker.cancel()
                        return .stoppedDuringExport
                    }
                } else {
                    let over = exportOver ?? now
                    exportOver = over
                    if measuring == nil && fraction > 0 { measuring = (now, fraction) }
                    if !ComparisonRoom.worthFinishing(fraction: fraction, from: measuring?.fraction ?? 0,
                                                      measured: measuring.map { now.timeIntervalSince($0.at) }, waited: now.timeIntervalSince(over)) {
                        NSLog("AquaRestore: comparison stopped after the export, at \(Int(fraction * 100))%, because waiting for it would take too long")
                        maker.cancel()
                        return .stoppedAfterExport
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            return nil
        }
        let assets = await withTaskCancellationHandler { await maker.value } onCancel: { maker.cancel() }
        watcher.cancel()
        // Finishing just as it was told to stop still leaves a usable result.
        if let stopped = await watcher.value, assets.isEmpty { return stopped }
        return .made(assets)
    }

    static func accept(_ entry: Entry?) {
        guard let entry else { return }
        entry.accepted = true
        if entry.postponed { decideAfterExport(entry) }
    }
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
        terminal.comparisonsBusy = entries.contains { !$0.done && !$0.skipped }
        Platform.keepScreenAwake(terminal.busy || terminal.comparisonsBusy)
        Exports.shared.status = terminal
    }
}

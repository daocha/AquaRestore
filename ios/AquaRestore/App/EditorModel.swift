import AVFoundation
import Combine
import PhotosUI
import SwiftUI

struct BatchDraft: Equatable {
    let videos: Bool
    let total: Int
    var prepared = 0
    var sources: [SourceMedia] = []
    var failures: [BatchFailure] = []
    var folders: [URL] = []
    var ready = false
}

@MainActor
final class EditorModel: ObservableObject {
    private let defaults = UserDefaults.standard
    @Published var language: String
    @Published var theme: String
    @Published var source: SourceMedia?
    @Published var analysis: Analysis?
    @Published var grade = Grade.neutral
    let gradeState = GradeState(.neutral)
    /// Set for videos: the player grades it live. Photos use the bitmaps below instead.
    @Published var previewURL: URL?
    @Published var previewOriginal: PixelImage?
    @Published var previewOriginalImage: CGImage?
    @Published var previewGraded: CGImage?
    @Published var phase: String?
    @Published var progress: Int?
    @Published var error: String?
    @Published var compare = false
    @Published var speed: Float = 1
    /// Video trim in source milliseconds. `trimming` is true while a handle is being dragged.
    @Published var trim: MsRange = 0...0
    @Published var trimming = false
    /// Ungraded thumbnails spread over the clip for the trim bar.
    @Published var filmstrip: [CGImage] = []
    /// Positions picked on the trim bar, with whether to play from there (a tap or a finished drag)
    /// or hold the frame (mid-drag). Events, so a quick tap is never lost.
    let scrub = PassthroughSubject<(Int64, Bool), Never>()
    /// Soundtrack: original-audio and music volumes, the music file, and where in the song the video starts.
    @Published var originalVolume: Float = 1
    @Published var music: MusicTrack?
    @Published var musicStartMs: Int64 = 0
    @Published var musicVolume: Float = 1
    @Published var musicEnvelope: [Float]?
    @Published var musicLoading = false
    /// Emitted after the song window moves: replay the video from the trim start to hear it.
    let audition = PassthroughSubject<Void, Never>()
    /// Photos or videos picked for a batch, being copied out of the Photos library for the export dialog.
    @Published var batchDraft: BatchDraft?

    lazy var player = PlayerController(model: self)
    var playbackPositionMs: Int64 = 0
    var playbackWanted = true

    private var pickTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var gradeTask: Task<Void, Never>?
    private var musicTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?
    private var backgroundTasks: [Task<Void, Never>] = []
    private var sourceFolder: URL?
    private var musicFolder: URL?
    private var exportStatusObserver: AnyCancellable?

    init() {
        language = defaults.string(forKey: "language") ?? "system"
        theme = defaults.string(forKey: "theme") ?? "system"
        // Only the current source is kept: anything a previous run left behind is dropped.
        try? FileManager.default.removeItem(at: Self.importRoot)
        exportStatusObserver = Exports.shared.$status.map(\.busy).removeDuplicates().sink { [weak self] busy in
            if !busy { self?.removeUnusedFolders() }
        }
    }

    nonisolated static var importRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("AquaRestoreImport", isDirectory: true) }

    func preference(_ key: String, _ value: String) {
        defaults.set(value, forKey: key)
        if key == "language" { language = value } else { theme = value }
    }

    // MARK: Import

    /// Copies a picked file into this app's own folder, which is removed when the edit is closed.
    nonisolated static func adopt(_ url: URL, name: String? = nil) throws -> (URL, URL) {
        let folder = importRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let target = folder.appendingPathComponent(name ?? url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: target)
            return (target, folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Copies the picked item out of the Photos library, then imports it. Copying can take a while for
    /// large or iCloud videos, so the analyzing screen (with Cancel) is shown from the start.
    func importPicked(_ item: PhotosPickerItem) {
        if Exports.shared.status.busy { return }
        pickTask?.cancel()
        phase = "analyzing"
        progress = nil
        pickTask = Task { [weak self] in
            let picked = try? await item.loadTransferable(type: PickedFile.self)
            guard let self, !Task.isCancelled else {
                if let picked { try? FileManager.default.removeItem(at: picked.folder) }
                return
            }
            guard let picked else {
                self.phase = nil
                self.error = "importFailed"
                return
            }
            self.importMedia(picked.url, folder: picked.folder)
        }
    }

    func importMedia(_ url: URL, folder: URL) {
        if Exports.shared.status.busy { try? FileManager.default.removeItem(at: folder); return }
        speed = 1
        trim = 0...0
        filmstrip = []
        removeMusic()
        originalVolume = 1
        playbackPositionMs = 0
        playbackWanted = true
        let previousImport = importTask
        previousImport?.cancel()
        gradeTask?.cancel()
        backgroundTasks.forEach { $0.cancel() }
        backgroundTasks = []
        player.unload()
        error = nil
        previewURL = nil
        previewOriginal = nil
        previewOriginalImage = nil
        previewGraded = nil
        source = nil
        analysis = nil
        setCompare(false)
        let oldFolder = sourceFolder
        sourceFolder = folder
        importTask = Task { [weak self] in
            await previousImport?.value
            guard let self else { return }
            if let oldFolder, oldFolder != folder { try? FileManager.default.removeItem(at: oldFolder) }
            do {
                try Task.checkCancellation()
                self.phase = "analyzing"
                self.progress = nil
                let media = try await MediaIO.inspect(url)
                try Task.checkCancellation()
                try MediaIO.requireHdrEncoder(media)
                let recommended = try await MediaIO.analyze(media)
                try Task.checkCancellation()
                self.trim = 0...media.durationMs
                self.source = media
                self.analysis = recommended
                self.setGrade(recommended.grade)
                if media.video {
                    // Play the original straight away; the grade is a live GPU effect, so no re-encode is needed.
                    self.previewURL = media.url
                    self.player.load(media)
                    // Thumbnails are built in the background and never hold up the editor.
                    self.backgroundTasks.append(Task { [weak self] in
                        do { self?.filmstrip = try await MediaIO.filmstrip(media.url, durationMs: media.durationMs, count: 10) }
                        catch { NSLog("AquaRestore: filmstrip unavailable: \(error)") }
                    })
                } else {
                    let bitmap = try await Task.detached { try MediaIO.bitmap(media.url, edge: 720) }.value
                    try Task.checkCancellation()
                    self.previewOriginalImage = bitmap.cgImage
                    self.previewOriginal = bitmap
                    self.setGrade(recommended.grade)
                }
            } catch is CancellationError {
            } catch {
                NSLog("AquaRestore: import failed: \(error)")
                self.source = nil
                self.analysis = nil
                self.error = (error as? MediaProblem)?.key ?? "importFailed"
            }
            if self.sourceFolder == folder {
                self.phase = nil
                self.progress = nil
                if self.source == nil && !Exports.shared.status.busy {
                    try? FileManager.default.removeItem(at: folder)
                    self.sourceFolder = nil
                }
            }
        }
    }

    // MARK: Batch

    /// Copies each picked item into this app's own folder, one at a time, and reads its size, so the dialog can
    /// estimate the batch. Items that cannot be copied or read are reported as failed with the rest.
    func prepareBatch(_ items: [PhotosPickerItem], videos: Bool, strings s: Strings) {
        if Exports.shared.status.busy || items.isEmpty { return }
        discardBatch()
        let picked = Array(items.prefix(videos ? BatchLimits.videos : BatchLimits.photos))
        batchDraft = BatchDraft(videos: videos, total: picked.count)
        batchTask = Task { [weak self] in
            for (index, item) in picked.enumerated() {
                let file = try? await item.loadTransferable(type: PickedFile.self)
                guard let self, !Task.isCancelled, self.batchDraft != nil else {
                    if let file { try? FileManager.default.removeItem(at: file.folder) }
                    return
                }
                let fallback = videos ? s.text("Video \(index + 1)", "影片 \(index + 1)") : s.text("Photo \(index + 1)", "照片 \(index + 1)")
                let unreadable = videos ? "videoUnreadable" : "photoUnreadable"
                if let file {
                    self.batchDraft?.folders.append(file.folder)
                    do {
                        let media = try await MediaIO.inspect(file.url)
                        if media.video != videos { throw MediaProblem(videos ? "batchVideosOnly" : "batchPhotosOnly") }
                        self.batchDraft?.sources.append(media)
                    } catch {
                        self.batchDraft?.failures.append(BatchFailure(name: file.url.lastPathComponent, error: (error as? MediaProblem)?.key ?? unreadable))
                    }
                } else {
                    self.batchDraft?.failures.append(BatchFailure(name: fallback, error: unreadable))
                }
                self.batchDraft?.prepared = index + 1
            }
            self?.batchDraft?.ready = true
        }
    }

    /// Closes the batch dialog and removes the copies.
    func discardBatch() {
        batchTask?.cancel()
        batchTask = nil
        batchDraft?.folders.forEach { try? FileManager.default.removeItem(at: $0) }
        batchDraft = nil
    }

    /// Hands the prepared batch to the export, which removes the copies when it ends.
    func takeBatch() -> BatchDraft? {
        guard let draft = batchDraft, draft.ready else { return nil }
        batchTask = nil
        batchDraft = nil
        return draft
    }

    // MARK: Music

    func addMusic(_ url: URL, folder: URL) {
        musicTask?.cancel()
        let oldFolder = musicFolder
        musicFolder = folder
        musicTask = Task { [weak self] in
            guard let self else { return }
            self.musicLoading = true
            do {
                let track = try await Soundtrack.inspect(url)
                try Task.checkCancellation()
                self.musicEnvelope = nil
                self.musicStartMs = 0
                self.music = track
                self.musicLoading = false
                if let oldFolder, oldFolder != folder { try? FileManager.default.removeItem(at: oldFolder) }
                do { self.musicEnvelope = try await Soundtrack.envelope(track) }
                catch is CancellationError { throw CancellationError() }
                catch { NSLog("AquaRestore: waveform unavailable: \(error)"); self.musicEnvelope = nil }
            } catch is CancellationError {
            } catch {
                NSLog("AquaRestore: music import failed: \(error)")
                try? FileManager.default.removeItem(at: folder)
                if self.musicFolder == folder { self.musicFolder = oldFolder }
                self.error = (error as? MediaProblem)?.key ?? "noAudio"
            }
            self.musicLoading = false
        }
    }

    func removeMusic() {
        musicTask?.cancel()
        music = nil
        musicEnvelope = nil
        musicStartMs = 0
        musicVolume = 1
        // An export request still reads this URL after the editor has been closed.
        removeUnusedFolders()
    }

    func audioMix() -> AudioMix { AudioMix(originalVolume: originalVolume, music: music, musicStartMs: musicStartMs, musicVolume: musicVolume) }

    func cancelImport() {
        pickTask?.cancel()
        let cancelled = importTask
        let cancelledFolder = sourceFolder
        cancelled?.cancel()
        source = nil
        analysis = nil
        phase = nil
        // Wait for analysis and bitmap decoding to release the copied source before deleting it.
        Task { [weak self] in
            await cancelled?.value
            guard let self, let cancelledFolder,
                  self.sourceFolder == cancelledFolder, self.source == nil,
                  !Exports.shared.status.busy else { return }
            try? FileManager.default.removeItem(at: cancelledFolder)
            self.sourceFolder = nil
        }
    }

    /// Leave the editor for the home screen, discarding the edit. A running export keeps its own copy.
    func closeMedia() {
        importTask?.cancel()
        gradeTask?.cancel()
        backgroundTasks.forEach { $0.cancel() }
        backgroundTasks = []
        player.unload()
        removeMusic()
        setCompare(false)
        source = nil
        analysis = nil
        previewURL = nil
        previewOriginal = nil
        previewOriginalImage = nil
        previewGraded = nil
        filmstrip = []
        trim = 0...0
        speed = 1
        originalVolume = 1
        playbackPositionMs = 0
        playbackWanted = true
        removeUnusedFolders()
    }

    private func removeUnusedFolders() {
        guard !Exports.shared.status.busy else { return }
        if source == nil, let folder = sourceFolder {
            try? FileManager.default.removeItem(at: folder)
            sourceFolder = nil
        }
        if music == nil, let folder = musicFolder {
            try? FileManager.default.removeItem(at: folder)
            musicFolder = nil
        }
    }

    // MARK: Grade

    func setGrade(_ value: Grade) {
        setCompare(false)
        grade = value
        gradeState.grade = value
        guard let original = previewOriginal else { return }
        if gradeTask != nil { return }
        gradeTask = Task { [weak self] in
            var rendered: Grade?
            // Finish each small preview, then consume the newest settings. Continuous dragging
            // must not indefinitely cancel/debounce every render before it can reach the screen.
            while let self, self.previewOriginal === original {
                let snapshot = self.grade
                if snapshot == rendered { break }
                let image = await Task.detached(priority: .userInitiated) { try? MediaIO.gradeBitmap(original, snapshot).cgImage }.value
                if self.previewOriginal !== original { break }
                self.previewGraded = image
                rendered = snapshot
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            self?.gradeTask = nil
        }
    }

    func setCompare(_ value: Bool) {
        if compare != value { compare = value }
        gradeState.compare = value
    }

    func reset() { if let result = analysis { setGrade(result.grade) } }
}

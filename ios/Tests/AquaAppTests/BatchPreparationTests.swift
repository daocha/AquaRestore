import XCTest
@testable import AquaRestore

final class BatchPreparationTests: XCTestCase {
    @MainActor
    func testDiscardedInspectionCannotChangeReplacementDraft() async throws {
        // Inspection may finish successfully or throw after cancellation; neither may update the next draft.
        for fails in [false, true] {
            let model = EditorModel()
            Exports.shared.status = ExportStatus()
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let oldFile = try pickedFile("old.mp4", root: root)
            let newFile = try pickedFile("new.mp4", root: root)
            let oldMedia = media(oldFile)
            let newMedia = media(newFile)
            let inspection = Suspended<SourceMedia>()
            let loading = Suspended<PickedFile?>()

            let oldTask = try XCTUnwrap(model.prepareBatch(["old"], videos: true, strings: Strings(chinese: false),
                load: { _ in oldFile }, inspect: { _ in try await inspection.wait() }))
            await inspection.waitUntilStarted()
            let newTask = try XCTUnwrap(model.prepareBatch(["new"], videos: true, strings: Strings(chinese: false),
                load: { _ in try await loading.wait() }, inspect: { _ in newMedia }))
            await loading.waitUntilStarted()
            let newID = model.batchDraft?.id

            inspection.resume(fails ? .failure(MediaProblem("unsupported")) : .success(oldMedia))
            await oldTask.value
            XCTAssertEqual(newID, model.batchDraft?.id)
            XCTAssertEqual(0, model.batchDraft?.prepared)
            XCTAssertEqual(false, model.batchDraft?.ready)
            XCTAssertTrue(model.batchDraft?.sources.isEmpty == true)
            XCTAssertTrue(model.batchDraft?.failures.isEmpty == true)
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.folder.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.folder.path))

            loading.resume(.success(newFile))
            await newTask.value
            XCTAssertEqual([newMedia], model.batchDraft?.sources)
            XCTAssertEqual(1, model.batchDraft?.prepared)
            XCTAssertEqual(true, model.batchDraft?.ready)
            model.discardBatch()
        }
    }

    @MainActor
    func testLateCopyIsRemovedWithoutChangingReplacementDraft() async throws {
        let model = EditorModel()
        Exports.shared.status = ExportStatus()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldFile = try pickedFile("old.mp4", root: root)
        let newFile = try pickedFile("new.mp4", root: root)
        let oldLoading = Suspended<PickedFile?>()
        let newLoading = Suspended<PickedFile?>()
        let oldTask = try XCTUnwrap(model.prepareBatch(["old"], videos: true, strings: Strings(chinese: false),
            load: { _ in try await oldLoading.wait() }, inspect: { _ in
                XCTFail("A discarded copy must not be inspected")
                return self.media(oldFile)
            }))
        await oldLoading.waitUntilStarted()
        let newTask = try XCTUnwrap(model.prepareBatch(["new"], videos: true, strings: Strings(chinese: false),
            load: { _ in try await newLoading.wait() }, inspect: { _ in self.media(newFile) }))
        await newLoading.waitUntilStarted()
        let newID = model.batchDraft?.id

        oldLoading.resume(.success(oldFile))
        await oldTask.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.folder.path))
        XCTAssertEqual(newID, model.batchDraft?.id)
        XCTAssertEqual(0, model.batchDraft?.prepared)
        XCTAssertEqual(false, model.batchDraft?.ready)
        XCTAssertTrue(model.batchDraft?.folders.isEmpty == true)

        newLoading.resume(.success(newFile))
        await newTask.value
        XCTAssertEqual([media(newFile)], model.batchDraft?.sources)
        XCTAssertEqual(true, model.batchDraft?.ready)
        model.discardBatch()
    }

    private func pickedFile(_ name: String, root: URL) throws -> PickedFile {
        let folder = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return PickedFile(url: folder.appendingPathComponent(name), folder: folder)
    }

    private func media(_ file: PickedFile) -> SourceMedia {
        SourceMedia(url: file.url, name: file.url.lastPathComponent, video: true, width: 640, height: 360)
    }
}

/// Deliberately ignores cancellation, like a file transfer or inspection that has already started.
@MainActor
private final class Suspended<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var started: CheckedContinuation<Void, Never>?

    func wait() async throws -> Value {
        try await withCheckedThrowingContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func resume(_ result: Result<Value, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class AppLogTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString)", isDirectory: true)
        AppLog.start(folder: folder)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func testLinesAreReadBack() {
        NSLog("AquaRestore: first")
        XCTAssertTrue(AppLog.read().contains("AquaRestore: first"))
    }

    func testAStrayPercentSignIsKeptAsWritten() {
        NSLog("AquaRestore: file 100%d %@.mp4")
        XCTAssertTrue(AppLog.read().contains("file 100%d %@.mp4"))
    }

    func testTheLastRunRemainsAfterRestartingOnlyUntilTheNextOne() {
        NSLog("AquaRestore: run one")
        AppLog.start(folder: folder)
        NSLog("AquaRestore: run two")
        XCTAssertTrue(AppLog.read().contains("run one") && AppLog.read().contains("run two"))
        AppLog.start(folder: folder)
        XCTAssertFalse(AppLog.read().contains("run one"))
        XCTAssertTrue(AppLog.read().contains("run two"))
    }

    func testClearStillLeavesLaterLinesReadable() {
        NSLog("AquaRestore: before")
        AppLog.clear()
        XCTAssertEqual("", AppLog.read())
        NSLog("AquaRestore: after")
        XCTAssertFalse(AppLog.read().contains("before"))
        XCTAssertTrue(AppLog.read().contains("after"))
    }

    func testProgressIsThrottledForEachExport() {
        let now = Date()
        AppLog.progress("export", percent: 1, now: now)
        AppLog.progress("export", percent: 2, now: now.addingTimeInterval(4))
        AppLog.progress("comparison", percent: 3, now: now.addingTimeInterval(4))
        AppLog.progress("export", percent: 4, now: now.addingTimeInterval(5))
        let text = AppLog.read()
        XCTAssertTrue(text.contains("export at 1%") && text.contains("comparison at 3%") && text.contains("export at 4%"))
        XCTAssertFalse(text.contains("export at 2%"))
    }
}

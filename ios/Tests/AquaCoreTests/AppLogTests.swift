import XCTest
// A test file sees both Foundation's NSLog and the app's, so it has to name the one it means.
#if canImport(AquaCore)
@testable import AquaCore
private func log(_ line: String) { AquaCore.NSLog(line) }
#else
@testable import AquaRestore
private func log(_ line: String) { AquaRestore.NSLog(line) }
#endif

final class AppLogTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString)", isDirectory: true)
        AppLog.enabled = true
        AppLog.start(folder: folder)
    }
    override func tearDown() {
        AppLog.enabled = false
        try? FileManager.default.removeItem(at: folder)
    }

    func testNothingIsKeptWhileDeveloperToolsAreOff() {
        AppLog.enabled = false
        log("AquaRestore: while off")
        AppLog.write("AquaRestore: written while off")
        AppLog.progress("export", percent: 1)
        XCTAssertEqual("", AppLog.read())
        AppLog.enabled = true
        log("AquaRestore: while on")
        XCTAssertTrue(AppLog.read().contains("while on"))
        XCTAssertFalse(AppLog.read().contains("while off"))
    }

    func testLinesAreReadBack() {
        log("AquaRestore: first")
        XCTAssertTrue(AppLog.read().contains("AquaRestore: first"))
    }

    func testAStrayPercentSignIsKeptAsWritten() {
        log("AquaRestore: file 100%d %@.mp4")
        XCTAssertTrue(AppLog.read().contains("file 100%d %@.mp4"))
    }

    func testTheLastRunRemainsAfterRestartingOnlyUntilTheNextOne() {
        log("AquaRestore: run one")
        AppLog.start(folder: folder)
        log("AquaRestore: run two")
        XCTAssertTrue(AppLog.read().contains("run one") && AppLog.read().contains("run two"))
        AppLog.start(folder: folder)
        XCTAssertFalse(AppLog.read().contains("run one"))
        XCTAssertTrue(AppLog.read().contains("run two"))
    }

    func testClearStillLeavesLaterLinesReadable() {
        log("AquaRestore: before")
        AppLog.clear()
        XCTAssertEqual("", AppLog.read())
        log("AquaRestore: after")
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

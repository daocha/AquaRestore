import XCTest
@testable import AquaRestore

final class ExportResumeTests: XCTestCase {
    @MainActor
    func testSceneReturnClearsPausedMessage() {
        defer { AppActivity.set(true) }
        let exports = Exports()
        exports.status = ExportStatus(busy: true, progress: 35)
        exports.activityChanged(false)
        XCTAssertEqual(exports.status.stage, "paused")
        XCTAssertFalse(AppActivity.active)

        exports.activityChanged(true)
        XCTAssertTrue(AppActivity.active)
        XCTAssertEqual(exports.status.stage, "restarting")
        XCTAssertEqual(exports.status.progress, 35)
        XCTAssertTrue(exports.status.busy)
    }

    @MainActor
    func testSceneReturnDoesNotChangeFinishedExport() {
        let exports = Exports()
        exports.status = ExportStatus(progress: 100, stage: "saved", saved: true)
        exports.activityChanged(false)
        exports.activityChanged(true)
        XCTAssertEqual(exports.status.stage, "saved")
        XCTAssertTrue(exports.status.saved)
    }
}

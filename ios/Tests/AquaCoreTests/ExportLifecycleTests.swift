import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class ExportLifecycleTests: XCTestCase {
    private struct RenderFailure: Error {}

    override func tearDown() {
        AppActivity.set(true)
        super.tearDown()
    }

    func testSuccessfulRenderIsNotRepeated() async throws {
        var attempts = 0
        let result = try await ForegroundExport.run(waiting: { XCTFail("No interruption") }) {
            attempts += 1
            return "rendered"
        }
        XCTAssertEqual(result, "rendered")
        XCTAssertEqual(attempts, 1)
    }

    func testBackgroundFailureAfterReturningRetriesCurrentItem() async throws {
        var attempts = 0
        let result = try await ForegroundExport.run(waiting: {}) {
            attempts += 1
            if attempts == 1 {
                AppActivity.set(false)
                AppActivity.set(true)
                throw RenderFailure()
            }
            return "rendered"
        }
        XCTAssertEqual(result, "rendered")
        XCTAssertEqual(attempts, 2)
    }

    func testInterruptedRenderIsDiscardedEvenIfItReportsSuccess() async throws {
        var attempts = 0
        let result = try await ForegroundExport.run(waiting: {}) {
            attempts += 1
            if attempts == 1 {
                AppActivity.set(false)
                AppActivity.set(true)
            }
            return attempts
        }
        XCTAssertEqual(result, 2)
    }

    func testDoesNotStartAnItemUntilForegrounded() async throws {
        AppActivity.set(false)
        var showedPause = false
        let result = try await ForegroundExport.run(waiting: {
            showedPause = true
            AppActivity.set(true)
        }) {
            XCTAssertTrue(showedPause)
            XCTAssertTrue(AppActivity.active)
            return "rendered"
        }
        XCTAssertEqual(result, "rendered")
    }

    func testRealFailureAfterRetryIsReported() async {
        var attempts = 0
        do {
            try await ForegroundExport.run(waiting: {}) {
                attempts += 1
                if attempts == 1 {
                    AppActivity.set(false)
                    AppActivity.set(true)
                }
                throw RenderFailure()
            }
            XCTFail("Expected the foreground failure")
        } catch {
            XCTAssertTrue(error is RenderFailure)
        }
        XCTAssertEqual(attempts, 2)
    }

    func testCancellationDuringPauseDoesNotRestart() async {
        AppActivity.set(false)
        let task = Task {
            try await ForegroundExport.run(waiting: {
                withUnsafeCurrentTask { $0?.cancel() }
            }) {
                XCTFail("Cancelled item must not run")
            }
        }
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCancellationErrorIsNotRetriedAfterInterruption() async {
        var attempts = 0
        do {
            try await ForegroundExport.run(waiting: {}) {
                attempts += 1
                AppActivity.set(false)
                AppActivity.set(true)
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(attempts, 1)
    }
}

import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class LivePreviewTests: XCTestCase {
    func testFastPlaybackWaitsLongerBeforeCountingAsStuck() {
        XCTAssertEqual(LivePreview.stallSeconds(speed: 0.5), 1.2)
        XCTAssertEqual(LivePreview.stallSeconds(speed: 1), 1.2)
        XCTAssertEqual(LivePreview.stallSeconds(speed: 2), 3)
        XCTAssertEqual(LivePreview.stallSeconds(speed: 4), 3)
    }

    func testAFailedPreviewStartsAgainAfterGrowingPauses() {
        let start = Date()
        var retry = PlaybackRetry()
        XCTAssertEqual(retry.nextDelay(now: start), 1)
        XCTAssertEqual(retry.nextDelay(now: start.addingTimeInterval(2)), 3)
        XCTAssertNil(retry.nextDelay(now: start.addingTimeInterval(6)))
        XCTAssertNil(retry.nextDelay(now: start.addingTimeInterval(20)))
        XCTAssertEqual(retry.nextDelay(now: start.addingTimeInterval(32)), 1)
    }

    func testUpTo4k60NeedsNoMeasuring() {
        XCTAssertTrue(LivePreview.withinLimit(width: 3840, height: 2160, fps: 60))
        XCTAssertTrue(LivePreview.withinLimit(width: 3840, height: 3360, fps: 30))
        XCTAssertFalse(LivePreview.withinLimit(width: 3840, height: 3360, fps: 60))
        XCTAssertFalse(LivePreview.withinLimit(width: 7680, height: 4320, fps: 30))
    }

    func testMeasuredSpeedChoosesHowThePreviewPlays() {
        XCTAssertEqual(.original, LivePreview.decide(fps: 60, measuredDecodeFps: 240))
        XCTAssertEqual(.original, LivePreview.decide(fps: 60, measuredDecodeFps: 72))
        XCTAssertEqual(.copy, LivePreview.decide(fps: 60, measuredDecodeFps: 71))
        XCTAssertEqual(.copy, LivePreview.decide(fps: 60, measuredDecodeFps: 20))
    }

    func testAnUnmeasuredVideoStillPlaysTheOriginal() {
        XCTAssertEqual(.original, LivePreview.decide(fps: 60, measuredDecodeFps: nil))
    }

    func testThePreviewGivesWayOnlyWhenTheExportWouldNotFit() {
        let mb: UInt64 = 1_048_576
        // An iPhone SE (3rd generation): 1059 and 1317 MB free when this export started with the preview open, which failed,
        // and 2062 MB free before the preview had started, the most it reports.
        XCTAssertTrue(LivePreview.previewYields(width: 2160, height: 3840, hdr: true, availableMemory: 1_059 * mb))
        XCTAssertTrue(LivePreview.previewYields(width: 2160, height: 3840, hdr: true, availableMemory: 1_317 * mb))
        XCTAssertTrue(LivePreview.previewYields(width: 2160, height: 3840, hdr: true, availableMemory: 2_062 * mb))
        XCTAssertFalse(LivePreview.previewYields(width: 2160, height: 3840, hdr: true, availableMemory: 3_000 * mb))
        XCTAssertFalse(LivePreview.previewYields(width: 2160, height: 3840, hdr: false, availableMemory: 1_317 * mb))
        XCTAssertFalse(LivePreview.previewYields(width: 1080, height: 1920, hdr: true, availableMemory: 1_317 * mb))
        XCTAssertTrue(LivePreview.previewYields(width: 1080, height: 1920, hdr: false, availableMemory: 0))
    }
}

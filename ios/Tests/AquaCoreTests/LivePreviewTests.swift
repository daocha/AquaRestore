import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class LivePreviewTests: XCTestCase {
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

    func testAComparisonWaitsOnlyForLargerFramesWithoutRoom() {
        let mb: UInt64 = 1_048_576
        XCTAssertFalse(LivePreview.comparisonWaits(width: 3840, height: 3360, availableMemory: 2_100 * mb))
        XCTAssertFalse(LivePreview.comparisonWaits(width: 3360, height: 3840, availableMemory: 0))
        XCTAssertTrue(LivePreview.comparisonWaits(width: 7680, height: 4320, availableMemory: 0))
        XCTAssertTrue(LivePreview.comparisonWaits(width: 7680, height: 4320, availableMemory: 3_000 * mb))
        XCTAssertFalse(LivePreview.comparisonWaits(width: 7680, height: 4320, availableMemory: 6_400 * mb))
        XCTAssertTrue(LivePreview.comparisonWaits(width: 3841, height: 1000, availableMemory: 2_499 * mb))
        XCTAssertFalse(LivePreview.comparisonWaits(width: 3841, height: 1000, availableMemory: 2_500 * mb))
    }
}

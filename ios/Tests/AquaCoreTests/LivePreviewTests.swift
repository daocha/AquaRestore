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
        XCTAssertEqual(.reduced, LivePreview.decide(fps: 60, measuredDecodeFps: 240))
        XCTAssertEqual(.reduced, LivePreview.decide(fps: 60, measuredDecodeFps: 72))
        XCTAssertEqual(.copy, LivePreview.decide(fps: 60, measuredDecodeFps: 71))
        XCTAssertEqual(.copy, LivePreview.decide(fps: 60, measuredDecodeFps: 20))
    }

    func testAnUnmeasuredVideoStillPlaysTheOriginalGradedSmaller() {
        XCTAssertEqual(.reduced, LivePreview.decide(fps: 60, measuredDecodeFps: nil))
    }
}

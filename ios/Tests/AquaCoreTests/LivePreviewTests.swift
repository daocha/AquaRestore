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
        XCTAssertEqual(.full, LivePreview.decide(fps: 60, measuredDecodeFps: 120, hasRoom: true))
        XCTAssertEqual(.reduced, LivePreview.decide(fps: 60, measuredDecodeFps: 119, hasRoom: true))
        XCTAssertEqual(.reduced, LivePreview.decide(fps: 60, measuredDecodeFps: 72, hasRoom: true))
        XCTAssertEqual(.copy, LivePreview.decide(fps: 60, measuredDecodeFps: 71, hasRoom: true))
        XCTAssertEqual(.copy, LivePreview.decide(fps: 60, measuredDecodeFps: 20, hasRoom: true))
    }

    func testWithoutMemoryAFastDecoderStillGradesSmaller() {
        XCTAssertEqual(.reduced, LivePreview.decide(fps: 60, measuredDecodeFps: 240, hasRoom: false))
        XCTAssertEqual(.reduced, LivePreview.decide(fps: 60, measuredDecodeFps: 72, hasRoom: false))
        XCTAssertEqual(.copy, LivePreview.decide(fps: 60, measuredDecodeFps: 71, hasRoom: false))
    }

    func testAnUnmeasuredVideoStillPlaysTheOriginalGradedSmaller() {
        XCTAssertEqual(.reduced, LivePreview.decide(fps: 60, measuredDecodeFps: nil, hasRoom: true))
    }

    func testRoomDependsOnFreeMemoryAndFrameSize() {
        let mb: UInt64 = 1_048_576
        // About the most a 4 GB iPhone offers an app, then what larger ones have free.
        XCTAssertFalse(LivePreview.hasRoom(width: 3840, height: 3360, availableMemory: 2_100 * mb))
        XCTAssertFalse(LivePreview.hasRoom(width: 3840, height: 3360, availableMemory: 2_499 * mb))
        XCTAssertTrue(LivePreview.hasRoom(width: 3840, height: 3360, availableMemory: 2_500 * mb))
        // A larger frame needs more than the minimum.
        XCTAssertFalse(LivePreview.hasRoom(width: 7680, height: 4320, availableMemory: 3_000 * mb))
        XCTAssertTrue(LivePreview.hasRoom(width: 7680, height: 4320, availableMemory: 6_400 * mb))
        // Where the system reports nothing.
        XCTAssertFalse(LivePreview.hasRoom(width: 3840, height: 2160, availableMemory: 0))
    }
}

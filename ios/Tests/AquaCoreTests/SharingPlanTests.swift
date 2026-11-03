import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class SharingPlanTests: XCTestCase {
    func testVideoBoundsAndNoUpscaling() {
        for (w, h, expectedW, expectedH) in [(3840,2160,1280,720), (2160,3840,720,1280),
                                           (2000,2000,720,720), (319,239,318,238), (4000,400,1280,128)] {
            let size = SharingPlan.videoSize(w, h)
            XCTAssertEqual(size.0, expectedW); XCTAssertEqual(size.1, expectedH)
        }
    }
    func testCenteredClipAndShortVideo() {
        let long = SharingPlan.clip(60_000)
        XCTAssertEqual(long.start, 27_000); XCTAssertEqual(long.length, 6_000)
        let short = SharingPlan.clip(3000)
        XCTAssertEqual(short.start, 0); XCTAssertEqual(short.length, 3000)
    }
    func testEitherThresholdQualifies() {
        XCTAssertFalse(SharingPlan.eligible(videos: 4, photos: 9))
        XCTAssertTrue(SharingPlan.eligible(videos: 5, photos: 0))
        XCTAssertTrue(SharingPlan.eligible(videos: 0, photos: 10))
    }
}

import XCTest
@testable import AquaCore

final class ExportSizeCurveTests: XCTestCase {
    private let curve = sizeCurveQualities.map { 0.1 + Double($0) / 100 }

    func testMeasuredQualitiesAreReadOffExactly() {
        for (i, quality) in sizeCurveQualities.enumerated() {
            XCTAssertEqual(interpolateBytesPerPixel(curve, quality), curve[i], accuracy: 1e-12)
        }
    }

    func testBetweenQualitiesIsInterpolatedInLogSpace() {
        // 72 lies between the measured 70 and 75.
        let low = curve[sizeCurveQualities.firstIndex(of: 70)!], high = curve[sizeCurveQualities.firstIndex(of: 75)!]
        let expected = exp(log(low) + (log(high) - log(low)) * 2.0 / 5.0)
        XCTAssertEqual(interpolateBytesPerPixel(curve, 72), expected, accuracy: 1e-12)
        XCTAssertGreaterThan(interpolateBytesPerPixel(curve, 72), low)
        XCTAssertLessThan(interpolateBytesPerPixel(curve, 72), high)
    }

    func testQualityOutsideTheCurveIsClamped() {
        XCTAssertEqual(interpolateBytesPerPixel(curve, 1), curve[0], accuracy: 1e-12)
        XCTAssertEqual(interpolateBytesPerPixel(curve, 150), curve[curve.count - 1], accuracy: 1e-12)
    }

    func testCustomFrameRateAboveTheOutputRateKeepsTheSourceTiming() {
        var selection = ExportSelection(mode: .custom)
        selection.fps = 60
        // A 2x speed-up leaves no frames to spare at 30 fps, so asking for 60 falls back to the source timing.
        XCTAssertEqual(selection.videoOptions(width: 1920, height: 1080, fps: 60, outputFps: 30, codec: "hvc1").fps, 0)
        XCTAssertEqual(selection.videoOptions(width: 1920, height: 1080, fps: 60, codec: "hvc1").fps, 60)
    }
}

import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

/// The contract the app relies on, whichever core is in use.
final class StubGradeTests: XCTestCase {
    func testZeroIntensityIsBitExact() {
        var off = Grade.blue; off.strength = 0
        XCTAssertEqual(0x8020_5f9f, ColorGrade.pixel(0x8020_5f9f, off))
    }
    func testNeutralGradeIsIdentity() {
        var neutral = Grade.neutral; neutral.strength = 1
        XCTAssertEqual(0xff20_5f9f, ColorGrade.pixel(0xff20_5f9f, neutral))
    }
    func testBlackFramesGetNoRecommendation() {
        XCTAssertEqual(0, AutoGrade.analyze([[UInt32](repeating: 0xff00_0000, count: 64)]).confidence)
    }
    func testBlueWaterGetsRedRecovery() {
        let analysis = AutoGrade.analyze([[UInt32](repeating: 0xff20_80c0, count: 64)])
        XCTAssertGreaterThan(analysis.grade.red, 0)
        XCTAssertEqual("blue", analysis.cast)
    }
}

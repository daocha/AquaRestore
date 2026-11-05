import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class ComparisonRoomTests: XCTestCase {
    private let mb: UInt64 = 1_048_576

    private func pressure(_ width: Int, _ height: Int, hdr: Bool, free: UInt64, pipelines: UInt64 = 2, warned: Bool = false,
                          thermal: ProcessInfo.ThermalState = .nominal) -> ComparisonRoom.Pressure? {
        ComparisonRoom.pressure(width: width, height: height, hdr: hdr, availableMemory: free * mb, pipelines: pipelines,
                                memoryWarned: warned, thermal: thermal)
    }

    func testRoomDependsOnTheVideoAndWhatIsFree() {
        XCTAssertEqual(.lowMemory, pressure(2160, 3840, hdr: true, free: 1_317))
        XCTAssertNil(pressure(2160, 3840, hdr: true, free: 1_500))
        XCTAssertNil(pressure(2160, 3840, hdr: false, free: 1_317))
        XCTAssertNil(pressure(3840, 3360, hdr: false, free: 1_317))
        XCTAssertNil(pressure(1080, 1920, hdr: false, free: 400))
        XCTAssertEqual(.lowMemory, pressure(1080, 1920, hdr: false, free: 0))
    }

    func testARunningComparisonOnlyNeedsItsMarginLeft() {
        XCTAssertNil(pressure(2160, 3840, hdr: true, free: 800, pipelines: 1))
        XCTAssertEqual(.lowMemory, pressure(2160, 3840, hdr: true, free: 354, pipelines: 1))
    }

    func testAMemoryWarningOrHeatLeavesNoRoomWhateverIsFree() {
        XCTAssertEqual(.memoryWarning, pressure(1080, 1920, hdr: false, free: 5_000, warned: true))
        XCTAssertEqual(.heat, pressure(1080, 1920, hdr: false, free: 5_000, thermal: .serious))
        XCTAssertEqual(.heat, pressure(1080, 1920, hdr: false, free: 5_000, thermal: .critical))
        XCTAssertNil(pressure(1080, 1920, hdr: false, free: 5_000, thermal: .fair))
    }

    func testAComparisonOffCourseForItsLimitIsSeenEarly() {
        XCTAssertFalse(ComparisonRoom.cannotFinish(fraction: 0, elapsed: 9))
        XCTAssertTrue(ComparisonRoom.cannotFinish(fraction: 0, elapsed: 10))
        XCTAssertTrue(ComparisonRoom.cannotFinish(fraction: 0.09, elapsed: 10))
        XCTAssertFalse(ComparisonRoom.cannotFinish(fraction: 0.2, elapsed: 10))
        // An iPhone SE (3rd generation) had made 41% of a 4K HDR comparison after 45 s.
        XCTAssertTrue(ComparisonRoom.cannotFinish(fraction: 0.41, elapsed: 45))
    }

    func testAPostponedComparisonIsMadeOnlyIfItAddsAFewSeconds() {
        XCTAssertFalse(ComparisonRoom.worthMakingAfterExport(clipMs: 10_000, exportSpeed: 1))
        XCTAssertFalse(ComparisonRoom.worthMakingAfterExport(clipMs: 10_000, exportSpeed: 3))
        XCTAssertTrue(ComparisonRoom.worthMakingAfterExport(clipMs: 10_000, exportSpeed: 4))
        XCTAssertTrue(ComparisonRoom.worthMakingAfterExport(clipMs: 2_000, exportSpeed: 1))
        XCTAssertFalse(ComparisonRoom.worthMakingAfterExport(clipMs: 2_000, exportSpeed: nil))
        XCTAssertFalse(ComparisonRoom.worthMakingAfterExport(clipMs: 2_000, exportSpeed: 0))
    }

    func testTheCostIsTheTimeAddedNotTheSlowdown() {
        func added(_ remaining: Double, alone: Double, current: Double, comparison: Double) -> Double {
            ComparisonRoom.addedSeconds(exportRemaining: remaining, aloneSpeed: alone, currentSpeed: current, comparisonRemaining: comparison)
        }
        // A fast phone slowed by half loses under two seconds, because the comparison is soon over.
        XCTAssertEqual(1.65, added(20, alone: 6, current: 3, comparison: 3.3), accuracy: 0.01)
        XCTAssertFalse(ComparisonRoom.costsTooMuch(exportRemaining: 20, aloneSpeed: 6, currentSpeed: 3, comparisonRemaining: 3.3))
        // An iPhone SE (3rd generation): the export fell from about real time to 0.22x, and the comparison would take 90 s.
        XCTAssertEqual(70.2, added(25, alone: 1, current: 0.22, comparison: 90), accuracy: 0.01)
        XCTAssertTrue(ComparisonRoom.costsTooMuch(exportRemaining: 25, aloneSpeed: 1, currentSpeed: 0.22, comparisonRemaining: 90))
        // No slowdown costs nothing while the comparison ends first.
        XCTAssertEqual(0, added(20, alone: 2, current: 2, comparison: 3), accuracy: 0.01)
        XCTAssertEqual(0, added(20, alone: 2, current: 5, comparison: 3), accuracy: 0.01)
        // Outlasting the export costs the wait for the rest, which goes faster once the export is done.
        XCTAssertEqual(4, added(2, alone: 2, current: 2, comparison: 5), accuracy: 0.01)
        XCTAssertEqual(3, added(4, alone: 4, current: 2, comparison: 6), accuracy: 0.01)
        // A stalled export counts as losing the whole of the comparison's time.
        XCTAssertTrue(ComparisonRoom.costsTooMuch(exportRemaining: 10, aloneSpeed: 1, currentSpeed: 0, comparisonRemaining: 20))
        // Saving, with nothing left to read, is not slowed.
        XCTAssertFalse(ComparisonRoom.costsTooMuch(exportRemaining: 0, aloneSpeed: 1, currentSpeed: 0, comparisonRemaining: 20))
        // Without a measured speed nothing is judged.
        XCTAssertFalse(ComparisonRoom.costsTooMuch(exportRemaining: 10, aloneSpeed: 0, currentSpeed: 0, comparisonRemaining: 20))
    }

    func testTheWaitAfterTheExportIsJudgedByItsOwnSpeed() {
        // Nothing measured yet, as when it has not read a frame: it has until the end of the allowance.
        XCTAssertTrue(ComparisonRoom.worthFinishing(fraction: 0, from: 0, measured: nil, waited: 0.5))
        XCTAssertTrue(ComparisonRoom.worthFinishing(fraction: 0, from: 0, measured: nil, waited: 4))
        XCTAssertFalse(ComparisonRoom.worthFinishing(fraction: 0, from: 0, measured: nil, waited: 4.1))
        XCTAssertTrue(ComparisonRoom.worthFinishing(fraction: 0.5, from: 0.5, measured: 0.5, waited: 0.5))
        // Going fast enough to finish in time.
        XCTAssertTrue(ComparisonRoom.worthFinishing(fraction: 0.8, from: 0.5, measured: 1, waited: 1))
        // Too far to go at this speed, which is seen after a second rather than at the end of the wait.
        XCTAssertFalse(ComparisonRoom.worthFinishing(fraction: 0.2, from: 0.1, measured: 1, waited: 1))
        XCTAssertFalse(ComparisonRoom.worthFinishing(fraction: 0.5, from: 0.5, measured: 1, waited: 1))
    }

    func testAnEstimatedSpeedUsesOnlyWhatHasBeenWatched() throws {
        var watch = SpeedWatch()
        let start = Date()
        XCTAssertNil(watch.rate(over: 1))
        watch.add(0, now: start)
        watch.add(1, now: start.addingTimeInterval(0.5))
        XCTAssertNil(watch.rate(over: 1))
        watch.add(4, now: start.addingTimeInterval(1))
        XCTAssertEqual(4, try XCTUnwrap(watch.rate(over: 1)), accuracy: 0.001)
        // Starts again from zero, as an interrupted export does.
        watch.add(0, now: start.addingTimeInterval(2))
        XCTAssertEqual(0, try XCTUnwrap(watch.rate(over: 1)), accuracy: 0.001)
        // Old samples go, so a slowdown shows.
        watch.add(100, now: start.addingTimeInterval(20))
        XCTAssertNil(watch.rate(over: 1))
    }

    func testTheLoadIsMeasuredFromTheLatestAttempt() {
        let load = ExportLoad(), start = Date()
        XCTAssertNil(load.speed)
        load.begin(total: 26, now: start)
        XCTAssertFalse(load.settled(now: start.addingTimeInterval(5)))
        load.frame(at: 0, now: start.addingTimeInterval(1))
        XCTAssertFalse(load.settled(now: start.addingTimeInterval(2)))
        XCTAssertTrue(load.settled(now: start.addingTimeInterval(2.5)))
        load.frame(at: 10, now: start.addingTimeInterval(5))
        XCTAssertEqual(2, load.speed)
        XCTAssertEqual(10, load.reachedSeconds)
        XCTAssertEqual(16, load.remainingSeconds)
        load.memoryWarning()
        load.begin(total: 26, now: start.addingTimeInterval(6))
        XCTAssertNil(load.speed)
        XCTAssertFalse(load.settled(now: start.addingTimeInterval(20)))
        XCTAssertTrue(load.memoryWarned)
    }
}

import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class MediaPipelineTests: XCTestCase {

    func testExportedNameUsesSourceStemAndOutputFormat() {
        XCTAssertEqual("AquaRestore_IMG_1234.jpg", exportFileName(sourceName: "IMG_1234.HEIC", extension: "jpg"))
        XCTAssertEqual("AquaRestore_dive.mp4", exportFileName(sourceName: "dive.mov", extension: "mp4"))
        XCTAssertEqual("AquaRestore_sea view.png", exportFileName(sourceName: "Pictures/sea view.jpeg", extension: "png"))
    }

    func testEqualRatePreservesEveryFrameDespiteMicrosecondRounding() {
        let cadence = FrameCadence(fps: 30)
        XCTAssertEqual(300, (0..<300).filter { cadence.accept(timeUs: Int64($0) * 1_000_000 / 30) }.count)
    }
    func testThirtyToTwentyFourDoesNotStayAtThirty() {
        let cadence = FrameCadence(fps: 24)
        let selected = (0..<300).map { Int64($0) * 1_000_000 / 30 }.filter { cadence.accept(timeUs: $0) }
        XCTAssertEqual(240, selected.count)
        XCTAssertTrue(zip(selected, selected.dropFirst()).allSatisfy { $0 < $1 })
    }
    func testFrameCappingResetsAndDoesNotDuplicateSparseFrames() {
        let cadence = FrameCadence(fps: 30)
        XCTAssertEqual(60, (0..<120).filter { cadence.accept(timeUs: Int64($0) * 1_000_000 / 60) }.count)
        cadence.reset()
        XCTAssertEqual(10, (0..<10).filter { cadence.accept(timeUs: Int64($0) * 100_000) }.count)
    }

    func testResizingPreservesPortraitAndNeverUpscales() {
        XCTAssert(ExportSizing.dimensions(2160, 3840, 1920, even: true) == (1080, 1920))
        XCTAssert(ExportSizing.dimensions(640, 480, 1920, even: true) == (640, 480))
        XCTAssert(ExportSizing.dimensions(4033, 3025, 0) == (4033, 3025))
    }
    func testPhotoSizeEstimateRespondsToFormatQualityAndResolution() {
        var full = ExportOptions(); full.quality = 90
        var small = full; small.original = false; small.longEdge = 1920
        XCTAssertLessThan(photoEstimatedBytes(width: 4032, height: 3024, options: small), photoEstimatedBytes(width: 4032, height: 3024, options: full))
        var low = full; low.quality = 50
        XCTAssertLessThan(photoEstimatedBytes(width: 4032, height: 3024, options: low), photoEstimatedBytes(width: 4032, height: 3024, options: full))
        var png = full; png.png = true
        XCTAssertGreaterThan(photoEstimatedBytes(width: 4032, height: 3024, options: png), photoEstimatedBytes(width: 4032, height: 3024, options: full))
    }
    func testOriginalUsesSourceRateEvenBelowHeuristicAndMinimum() {
        XCTAssertEqual(8_000_000, ExportSizing.bitrate(3840, 2160, 60, 100, 8_000_000, true))
        XCTAssertEqual(200_000, ExportSizing.bitrate(640, 360, 30, 100, 200_000, true))
        XCTAssertGreaterThan(ExportSizing.bitrate(1920, 1080, 30, 100, 0, true), 0)
    }
    func testSizeIncludesAudioDurationAndSpeedWithoutOriginalInflation() {
        func plan(_ o: ExportOptions, audio: Int = 128_000, duration: Int64 = 60_000) -> VideoExportPlan {
            videoExportPlan(width: 1920, height: 1080, fps: 30, sourceBitrate: 8_000_000, audioBitrate: audio, durationMs: duration, options: o)
        }
        let original = plan(ExportOptions())
        XCTAssertEqual(8_000_000, original.bitrate)
        XCTAssertEqual(61_569_600, original.estimatedBytes)
        XCTAssertLessThan(plan(ExportOptions(), audio: 0).estimatedBytes!, original.estimatedBytes!)
        XCTAssertNil(plan(ExportOptions(), duration: 0).estimatedBytes)
        var half = ExportOptions(); half.speed = 0.5
        let slow = plan(half, audio: 0)
        XCTAssertEqual(4_000_000, slow.bitrate)
        XCTAssertEqual(plan(ExportOptions(), audio: 0).estimatedBytes, slow.estimatedBytes)
        for speed: Float in [2, 4] {
            var o = ExportOptions(); o.speed = speed
            let fast = plan(o, audio: 0)
            XCTAssertEqual(8_000_000, fast.bitrate)
            XCTAssertEqual(Double(plan(ExportOptions(), audio: 0).estimatedBytes!) / Double(speed), Double(fast.estimatedBytes!), accuracy: 2)
        }
        var custom = ExportOptions(); custom.original = false
        var q10 = custom; q10.quality = 10
        var q100 = custom; q100.quality = 100
        XCTAssertLessThan(plan(q10).estimatedBytes!, plan(q100).estimatedBytes!)
        var small = custom; small.longEdge = 640
        XCTAssertLessThan(plan(small).estimatedBytes!, plan(custom).estimatedBytes!)
        var slowFps = custom; slowFps.fps = 24
        XCTAssertLessThan(plan(slowFps).estimatedBytes!, plan(custom).estimatedBytes!)
    }

    func testTrimShortensDurationAndSizeEstimate() {
        XCTAssertEqual(60_000, ExportOptions().trimmedMs(60_000))
        XCTAssertEqual(50_000, ExportOptions(startMs: 10_000).trimmedMs(60_000))
        XCTAssertEqual(20_000, ExportOptions(startMs: 10_000, endMs: 30_000).trimmedMs(60_000))
        XCTAssertEqual(0, ExportOptions(startMs: 70_000).trimmedMs(60_000))
        func bytes(_ o: ExportOptions) -> Int64 {
            videoExportPlan(width: 1920, height: 1080, fps: 30, sourceBitrate: 8_000_000, audioBitrate: 128_000, durationMs: 60_000, options: o).estimatedBytes!
        }
        XCTAssertEqual(Double(bytes(ExportOptions())) / 3, Double(bytes(ExportOptions(startMs: 10_000, endMs: 30_000))), accuracy: 2)
    }

    func testMusicWindowStaysInsideTheSongAndMatchesTheVideo() {
        XCTAssertEqual(30_000...40_000, musicWindow(songMs: 180_000, startMs: 30_000, outputMs: 10_000))
        XCTAssertEqual(0...10_000, musicWindow(songMs: 180_000, startMs: -500, outputMs: 10_000))
        XCTAssertEqual(170_000...180_000, musicWindow(songMs: 180_000, startMs: 175_000, outputMs: 10_000))
        XCTAssertEqual(0...8_000, musicWindow(songMs: 8_000, startMs: 3_000, outputMs: 20_000), "shorter song plays whole")
    }
    func testShortSongsRepeatToFillTheVideo() {
        XCTAssertEqual([30_000...40_000], musicPieces(window: 30_000...40_000, outputMs: 10_000))
        XCTAssertEqual([0...8_000, 0...8_000, 0...4_000], musicPieces(window: 0...8_000, outputMs: 20_000))
        XCTAssertEqual([0...8_000], musicPieces(window: 0...8_000, outputMs: 8_000))
        XCTAssertEqual([], musicPieces(window: 0...8_000, outputMs: 0))
    }
    func testMusicPositionFollowsOutputTimeAndLoopsShortSongs() {
        let window = musicWindow(songMs: 180_000, startMs: 30_000, outputMs: 10_000)
        XCTAssertEqual(30_000, musicPosition(songMs: 180_000, window: window, elapsedMs: 0))
        XCTAssertEqual(35_000, musicPosition(songMs: 180_000, window: window, elapsedMs: 5_000))
        XCTAssertNil(musicPosition(songMs: 180_000, window: window, elapsedMs: 10_000), "silent past the window")
        XCTAssertNil(musicPosition(songMs: 180_000, window: window, elapsedMs: -1))
        XCTAssertEqual(2_000, musicPosition(songMs: 8_000, window: musicWindow(songMs: 8_000, startMs: 0, outputMs: 20_000), elapsedMs: 10_000), "short song loops")
    }
    func testAudioMixReportsReencodingAndSizeEstimateAccountsForIt() {
        XCTAssertFalse(AudioMix().changesAudio)
        XCTAssertTrue(AudioMix(originalVolume: 0).changesAudio)
        func bytes(_ mixed: Bool) -> Int64 {
            videoExportPlan(width: 1920, height: 1080, fps: 30, sourceBitrate: 8_000_000, audioBitrate: 96_000, durationMs: 60_000, options: ExportOptions(), mixedAudio: mixed).estimatedBytes!
        }
        XCTAssertGreaterThan(bytes(true), bytes(false))
    }
    func testVolumeBoostClipsInsteadOfWrapping() {
        XCTAssertEqual([32_767, -32_768, 2_000, 0], [20_000, -20_000, 1_000, 0].map { Gain.apply(Int16($0), 2) })
        XCTAssertEqual(1, Gain.apply(Float(0.8), 2))
    }

    func testCustomAtSourceSizeAndFullQualityMatchesOriginal() {
        func plan(_ o: ExportOptions) -> VideoExportPlan {
            videoExportPlan(width: 3840, height: 3360, fps: 61, sourceBitrate: 124_000_000, audioBitrate: 192_000, durationMs: 43_200, options: o)
        }
        let original = plan(ExportOptions())
        func custom(edge: Int, fps: Int = 0, q: Int) -> ExportOptions { ExportOptions(original: false, longEdge: edge, fps: fps, quality: q) }
        let full = plan(custom(edge: 0, q: 100))
        XCTAssertEqual(original.bitrate, full.bitrate)
        XCTAssertEqual(original.estimatedBytes, full.estimatedBytes)
        XCTAssertEqual(original.bitrate, plan(custom(edge: 3840, q: 100)).bitrate)
        let smaller = plan(custom(edge: 1920, q: 100)).bitrate
        XCTAssertTrue(smaller < original.bitrate && smaller > original.bitrate / 4)
        XCTAssertLessThan(plan(custom(edge: 0, fps: 30, q: 100)).bitrate, original.bitrate)
        XCTAssertEqual(Double(original.bitrate) / 2, Double(plan(custom(edge: 0, q: 50)).bitrate), accuracy: 1)
        func small(_ q: Int) -> Int {
            videoExportPlan(width: 640, height: 360, fps: 30, sourceBitrate: 614_000, audioBitrate: 70_000, durationMs: 2_000,
                            options: ExportOptions(original: false, quality: q)).bitrate
        }
        XCTAssertLessThan(small(10), small(90))
    }
    func testOriginalBitrateNeverUndercutsSource() {
        XCTAssertGreaterThanOrEqual(ExportSizing.bitrate(1920, 1080, 30, 100, 80_000_000, true), 80_000_000)
        XCTAssertGreaterThan(ExportSizing.bitrate(1920, 1080, 30, 100, 0, false), ExportSizing.bitrate(1920, 1080, 30, 50, 0, false))
    }
    func testClockFormatsTenths() {
        XCTAssertEqual("0:00.0", clock(0))
        XCTAssertEqual("1:05.3", clock(65_300))
    }
}

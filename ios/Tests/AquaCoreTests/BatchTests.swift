import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class BatchTests: XCTestCase {
    func testLimitsKeepAForegroundBatchShort() {
        XCTAssertEqual(30, BatchLimits.photos)
        XCTAssertEqual(5, BatchLimits.videos)
    }

    func testRecommendedResolvesEachPhotosSizeAndFormat() {
        let selection = ExportSelection()
        let small = selection.photoOptions(width: 1200, height: 800, pngSource: false)
        XCTAssertTrue(small.original)
        XCTAssertFalse(small.png)
        XCTAssertEqual(95, small.quality)
        let large = selection.photoOptions(width: 6000, height: 4000, pngSource: true)
        XCTAssertFalse(large.original)
        XCTAssertEqual(2560, large.longEdge)
        XCTAssertTrue(large.png)
    }

    func testOriginalAndCustomPhotoOptions() {
        let original = ExportSelection(mode: .original, png: true).photoOptions(width: 6000, height: 4000, pngSource: false)
        XCTAssertTrue(original.original)
        XCTAssertTrue(original.png)
        XCTAssertEqual(ExportOptions.originalJpegQuality, original.quality)
        let custom = ExportSelection(mode: .custom, longEdge: 1920, quality: 72).photoOptions(width: 4000, height: 6000, pngSource: true)
        XCTAssertFalse(custom.original)
        XCTAssertFalse(custom.png)
        XCTAssertEqual(72, custom.quality)
        XCTAssertEqual(1, custom.speed)
        XCTAssertEqual(0, custom.startMs)
        XCTAssertEqual(0, custom.endMs)
    }

    func testRecommendedVideoCapsAt1080pAnd30Fps() {
        let phone = ExportSelection().videoOptions(width: 3840, height: 2160, fps: 60, codec: "hvc1")
        XCTAssertFalse(phone.original)
        XCTAssertEqual(1920, phone.longEdge)
        XCTAssertEqual(30, phone.fps)
        XCTAssertEqual(85, phone.quality)
        XCTAssertTrue(ExportSelection().videoOptions(width: 1280, height: 720, fps: 30, codec: "avc1").original)
        // Portrait: the short side is bounded by 1080 as well.
        XCTAssertEqual(1920, ExportSelection().videoOptions(width: 2160, height: 3840, fps: 30, codec: "avc1").longEdge)
    }

    func testRecommendedConvertsProResAndOtherCodecsWithoutChangingSmallClipsSizeOrTiming() {
        for codec in ["apcn", "apch", "jpeg", ""] {
            let options = ExportSelection().videoOptions(width: 1920, height: 1080, fps: 30, codec: codec)
            XCTAssertFalse(options.original)
            XCTAssertEqual(0, options.longEdge)
            XCTAssertEqual(0, options.fps)
            XCTAssertEqual(85, options.quality)
            let (width, height) = ExportSizing.dimensions(1920, 1080, options.longEdge)
            XCTAssertEqual(1920, width)
            XCTAssertEqual(1080, height)
        }
        // Choosing Original explicitly still requires a codec the MP4 exporter can preserve.
        XCTAssertTrue(ExportSelection(mode: .original).videoOptions(width: 1920, height: 1080, fps: 30, codec: "apcn").original)
        XCTAssertFalse(canPreserveVideoCodec("apcn", hdr: false))
    }

    func testRecommendedKeepsCompatibleCodecsAndChoosesHevcForHdrAvc() {
        for codec in ["avc1", "avc3", "hvc1", "hev1"] {
            XCTAssertTrue(ExportSelection().videoOptions(width: 1280, height: 720, fps: 30, codec: codec).original)
        }
        for codec in ["hvc1", "hev1"] {
            XCTAssertTrue(ExportSelection().videoOptions(width: 1280, height: 720, fps: 30, codec: codec, hdr: true).original)
        }
        XCTAssertFalse(ExportSelection().videoOptions(width: 1280, height: 720, fps: 30, codec: "avc1", hdr: true).original)
    }

    func testCustomVideoNeverRaisesTheFrameRate() {
        let custom = ExportSelection(mode: .custom, longEdge: 1280, fps: 60, quality: 70)
        XCTAssertEqual(0, custom.videoOptions(width: 1920, height: 1080, fps: 30, codec: "avc1").fps)
        XCTAssertEqual(60, custom.videoOptions(width: 1920, height: 1080, fps: 120, codec: "avc1").fps)
        XCTAssertEqual(70, custom.videoOptions(width: 1920, height: 1080, fps: 30, codec: "avc1").quality)
        XCTAssertTrue(ExportSelection(mode: .original).videoOptions(width: 3840, height: 2160, fps: 60, codec: "hvc1").original)
    }

    func testSpaceCountsTheVideoBeingCopiedTwice() {
        XCTAssertEqual(BatchLimits.spaceMargin, batchVideoSpace([]))
        XCTAssertEqual(100 + 300 + 300 + BatchLimits.spaceMargin, batchVideoSpace([100, 300]))
    }

    func testSizeAndDurationTexts() {
        XCTAssertEqual("512 KB", batchSizeText(512_000))
        XCTAssertEqual("3.5 MB", batchSizeText(3_500_000))
        XCTAssertEqual("1.25 GB", batchSizeText(1_250_000_000))
        XCTAssertEqual("1:05", batchDurationText(65_000))
        XCTAssertEqual("1:00:00", batchDurationText(3_600_000))
    }

    func testProgressAndResultTexts() {
        let s = Strings(chinese: false)
        var photos = BatchExportStatus(total: 3)
        photos.currentName = "a.jpg"
        XCTAssertEqual("Photo 1 of 3 · a.jpg", photos.progressText(s))
        photos.saved = 1
        photos.failures = [BatchFailure(name: "b.jpg", error: "photoUnreadable")]
        XCTAssertEqual("1 of 3 photos saved to your Photos library.\n1 failed.\n1 not processed. Completed photos are kept.", photos.resultText(s))
        var videos = BatchExportStatus(total: 2, videos: true)
        videos.saved = 2
        XCTAssertEqual("Video 2 of 2", videos.progressText(s))
        XCTAssertEqual("2 of 2 videos saved to your Photos library.", videos.resultText(s))
        XCTAssertEqual("已將 2／2 段影片儲存至相簿。", videos.resultText(Strings(chinese: true)))
    }
}

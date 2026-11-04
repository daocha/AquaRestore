import XCTest
import Foundation
import UIKit
import AVFoundation
@testable import AquaRestore

final class ShareMediaTests: XCTestCase {
    func testPhotoComparisonOrientationDurationAndResolution() async throws {
        for (width, height) in [(160,240), (240,160), (200,200), (800,80)] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let photo = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
                UIColor(red: 0.25, green: 0.45, blue: 0.65, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                UIColor(red: 0.8, green: 0.2, blue: 0.3, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("comparison-test-\(UUID().uuidString).png")
            try XCTUnwrap(photo.pngData()).write(to: url)
            let source = SourceMedia(url: url, name: url.lastPathComponent, video: false, width: width, height: height)
            let items = await ShareMediaMaker.make(ExportRequest(source: source, grade: .neutral, options: ExportOptions(), chinese: false))
            defer { ShareMediaMaker.remove(items); try? FileManager.default.removeItem(at: url) }
            XCTAssertEqual(items.count, 2)
            guard items.count == 2 else { continue }
            XCTAssertTrue(items[0].video); XCTAssertFalse(items[1].video)
            let collage = try XCTUnwrap(UIImage(contentsOfFile: items[1].url.path))
            if height > width { XCTAssertGreaterThanOrEqual(collage.size.width, collage.size.height) }
            else { XCTAssertGreaterThan(collage.size.height, collage.size.width) }
            let output = try await MediaIO.inspect(items[0].url)
            XCTAssertEqual(output.width, width); XCTAssertEqual(output.height, height)
            XCTAssertTrue(abs(output.durationMs - 6000) <= 50)
            let frames = AVAssetImageGenerator(asset: AVURLAsset(url: items[0].url))
            frames.appliesPreferredTrackTransform = true
            let firstFrame = try frames.copyCGImage(at: .zero, actualTime: nil)
            let first = try XCTUnwrap(PixelImage(firstFrame))
            let top = first.pixels[(first.height / 4) * first.width + first.width / 4]
            XCTAssertGreaterThan(Int((top >> 16) & 255), Int(top & 255) + 40)
            XCTAssertLessThanOrEqual(output.fps, 30.1)
        }
    }
    func testVideoComparisonUsesNativePipelineAndFinalTrim() async throws {
        AppActivity.set(true)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "audit-video", withExtension: "mp4"))
        let source = try await MediaIO.inspect(url)
        let start = source.durationMs / 4, end = source.durationMs * 3 / 4
        let options = ExportOptions(original: false, longEdge: 160, fps: 10, speed: 2, startMs: start, endMs: end)
        let began = Date()
        let items = await ShareMediaMaker.make(ExportRequest(source: source, grade: .neutral, options: options, chinese: false))
        Foundation.NSLog("AquaRestoreTest:sequential video comparison %.2f s", Date().timeIntervalSince(began))
        defer { ShareMediaMaker.remove(items) }
        XCTAssertEqual(items.count, 1)
        guard let item = items.first else { return }
        XCTAssertTrue(item.video)
        let output = try await MediaIO.inspect(item.url)
        let expected = SharingPlan.clip((end - start) / 2).length
        XCTAssertTrue(abs(output.durationMs - expected) <= 100)
        XCTAssertLessThanOrEqual(output.fps, 30.1)
        if source.fps >= 24 { XCTAssertGreaterThan(output.fps, 20) }
        let size = SharingPlan.videoSize(source.width, source.height)
        XCTAssertEqual(output.width, size.0); XCTAssertEqual(output.height, size.1)
    }

    func testFullLength720pComparisonTimingAndResolution() async throws {
        AppActivity.set(true)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "audit-video", withExtension: "mp4"))
        let asset = AVURLAsset(url: fixture)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let original = try XCTUnwrap(tracks.first)
        let segment = try await asset.load(.duration)
        let composition = AVMutableComposition()
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        for index in 0..<8 {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: segment), of: original,
                                      at: CMTimeMultiply(segment, multiplier: Int32(index)))
        }
        let natural = try await original.load(.naturalSize)
        let transform = try await original.load(.preferredTransform)
        let display = GradeInstruction.displaySize(natural, transform)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(GradeInstruction.normalized(transform, natural)
            .concatenating(CGAffineTransform(scaleX: 1920 / display.width, y: 1080 / display.height)), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.layerInstructions = [layer]
        let video = AVMutableVideoComposition()
        video.renderSize = CGSize(width: 1920, height: 1080)
        video.frameDuration = CMTime(value: 1, timescale: 30)
        video.instructions = [instruction]
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("comparison-1080p-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080))
        exporter.outputURL = sourceURL; exporter.outputFileType = .mp4; exporter.videoComposition = video
        await withCheckedContinuation { continuation in exporter.exportAsynchronously { continuation.resume() } }
        guard exporter.status == .completed else { throw exporter.error ?? MediaProblem("exportFailed") }
        let source = try await MediaIO.inspect(sourceURL)
        let options = ExportOptions(original: false, longEdge: 160, fps: 10)
        let began = Date()
        let items = await ShareMediaMaker.make(ExportRequest(source: source, grade: .neutral, options: options, chinese: false))
        let elapsed = Date().timeIntervalSince(began)
        defer { ShareMediaMaker.remove(items) }
        let item = try XCTUnwrap(items.first)
        let output = try await MediaIO.inspect(item.url)
        Foundation.NSLog("AquaRestoreTest:full comparison %lld ms at %dx%d %.1f fps generated in %.3f s", output.durationMs, output.width, output.height, output.fps, elapsed)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(output.width, 1280); XCTAssertEqual(output.height, 720)
        XCTAssertTrue(abs(output.durationMs - SharingPlan.clip(source.durationMs).length) <= 100)
        XCTAssertGreaterThan(output.fps, 29); XCTAssertLessThanOrEqual(output.fps, 30.1)
    }

}

import XCTest
import UIKit
import SwiftUI
import CoreImage
@testable import AquaRestore

final class ComparisonWorkTests: XCTestCase {
    @MainActor
    func testPrimaryResultDoesNotWaitAndSourceSurvivesBatchCleanup() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("comparison-source-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 240), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 240))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        defer { ComparisonWork.dismiss(); Exports.shared.status = ExportStatus(); try? FileManager.default.removeItem(at: url) }
        let source = SourceMedia(url: url, name: url.lastPathComponent, video: false, width: 160, height: 240)
        ComparisonWork.reset()
        let entry = try XCTUnwrap(ComparisonWork.submit(ExportRequest(source: source, grade: .neutral, options: ExportOptions(), chinese: false)))
        ComparisonWork.accept(entry)
        ComparisonWork.finish(ExportStatus(stage: "saved", saved: true))
        XCTAssertTrue(Exports.shared.status.saved)
        XCTAssertFalse(Exports.shared.status.busy)
        XCTAssertTrue(Exports.shared.status.comparisonsBusy)
        try FileManager.default.removeItem(at: url)
        await entry.task?.value
        XCTAssertFalse(Exports.shared.status.comparisonsBusy)
        XCTAssertEqual(Exports.shared.status.comparisons.count, 2)
        ComparisonWork.dismiss()
        XCTAssertTrue(entry.assets.allSatisfy { !FileManager.default.fileExists(atPath: $0.url.path) })
    }

    @MainActor
    func testASkippedComparisonIsNotReportedAsAFailure() throws {
        defer { ComparisonWork.dismiss(); Exports.shared.status = ExportStatus() }
        // A file that does not exist ends the work at once, leaving this test to say how.
        let source = SourceMedia(url: URL(fileURLWithPath: "/nonexistent/skipped.mp4"), name: "skipped.mp4", video: true, width: 160, height: 240)
        ComparisonWork.reset()
        let entry = try XCTUnwrap(ComparisonWork.submit(ExportRequest(source: source, grade: .neutral, options: ExportOptions(), chinese: false)))
        XCTAssertTrue(entry.done)
        entry.skipped = true
        ComparisonWork.accept(entry)
        ComparisonWork.finish(ExportStatus(stage: "saved", saved: true))
        XCTAssertTrue(Exports.shared.status.comparisonSkipped)
        XCTAssertFalse(Exports.shared.status.comparisonUnavailable)
        XCTAssertFalse(Exports.shared.status.comparisonsBusy)
    }

    @MainActor
    func testActionRowSizeDoesNotChangeWhileSaving() {
        func size(_ working: Bool) -> CGSize {
            let host = UIHostingController(rootView: ComparisonActions(working: working, download: {}, share: {}))
            return host.sizeThatFits(in: CGSize(width: 500, height: 100))
        }
        let idle = size(false), saving = size(true)
        XCTAssertEqual(idle.width, saving.width, accuracy: 0.5)
        XCTAssertEqual(idle.height, saving.height, accuracy: 0.5)
    }
    func testOriginalFrameTransformFitsRotatedSource() {
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 360))
        let rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        let instruction = GradeInstruction(timeRange: .zero, trackID: 1, state: GradeState(.neutral), hdr: .sdr,
                                           transform: rotation, naturalSize: CGSize(width: 640, height: 360))
        let image = ComparisonFrame.originalImage(source, instruction: instruction, size: CGSize(width: 180, height: 320))
        XCTAssertEqual(image.extent.minX, 0, accuracy: 0.01)
        XCTAssertEqual(image.extent.minY, 0, accuracy: 0.01)
        XCTAssertEqual(image.extent.width, 180, accuracy: 0.01)
        XCTAssertEqual(image.extent.height, 320, accuracy: 0.01)
    }

    @MainActor
    func testVideoCanBePreviewedBeforeCollageFinishes() {
        let entry = ComparisonWork.Entry()
        let movie = ShareMedia(url: URL(fileURLWithPath: "/tmp/reveal.mp4"), video: true)
        let collage = ShareMedia(url: URL(fileURLWithPath: "/tmp/collage.jpg"), video: false)
        entry.assets = [movie]
        XCTAssertFalse(entry.done)
        XCTAssertEqual(entry.previewAssets, [movie])
        entry.assets.append(collage)
        XCTAssertEqual(entry.previewAssets, [movie, collage])
        entry.assets = [collage]
        XCTAssertTrue(entry.previewAssets.isEmpty)
        entry.done = true
        XCTAssertEqual(entry.previewAssets, [collage])
    }

}

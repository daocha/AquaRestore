import XCTest
import UIKit
import SwiftUI
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
    func testActionRowSizeDoesNotChangeWhileSaving() {
        func size(_ working: Bool) -> CGSize {
            let host = UIHostingController(rootView: ComparisonActions(working: working, download: {}, share: {}))
            return host.sizeThatFits(in: CGSize(width: 500, height: 100))
        }
        let idle = size(false), saving = size(true)
        XCTAssertEqual(idle.width, saving.width, accuracy: 0.5)
        XCTAssertEqual(idle.height, saving.height, accuracy: 0.5)
    }
}

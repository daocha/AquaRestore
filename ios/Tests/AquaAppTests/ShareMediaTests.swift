import XCTest
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
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("comparison-test-\(UUID().uuidString).png")
            try XCTUnwrap(photo.pngData()).write(to: url)
            let source = SourceMedia(url: url, name: url.lastPathComponent, video: false, width: width, height: height)
            let items = await ShareMediaMaker.make(ExportRequest(source: source, grade: .neutral, options: ExportOptions(), chinese: false), restored: url)
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
        }
    }
}

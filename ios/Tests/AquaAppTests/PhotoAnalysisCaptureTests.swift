import XCTest
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
@testable import AquaRestore

final class PhotoAnalysisCaptureTests: XCTestCase {
    func testSavedPhotoMatchesAnalysisPixelsAndSourceIdentity() async throws {
        let stem = "photo-capture-\(UUID().uuidString)"
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem)-original.png")
        let folder = try DevFiles.folder("frames")
        let imageURL = folder.appendingPathComponent("\(stem)-photo-analysis.png")
        let infoURL = folder.appendingPathComponent("\(stem)-photo-source.txt")
        defer { for file in [sourceURL, imageURL, infoURL] { try? FileManager.default.removeItem(at: file) } }
        let pixels: [UInt32] = (0..<320*200).map { i in
            0xff000000 | UInt32(i % 256) << 16 | UInt32((i / 320) % 256) << 8 | 123
        }
        let image = try XCTUnwrap(PixelImage(width: 320, height: 200, pixels: pixels).cgImage)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(sourceURL as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try await MediaIO.inspect(sourceURL)
        let expected = try MediaIO.bitmap(sourceURL, edge: 192)
        let count = try await MediaIO.saveAnalysisFrames(source)
        XCTAssertEqual(count, 1)
        let savedSource = try XCTUnwrap(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        let savedImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(savedSource, 0, nil))
        let saved = try XCTUnwrap(PixelImage(savedImage))
        XCTAssertEqual(saved.width, expected.width)
        XCTAssertEqual(saved.height, expected.height)
        XCTAssertEqual(saved.pixels, expected.pixels)
        let bytes = try Data(contentsOf: sourceURL)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let info = try String(contentsOf: infoURL, encoding: .utf8)
        XCTAssertTrue(info.contains("name=\(sourceURL.lastPathComponent)\n"))
        XCTAssertTrue(info.contains("size=320x200\n"))
        XCTAssertTrue(info.contains("bytes=\(bytes.count)\n"))
        XCTAssertTrue(info.contains("sha256=\(hash)\n"))
    }
}

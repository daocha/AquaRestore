import XCTest
import CoreGraphics
@testable import AquaRestore

final class PixelImageTests: XCTestCase {
    private func source(_ pixels: [UInt32]) -> CGImage {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) } as CFData
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        return CGImage(width: pixels.count, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixels.count * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: info), provider: CGDataProvider(data: data)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func testDecodingExposesStraightAlphaColors() throws {
        let image = try XCTUnwrap(PixelImage(source([0x801a3366, 0x00000000, 0xff3168b3, 0xc0244890])))
        XCTAssertEqual(image.pixels, [0x803466cb, 0, 0xff3168b3, 0xc03060bf])
    }

    func testCGImagePremultipliesColorsAndPreservesAlpha() throws {
        let pixels: [UInt32] = [0x803466cb, 0, 0xff3168b3, 0xc03060bf]
        let cgImage = try XCTUnwrap(PixelImage(width: 4, height: 1, pixels: pixels).cgImage)
        let data = try XCTUnwrap(cgImage.dataProvider?.data) as Data
        let actual = data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        XCTAssertEqual(actual, [0x801a3366, 0, 0xff3168b3, 0xc0244890])
    }

    func testOpaquePixelsRoundTripWithoutChanges() throws {
        let pixels: [UInt32] = (0..<256).map { 0xff000000 | UInt32($0 << 16 | (255-$0) << 8 | $0/2) }
        let decoded = try XCTUnwrap(PixelImage(source(pixels)))
        XCTAssertEqual(decoded.pixels, pixels)
        let encoded = try XCTUnwrap(decoded.cgImage)
        XCTAssertEqual(try XCTUnwrap(PixelImage(encoded)).pixels, pixels)
    }
}

import Foundation
import CoreGraphics

/// Upright sRGB pixels in straight-alpha 0xAARRGGBB order.
final class PixelImage {
    let width: Int
    let height: Int
    let pixels: [UInt32]
    init(width: Int, height: Int, pixels: [UInt32]) { self.width = width; self.height = height; self.pixels = pixels }

    private static let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    convenience init?(_ image: CGImage) {
        let w = image.width, h = image.height
        var pixels = [UInt32](repeating: 0, count: w * h)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: PixelImage.space, bitmapInfo: PixelImage.bitmapInfo) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // Core Graphics draws premultiplied pixels; callers work with independent color and alpha.
        for i in pixels.indices {
            let p = pixels[i], a = (p >> 24) & 255
            if a == 0 { pixels[i] = 0 }
            else if a < 255 {
                func channel(_ shift: UInt32) -> UInt32 { min(255, (((p >> shift) & 255) * 255 + a / 2) / a) }
                pixels[i] = (a << 24) | (channel(16) << 16) | (channel(8) << 8) | channel(0)
            }
        }
        self.init(width: w, height: h, pixels: pixels)
    }

    var cgImage: CGImage? {
        var encoded = Data(count: pixels.count * MemoryLayout<UInt32>.stride)
        encoded.withUnsafeMutableBytes { bytes in
            let out = bytes.bindMemory(to: UInt32.self)
            for i in pixels.indices {
                let p = pixels[i], a = (p >> 24) & 255
                if a == 255 { out[i] = p; continue }
                func channel(_ shift: UInt32) -> UInt32 { (((p >> shift) & 255) * a + 127) / 255 }
                out[i] = (a << 24) | (channel(16) << 16) | (channel(8) << 8) | channel(0)
            }
        }
        let data = encoded as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: PixelImage.space, bitmapInfo: CGBitmapInfo(rawValue: PixelImage.bitmapInfo), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}


import Foundation

/// The public stand-in delegates analysis image decoding to the app's native fallback.
enum PhotoDecoder {
    static func decode(_ url: URL, edge: Int) throws -> PixelImage? { nil }
}

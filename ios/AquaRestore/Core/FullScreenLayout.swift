import CoreGraphics

/// The full-screen preview's geometry, as the Android `Preview` composable computes it: where the media sits above
/// the controls, and how pinch and pan move it.
enum FullScreenLayout {
    static let maxZoom: CGFloat = 5

    /// How far the media moves vertically so that it is centred in the space above the controls instead of in the
    /// whole screen, letting the controls (and the Adjust panel) cover as little of it as possible. Media as tall as
    /// the screen stays at the top.
    static func lift(width: CGFloat, height: CGFloat, controls: CGFloat, mediaWidth: Int, mediaHeight: Int) -> CGFloat {
        guard height > 0 else { return 0 }
        let fitted = mediaWidth > 0 && mediaHeight > 0 && width > 0
            ? min(height, width * CGFloat(mediaHeight) / CGFloat(mediaWidth))
            : height
        return max((height - controls - fitted) / 2, 0) - (height - fitted) / 2
    }

    /// The scale and pan after one pinch/pan event, keeping the point under the fingers where it was and the
    /// picture inside its bounds. `lift` moves the zoom centre with the media.
    static func transformed(scale: CGFloat, pan: CGPoint, size: CGSize, lift: CGFloat,
                            centroid: CGPoint, panBy: CGSize, zoom: CGFloat) -> (scale: CGFloat, pan: CGPoint) {
        let next = min(max(scale * zoom, 1), maxZoom)
        guard next > 1 else { return (next, .zero) }
        let ratio = next / scale
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + lift)
        let x = pan.x * ratio + (centroid.x - center.x) * (1 - ratio) + panBy.width
        let y = pan.y * ratio + (centroid.y - center.y) * (1 - ratio) + panBy.height
        let maxX = (next - 1) * size.width / 2
        let maxY = (next - 1) * size.height / 2
        return (next, CGPoint(x: min(max(x, -maxX), maxX), y: min(max(y, -maxY), maxY)))
    }
}

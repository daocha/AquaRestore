import XCTest
#if canImport(AquaCore)
@testable import AquaCore
#else
@testable import AquaRestore
#endif

final class FullScreenLayoutTests: XCTestCase {
    func testMediaIsCentredAboveTheControls() {
        // 400x800 screen, 400x300 media, 200 of controls: free space is 600, so the media's top is at 150 instead of 250.
        let lift = FullScreenLayout.lift(width: 400, height: 800, controls: 200, mediaWidth: 4000, mediaHeight: 3000)
        XCTAssertEqual(lift, -100, accuracy: 0.001)
    }

    func testMediaAsTallAsTheScreenStaysAtTheTop() {
        // A portrait 9:16 clip on a 400x800 screen is 711 high: it moves up only until it touches the top edge.
        XCTAssertEqual(FullScreenLayout.lift(width: 400, height: 800, controls: 200, mediaWidth: 1080, mediaHeight: 1920),
                       -(800 - 400.0 * 1920 / 1080) / 2, accuracy: 0.001)
        // Media that fills the whole height has nowhere to move.
        XCTAssertEqual(FullScreenLayout.lift(width: 400, height: 800, controls: 200, mediaWidth: 500, mediaHeight: 1000), 0, accuracy: 0.001)
        // Tall media that leaves a little room moves only as far as the top edge.
        let lift = FullScreenLayout.lift(width: 400, height: 800, controls: 200, mediaWidth: 1000, mediaHeight: 1800)
        XCTAssertEqual(lift, -(800 - 720) / 2, accuracy: 0.001)
    }

    func testUnknownSizeUsesTheWholeHeight() {
        XCTAssertEqual(FullScreenLayout.lift(width: 400, height: 800, controls: 100, mediaWidth: 0, mediaHeight: 0), 0, accuracy: 0.001)
        XCTAssertEqual(FullScreenLayout.lift(width: 0, height: 0, controls: 100, mediaWidth: 10, mediaHeight: 10), 0)
    }

    func testZoomIsLimitedAndResetsAtOne() {
        let size = CGSize(width: 400, height: 800)
        var state = (scale: CGFloat(1), pan: CGPoint.zero)
        state = FullScreenLayout.transformed(scale: state.scale, pan: state.pan, size: size, lift: 0,
                                          centroid: CGPoint(x: 200, y: 400), panBy: .zero, zoom: 10)
        XCTAssertEqual(state.scale, 5)
        state = FullScreenLayout.transformed(scale: state.scale, pan: state.pan, size: size, lift: 0,
                                          centroid: CGPoint(x: 200, y: 400), panBy: CGSize(width: 50, height: 0), zoom: 0.01)
        XCTAssertEqual(state.scale, 1)
        XCTAssertEqual(state.pan, .zero)
    }

    func testZoomKeepsThePointUnderTheFingers() {
        let size = CGSize(width: 400, height: 800)
        // Zooming 2x about the top-left corner moves the picture right and down by a full half size, which is the limit.
        let state = FullScreenLayout.transformed(scale: 1, pan: .zero, size: size, lift: 0,
                                              centroid: CGPoint(x: 0, y: 0), panBy: .zero, zoom: 2)
        XCTAssertEqual(state.pan.x, 200, accuracy: 0.001)
        XCTAssertEqual(state.pan.y, 400, accuracy: 0.001)
    }

    func testPanStaysInsideTheZoomedPicture() {
        let size = CGSize(width: 400, height: 800)
        let state = FullScreenLayout.transformed(scale: 2, pan: .zero, size: size, lift: 0,
                                              centroid: CGPoint(x: 200, y: 400), panBy: CGSize(width: 999, height: -999), zoom: 1)
        XCTAssertEqual(state.pan.x, 200, accuracy: 0.001)
        XCTAssertEqual(state.pan.y, -400, accuracy: 0.001)
    }
}

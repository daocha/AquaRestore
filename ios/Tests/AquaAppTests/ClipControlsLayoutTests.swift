import SwiftUI
import XCTest
@testable import AquaRestore

final class ClipControlsLayoutTests: XCTestCase {
    /// A row wider than its screen widens everything above it too, because a vertical ScrollView takes its content's width.
    @MainActor
    func testTrimmingDoesNotWidenTheRowOnASmallIPhone() {
        // An iPhone SE is 375 pt wide, less 20 pt each side.
        let width: CGFloat = 335
        let model = EditorModel()
        model.trim = 5000...60000
        for chinese in [false, true] {
            let row = VideoControls(model: model, player: model.player, ui: ClipUI(), duration: 60000, enabled: true)
                .environment(\.strings, Strings(chinese: chinese))
            let size = UIHostingController(rootView: row).sizeThatFits(in: CGSize(width: width, height: 100))
            XCTAssertEqual(size.width, width, accuracy: 0.5, "chinese: \(chinese)")
        }
    }
}

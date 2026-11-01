import XCTest

/// CI seeds the simulator with audit-exif.jpg and audit-video.mp4 before running this suite.
final class ImportMediaPickerTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard #available(iOS 17, *) else {
            throw XCTSkip("The embedded picker requires iOS 17; iOS 16 uses Apple's system sheet.")
        }
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-language", "en"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testTabsFilterRealPhotosAndVideos() {
        openPicker()
        let tabs = app.segmentedControls["importMediaTabs"]
        XCTAssertEqual(tabs.buttons.allElementsBoundByIndex.map(\.label), ["Library", "Videos", "Photos"])
        XCTAssertTrue(tabs.buttons["Library"].isSelected)
        XCTAssertTrue(asset("Photo").waitForExistence(timeout: 15), "Seed a photo with simctl addmedia before running.")
        XCTAssertTrue(asset("Video").waitForExistence(timeout: 15), "Seed a video with simctl addmedia before running.")

        tabs.buttons["Videos"].tap()
        XCTAssertTrue(tabs.buttons["Videos"].isSelected)
        XCTAssertTrue(asset("Video").waitForExistence(timeout: 15))
        assertDisappears(asset("Photo"))

        tabs.buttons["Photos"].tap()
        XCTAssertTrue(tabs.buttons["Photos"].isSelected)
        XCTAssertTrue(asset("Photo").waitForExistence(timeout: 15))
        assertDisappears(asset("Video"))

        tabs.buttons["Library"].tap()
        XCTAssertTrue(asset("Photo").waitForExistence(timeout: 15))
        XCTAssertTrue(asset("Video").waitForExistence(timeout: 15))
    }

    func testDismissAndReopenDefaultsToLibraryWithCompactHeader() {
        openPicker()
        let header = app.otherElements["importMediaHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(header.frame.height, 56, "Keep the fixed import header to one control row.")
        XCTAssertFalse(app.staticTexts["Choose video or photo"].exists)
        app.segmentedControls["importMediaTabs"].buttons["Photos"].tap()
        app.buttons["importMediaClose"].tap()
        assertDisappears(app.segmentedControls["importMediaTabs"])
        XCTAssertTrue(app.buttons["importMedia"].isHittable)

        openPicker()
        XCTAssertTrue(app.segmentedControls["importMediaTabs"].buttons["Library"].isSelected)
    }

    private func openPicker() {
        let button = app.buttons["importMedia"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        if !button.isHittable { app.swipeUp() }
        button.tap()
        XCTAssertTrue(app.segmentedControls["importMediaTabs"].waitForExistence(timeout: 10))
    }

    private func asset(_ type: String) -> XCUIElement {
        // Apple's remote picker exposes thumbnails with localized labels such as "Photo, ...".
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH[c] %@", type + ",")).firstMatch
    }

    private func assertDisappears(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, file: file, line: line)
    }
}

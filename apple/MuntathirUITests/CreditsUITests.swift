import XCTest

final class CreditsUITests: XCTestCase {
    @MainActor func testCreditsAreAbsentFromAppSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Settings"].tap()
        for _ in 0 ..< 5 { app.swipeUp() }
        XCTAssertFalse(app.buttons["sources-and-licenses"].exists)
        XCTAssertFalse(app.buttons["Sources and licenses"].exists)
    }
}

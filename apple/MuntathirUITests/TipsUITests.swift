import XCTest

final class TipsUITests: XCTestCase {
    @MainActor func testPrayerTipAppearsOnlyWhenEnabledForTests() {
        let app = XCUIApplication()
        let arguments = ["--ui-testing", "--ui-testing-mecca", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        let message = "Press and hold a prayer time to mute its alert. Optional times can also be hidden."
        app.launchArguments = arguments + ["--ui-testing-tips"]
        app.launch()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Choose a translation to read alongside Arabic."].exists)
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["prayer-fajr"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[message].exists)
    }
}

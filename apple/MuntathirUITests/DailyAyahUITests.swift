import XCTest

final class DailyAyahUITests: XCTestCase {
    @MainActor func testDailyAyahOpensImageShareSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let share = app.buttons["share-daily-ayah"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        for _ in 0 ..< 4 where !share.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["daily-ayah-translation"].exists)
        let card = XCTAttachment(screenshot: app.screenshot())
        card.name = "Daily ayah card"
        card.lifetime = .keepAlways
        add(card)
        share.tap()
        app.buttons["Share as image"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5))
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "Verse image share sheet"
        sheet.lifetime = .keepAlways
        add(sheet)
    }
}

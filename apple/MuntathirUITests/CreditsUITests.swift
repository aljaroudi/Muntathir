import XCTest

final class CreditsUITests: XCTestCase {
    @MainActor func testTranslationCreditUsesSystemLanguageName() throws {
        for language in ["en", "ar"] {
            let localeID = language == "ar" ? "ar_SA" : "en_US"
            let languageName = try XCTUnwrap(Locale(identifier: localeID).localizedString(forLanguageCode: "en"))
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", localeID]
            app.launch()
            app.buttons[language == "ar" ? "الإعدادات" : "Settings"].tap()
            let sources = app.buttons["sources-and-licenses"]
            for _ in 0 ..< 5 where !sources.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(sources.isHittable)
            sources.tap()
            let credit = app.descendants(matching: .any)["quran-translation-credit"]
            for _ in 0 ..< 8 where !credit.exists || !credit.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(credit.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[languageName].exists || credit.label.contains(languageName))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Ali Quli Qara’i").firstMatch.exists)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Translation credit \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}

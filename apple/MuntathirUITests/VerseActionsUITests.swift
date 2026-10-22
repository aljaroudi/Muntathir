import XCTest

final class VerseActionsUITests: XCTestCase {
    @MainActor private func launch(extra: [String] = [], arabic: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", arabic ? "(ar)" : "(en)", "-AppleLocale", arabic ? "ar_SA" : "en_US"] + extra
        app.launch()
        openQuran(app, arabic: arabic)
        return app
    }

    @MainActor private func openQuran(_ app: XCUIApplication, arabic: Bool = false) {
        app.buttons[arabic ? "الأدوات" : "Tools"].firstMatch.tap()
        app.buttons["holy-quran"].tap()
        XCTAssertTrue(app.buttons["quran-surah-1"].waitForExistence(timeout: 10))
    }

    @MainActor private func openFirstVerse(_ app: XCUIApplication) {
        app.buttons["quran-surah-1"].tap()
        XCTAssertTrue(app.buttons["verse-actions-1:1"].waitForExistence(timeout: 5))
    }

    @MainActor func testFavoritesAndNotesSurviveRelaunchAndOpenTheVerse() {
        let app = launch()
        openFirstVerse(app)
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["Favorite"].tap()
        XCTAssertTrue(app.images["verse-favorite-1:1"].waitForExistence(timeout: 5))
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["Add note"].tap()
        let editor = app.textViews["verse-note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("My private note")
        app.buttons["save-verse-note"].tap()
        XCTAssertTrue(app.images["verse-has-note-1:1"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["quran-notes"].tap()
        XCTAssertTrue(app.staticTexts["My private note"].waitForExistence(timeout: 5))
        app.buttons["saved-verse-1:1"].tap()
        XCTAssertTrue(app.buttons["verse-actions-1:1"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments += ["--ui-testing-preserve-state"]
        app.launch()
        openQuran(app)
        app.buttons["quran-favorites"].tap()
        XCTAssertTrue(app.buttons["saved-verse-1:1"].waitForExistence(timeout: 5))
        app.buttons["saved-verse-1:1"].tap()
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["Remove favorite"].tap()
        XCTAssertTrue(app.images["verse-has-note-1:1"].exists)
        XCTAssertFalse(app.images["verse-favorite-1:1"].exists)
    }

    @MainActor func testUnsavedEditsCanBeDiscardedAndNotesDeleted() {
        let app = launch()
        openFirstVerse(app)
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["Add note"].tap()
        let editor = app.textViews["verse-note-editor"]
        editor.tap()
        editor.typeText("Keep this")
        app.buttons["save-verse-note"].tap()
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["Edit note"].tap()
        editor.tap()
        editor.typeText(" discarded")
        app.buttons["Cancel"].tap()
        app.buttons["Discard changes"].tap()
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["Edit note"].tap()
        XCTAssertEqual(editor.value as? String, "Keep this")
        app.buttons["Delete note"].tap()
        app.sheets.buttons["Delete note"].tap()
        XCTAssertTrue(app.buttons["verse-actions-1:1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.images["verse-has-note-1:1"].exists)
    }

    @MainActor func testFailedSaveKeepsTheDraft() {
        let app = launch(extra: ["--ui-testing-quran-save-failure"])
        openFirstVerse(app)
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["Add note"].tap()
        let editor = app.textViews["verse-note-editor"]
        editor.tap()
        editor.typeText("Do not lose this draft")
        app.buttons["save-verse-note"].tap()
        XCTAssertTrue(app.alerts["Unable to save"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(editor.value as? String, "Do not lose this draft")
    }

    @MainActor func testArabicCopyAndImageActionsAreAccessible() {
        let app = launch(arabic: true)
        openFirstVerse(app)
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["نسخ النص"].tap()
        XCTAssertTrue(app.alerts["تم نسخ النص"].waitForExistence(timeout: 5))
        app.alerts.buttons.firstMatch.tap()
        app.buttons["verse-actions-1:1"].tap()
        XCTAssertTrue(app.buttons["مشاركة كصورة"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arabic verse actions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

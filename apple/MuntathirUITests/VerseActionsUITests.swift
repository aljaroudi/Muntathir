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

    @MainActor private func addHighlight(_ app: XCUIApplication, note: String = "My private note") {
        app.buttons["verse-actions-1:1"].tap()
        app.buttons["Highlight"].tap()
        app.buttons["highlight-add-note"].tap()
        let editor = app.textViews["highlight-note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["highlight-color-green"].tap()
        editor.tap()
        editor.typeText(note)
        app.buttons["save-highlight"].tap()
    }

    @MainActor private func editHighlight(_ app: XCUIApplication) {
        app.buttons["verse-actions-1:1"].tap()
        let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit highlight")).firstMatch
        if !edit.waitForExistence(timeout: 5) {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Missing highlight action"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        edit.tap()
    }

    @MainActor func testHighlightsSurviveRelaunchAndOpenTheVerse() {
        let app = launch()
        openFirstVerse(app)
        addHighlight(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["quran-highlights"].tap()
        XCTAssertTrue(app.staticTexts["My private note"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quran highlights list"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["saved-verse-1:1"].swipeLeft()
        app.buttons["Edit highlight"].tap()
        XCTAssertEqual(app.staticTexts["highlight-note-preview"].label, "My private note")
        XCTAssertFalse(app.staticTexts["Edit note"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["highlight-note-preview"].waitForNonExistence(timeout: 5))
        app.buttons["saved-verse-1:1"].tap()
        XCTAssertTrue(app.buttons["verse-actions-1:1"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments += ["--ui-testing-preserve-state"]
        app.launch()
        openQuran(app)
        app.buttons["quran-highlights"].tap()
        XCTAssertTrue(app.buttons["saved-verse-1:1"].waitForExistence(timeout: 5))
        app.buttons["saved-verse-1:1"].tap()
        editHighlight(app)
        XCTAssertEqual(app.staticTexts["highlight-note-preview"].label, "My private note")
    }

    @MainActor func testUnsavedEditsCanBeDiscardedAndHighlightsDeleted() {
        let app = launch()
        openFirstVerse(app)
        addHighlight(app, note: "Keep this")
        editHighlight(app)
        app.buttons["highlight-add-note"].tap()
        let editor = app.textViews["highlight-note-editor"]
        editor.tap()
        editor.typeText(" discarded")
        app.buttons["Cancel"].tap()
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        editHighlight(app)
        XCTAssertEqual(app.staticTexts["highlight-note-preview"].label, "Keep this")
        app.buttons["Delete highlight"].tap()
        app.sheets.buttons["Delete highlight"].tap()
        XCTAssertTrue(app.buttons["verse-actions-1:1"].waitForExistence(timeout: 5))
        app.buttons["verse-actions-1:1"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit highlight")).firstMatch.exists)
    }

    @MainActor func testFailedSaveKeepsTheDraft() {
        let app = launch(extra: ["--ui-testing-quran-save-failure"])
        openFirstVerse(app)
        addHighlight(app, note: "Do not lose this draft")
        XCTAssertTrue(app.alerts["Unable to save"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.textViews["highlight-note-editor"].value as? String, "Do not lose this draft")
    }

    @MainActor func testPartialHighlightUsesNativeSelectionAndCanBeEdited() {
        let app = launch()
        openFirstVerse(app)
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["English"].tap()
        let text = app.textViews["quran-translation-1:1"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.press(forDuration: 1.2)
        let highlight = app.menuItems["Highlight"]
        XCTAssertTrue(highlight.waitForExistence(timeout: 5))
        highlight.tap()
        XCTAssertTrue(app.buttons["highlight-color-blue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["highlight-note-editor"].exists)
        XCTAssertFalse(app.buttons["save-highlight"].exists)
        XCTAssertFalse(app.staticTexts["Blue"].exists)
        app.buttons["highlight-color-blue"].tap()
        let reader = XCTAttachment(screenshot: app.screenshot())
        reader.name = "Persistent partial highlight"
        reader.lifetime = .keepAlways
        add(reader)
        editHighlight(app)
        XCTAssertTrue(app.buttons["highlight-color-blue"].isSelected)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Partial highlight editor"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testTappingHighlightShowsNoteWithoutLeavingReader() {
        let app = launch()
        openFirstVerse(app)
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["English"].tap()
        addHighlight(app, note: "Read this here")
        let text = app.textViews["quran-translation-1:1"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.25)).tap()
        let note = app.staticTexts["highlight-note-preview"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.label, "Read this here")
        XCTAssertFalse(app.textViews["highlight-note-editor"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quick note preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["verse-actions-1:1"].isHittable)
    }

    @MainActor func testOverlappingHighlightsOfferTheirNotesInPlace() {
        let app = launch()
        openFirstVerse(app)
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["English"].tap()
        addHighlight(app, note: "First note")
        addHighlight(app, note: "Second note")
        app.textViews["quran-translation-1:1"].coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.25)).tap()
        XCTAssertTrue(app.buttons["First note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Second note"].exists)
        app.buttons["First note"].tap()
        XCTAssertTrue(app.staticTexts["highlight-note-preview"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["highlight-note-preview"].label, "First note")
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
    }
}

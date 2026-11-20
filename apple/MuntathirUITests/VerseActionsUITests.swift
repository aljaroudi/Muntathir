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

    @MainActor private func firstTranslationWord(_ app: XCUIApplication) -> XCUICoordinate {
        let text = app.textViews["quran-translation-1:1"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        return text.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.25))
    }

    @MainActor private func openHighlightPicker(_ app: XCUIApplication) {
        if !app.textViews["quran-translation-1:1"].exists {
            app.buttons["quran-reading-options"].tap()
            app.buttons["quran-translation-picker"].tap()
            app.buttons["English"].tap()
        }
        firstTranslationWord(app).press(forDuration: 1.2)
        XCTAssertTrue(app.menuItems["Highlight"].waitForExistence(timeout: 5))
        app.menuItems["Highlight"].tap()
    }

    @MainActor private func addHighlight(_ app: XCUIApplication, note: String = "My private note") {
        openHighlightPicker(app)
        let green = app.buttons["highlight-color-green"]
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        green.tap()
        XCTAssertTrue(green.waitForNonExistence(timeout: 5))
        editHighlight(app)
        let editor = app.textViews["highlight-note-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(note)
        green.tap()
        XCTAssertTrue(green.waitForNonExistence(timeout: 5))
    }

    @MainActor private func dismissHighlightSheet(_ app: XCUIApplication) {
        let grabber = app.buttons["Sheet Grabber"]
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertTrue(grabber.waitForNonExistence(timeout: 5))
    }

    @MainActor private func editHighlight(_ app: XCUIApplication) {
        firstTranslationWord(app).tap()
        XCTAssertTrue(app.buttons["Delete highlight"].waitForExistence(timeout: 5))
    }

    @MainActor func testHighlightsSurviveRelaunchAndOpenTheVerse() {
        let app = launch()
        openFirstVerse(app)
        addHighlight(app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["quran-saved"].tap()
        XCTAssertTrue(app.staticTexts["My private note"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("missing-note\n")
        XCTAssertTrue(app.buttons["saved-verse-1:1"].waitForNonExistence(timeout: 5))
        search.buttons["Clear text"].tap()
        search.typeText("private\n")
        XCTAssertTrue(app.buttons["saved-verse-1:1"].waitForExistence(timeout: 5))
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
        } else {
            app.buttons["Cancel"].tap()
        }
        app.buttons["saved-grouping"].tap()
        app.buttons["Group by Date"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quran highlights list"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["saved-verse-1:1"].swipeLeft()
        app.buttons["Edit highlight"].tap()
        XCTAssertEqual(app.textViews["highlight-note-editor"].value as? String, "My private note")
        XCTAssertFalse(app.staticTexts["Edit note"].exists)
        app.buttons["highlight-color-blue"].tap()
        XCTAssertTrue(app.textViews["highlight-note-editor"].waitForNonExistence(timeout: 5))
        app.buttons["saved-verse-1:1"].tap()
        XCTAssertTrue(app.buttons["verse-actions-1:1"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments += ["--ui-testing-preserve-state"]
        app.launch()
        openQuran(app)
        app.buttons["quran-saved"].tap()
        XCTAssertTrue(app.buttons["saved-verse-1:1"].waitForExistence(timeout: 5))
        app.buttons["saved-verse-1:1"].tap()
        editHighlight(app)
        XCTAssertEqual(app.textViews["highlight-note-editor"].value as? String, "My private note")
        XCTAssertTrue(app.buttons["highlight-color-blue"].isSelected)
    }

    @MainActor func testNotesEditDirectlyAndHighlightsCanBeDeleted() {
        let app = launch()
        openFirstVerse(app)
        addHighlight(app, note: "Keep this")
        editHighlight(app)
        let editor = app.textViews["highlight-note-editor"]
        editor.tap()
        editor.typeText(" updated")
        let editedNote = editor.value as? String
        XCTAssertTrue(editedNote?.contains("updated") == true)
        XCTAssertTrue(editedNote?.contains("Keep this") == true)
        dismissHighlightSheet(app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        editHighlight(app)
        XCTAssertEqual(app.textViews["highlight-note-editor"].value as? String, editedNote)
        if editedNote != nil {
            editor.tap()
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText(XCUIKeyboardKey.delete.rawValue)
            dismissHighlightSheet(app)
            editHighlight(app)
            XCTAssertFalse((editor.value as? String ?? "").contains("Keep this"))
        }
        app.buttons["Delete highlight"].tap()
        app.sheets.buttons["Delete highlight"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        firstTranslationWord(app).press(forDuration: 1.2)
        XCTAssertTrue(app.menuItems["Highlight"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit highlight")).firstMatch.exists)
    }

    @MainActor func testFailedSaveKeepsTheDraft() {
        let app = launch(extra: ["--ui-testing-quran-save-failure"])
        openFirstVerse(app)
        openHighlightPicker(app)
        let green = app.buttons["highlight-color-green"]
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        green.tap()
        XCTAssertTrue(app.staticTexts["Unable to save"].waitForExistence(timeout: 5))
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["Unable to save"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(green.waitForNonExistence(timeout: 5))
        openHighlightPicker(app)
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        XCTAssertFalse(green.isSelected)
    }

    @MainActor func testPartialHighlightUsesNativeSelectionAndCanBeEdited() {
        let app = launch()
        openFirstVerse(app)
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["English"].tap()
        firstTranslationWord(app).press(forDuration: 1.2)
        let highlight = app.menuItems["Highlight"]
        XCTAssertTrue(highlight.waitForExistence(timeout: 5))
        highlight.tap()
        XCTAssertTrue(app.buttons["highlight-color-blue"].waitForExistence(timeout: 5))
        for color in ["yellow", "green", "blue", "pink", "purple", "orange"] {
            let swatch = app.buttons["highlight-color-\(color)"]
            XCTAssertTrue(swatch.isHittable)
            XCTAssertFalse(swatch.isSelected)
        }
        XCTAssertFalse(app.textViews["highlight-note-editor"].exists)
        XCTAssertFalse(app.buttons["save-highlight"].exists)
        dismissHighlightSheet(app)
        XCTAssertTrue(app.buttons["highlight-color-blue"].waitForNonExistence(timeout: 5))
        openHighlightPicker(app)
        XCTAssertFalse(app.staticTexts["Blue"].exists)
        app.buttons["highlight-color-orange"].tap()
        XCTAssertTrue(app.buttons["highlight-color-orange"].waitForNonExistence(timeout: 5))
        let reader = XCTAttachment(screenshot: app.screenshot())
        reader.name = "Persistent partial highlight"
        reader.lifetime = .keepAlways
        add(reader)
        editHighlight(app)
        XCTAssertTrue(app.buttons["highlight-color-orange"].isSelected)
        XCTAssertTrue(app.menuItems["Highlight"].waitForNonExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Partial highlight editor"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testPaletteCountAndOrderPersistIntoPicker() {
        let app = launch()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openSettingsFromTools()
        app.buttons["settings-highlight-colors"].tap()
        let count = app.steppers["highlight-color-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.value as? String, "6")
        let paletteScreenshot = XCTAttachment(screenshot: app.screenshot())
        paletteScreenshot.name = "Reorderable highlight swatches"
        paletteScreenshot.lifetime = .keepAlways
        add(paletteScreenshot)
        count.buttons.element(boundBy: 1).tap()
        let orange = app.cells.containing(.any, identifier: "palette-color-orange").firstMatch
        let yellow = app.cells.containing(.any, identifier: "palette-color-yellow").firstMatch
        XCTAssertTrue(orange.isHittable)
        orange.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            .press(forDuration: 1, thenDragTo: yellow.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.1)))
        app.terminate()
        app.launchArguments.append("--ui-testing-preserve-state")
        app.launch()
        openQuran(app)
        openFirstVerse(app)
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["English"].tap()
        firstTranslationWord(app).press(forDuration: 1.2)
        app.menuItems["Highlight"].tap()
        let first = app.buttons["highlight-color-orange"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(first.isSelected)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "highlight-color-")).count, 7)
        XCTAssertLessThan(first.frame.minX, app.buttons["highlight-color-yellow"].frame.minX)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertFalse(app.buttons["highlight-add-note"].exists)
    }

    @MainActor func testAllColorsFitWithLargeText() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-highlightColorCount", "12"])
        openFirstVerse(app)
        openHighlightPicker(app)
        XCTAssertTrue(app.buttons["highlight-color-yellow"].waitForExistence(timeout: 5))
        for color in ["yellow", "green", "blue", "pink", "purple", "orange", "red", "mint", "teal", "cyan", "indigo", "brown"] {
            XCTAssertTrue(app.buttons["highlight-color-\(color)"].isHittable)
        }
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
        let note = app.textViews["highlight-note-editor"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, "Read this here")
        XCTAssertTrue(app.textViews["highlight-note-editor"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quick note preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["highlight-color-green"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["verse-actions-1:1"].isHittable)
    }

    @MainActor func testOverlappingHighlightsOfferTheirNotesInPlace() {
        let app = launch(extra: ["--ui-testing-legacy-highlights"])
        openFirstVerse(app)
        app.buttons["quran-reading-options"].tap()
        app.buttons["quran-translation-picker"].tap()
        app.buttons["English"].tap()
        app.textViews["quran-translation-1:1"].coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.25)).tap()
        XCTAssertTrue(app.buttons["First note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Second note"].exists)
        app.buttons["First note"].tap()
        XCTAssertTrue(app.textViews["highlight-note-editor"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["highlight-note-editor"].value as? String, "First note")
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

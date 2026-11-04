import Foundation
@testable import Muntathir
import SwiftUI
import Testing
import UIKit

struct VerseShareTests {
    @MainActor @Test(arguments: ["zh.jian", "zh.majian"])
    func chineseTranslationSharePreview(translationID: String) throws {
        let translation = try #require(QuranTranslation.catalog.first { $0.id == translationID })
        let database = QuranDatabase(url: Bundle.main.url(forResource: "quran", withExtension: "db"), translationURLs: {
            QuranTestResources.translationURLs.filter { $0.key == translationID }
        })
        let dailyVerse = try #require(ContentLibrary().verses.first)
        let verse = try #require(try database.verse(surah: dailyVerse.surah, number: dailyVerse.number))
        #expect(verse.translations[translationID]?.isEmpty == false)
        let image = try #require(AyahImageRenderer.image(for: verse, locale: Locale(identifier: translation.language), translation: translation))
        try Attachment.record(#require(image.pngData()), named: "quran-\(translation.language).png")
    }

    @Test func copyIncludesOnlyTheShownTranslationAndReference() throws {
        let ayah = Ayah(surah: 1, number: 1, text: "Arabic source", translations: ["en.qarai": "English", "fr.hamidullah": "French"])
        let english = try #require(QuranTranslation.catalog.first { $0.id == "en.qarai" })
        let shared = VerseShareContent(ayah: ayah, translation: english, locale: Locale(identifier: "en"))
        #expect(shared.text == "Arabic source\n\nEnglish\n\nAl-Faatiha · 1:1")
        let arabic = VerseShareContent(ayah: ayah, translation: nil, locale: Locale(identifier: "ar"))
        #expect(arabic.text == "Arabic source\n\nالفاتحة · 1:1")
        let missing = VerseShareContent(ayah: Ayah(surah: 1, number: 1, text: "Arabic source"), translation: english, locale: Locale(identifier: "en"))
        #expect(missing.text.contains("Ali Quli") == false)
    }

    @Test func localizedImageReferencesDoNotChangeCopiedText() {
        let ayah = Ayah(surah: 2, number: 255, text: "Arabic")
        let english = VerseShareContent(ayah: ayah, translation: nil, locale: Locale(identifier: "en"))
        let arabic = VerseShareContent(ayah: ayah, translation: nil, locale: Locale(identifier: "ar"))
        #expect(english.imageReference == "2:255")
        #expect(arabic.imageReference == "البقرة ٢٥٥")
        #expect(arabic.reference.contains("2:255"))
    }

    @MainActor @Test func longestVerseSharingIsDisabledWithoutClipping() throws {
        let database = QuranDatabase(url: Bundle.main.url(forResource: "quran", withExtension: "db"), translationURLs: {
            QuranTestResources.translationURLs.filter { $0.key == "en.qarai" }
        })
        let ayah = try #require(try database.verse(surah: 2, number: 282))
        let translation = try #require(QuranTranslation.catalog.first { $0.id == "en.qarai" })
        #expect(!AyahImageRenderer.canShare(ayah, locale: Locale(identifier: "en"), translation: translation))
        #expect(AyahImageRenderer.image(for: ayah, locale: Locale(identifier: "en"), translation: translation) == nil)
    }

    @MainActor @Test func imageHeightBoundary() throws {
        #expect(ShareImageRenderer.fits(height: 960))
        #expect(!ShareImageRenderer.fits(height: 960.01))
        #expect(!ShareImageRenderer.fits(height: .infinity))
        #expect(!ShareImageRenderer.fits(height: 0))
        let exact = Color.white.frame(width: 540, height: 960)
        let image = try #require(ShareImageRenderer.image(exact, locale: Locale(identifier: "en")))
        #expect(image.cgImage?.height == 1920)
        #expect(!ShareImageRenderer.canShare(Color.white.frame(width: 540, height: 961), locale: Locale(identifier: "en")))
    }

    @MainActor @Test func translationChangesImageEligibility() throws {
        let english = try #require(QuranTranslation.catalog.first { $0.id == "en.qarai" })
        let verse = Ayah(surah: 1, number: 1, text: "بِسْمِ اللَّهِ", translations: [english.id: String(repeating: "Long translation text. ", count: 200)])
        #expect(AyahImageRenderer.canShare(verse, locale: Locale(identifier: "en")))
        #expect(!AyahImageRenderer.canShare(verse, locale: Locale(identifier: "en"), translation: english))
    }

    @MainActor @Test func hadithImagesAreContentSizedAndRejectOversizedContent() throws {
        let chapter = HadithChapter(id: 1, arabic: "كتاب", english: "Book", bookArabic: "كتاب", bookEnglish: "Book")
        func content(_ text: String, english: String = "") -> HadithShareContent {
            .init(narration: Hadith(id: 1, collectionID: "book", number: 1, chapter: chapter, arabic: text, englishNarrator: "", english: english), showEnglish: true, locale: Locale(identifier: "en"))
        }
        let short = try #require(HadithImageRenderer.image(for: content("نص الحديث")))
        let longer = try #require(HadithImageRenderer.image(for: content("نص الحديث", english: "A short English translation.")))
        #expect(short.cgImage?.width == 1080)
        #expect(try #require(short.cgImage?.height) < 1920)
        #expect(longer.size.height > short.size.height)
        let oversized = content(String(repeating: "نص الحديث الطويل ", count: 500))
        #expect(!HadithImageRenderer.canShare(oversized))
        #expect(HadithImageRenderer.image(for: oversized) == nil)
        try Attachment.record(#require(short.pngData()), named: "short-hadith.png")
    }
}

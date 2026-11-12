import Foundation
@testable import Muntathir
import SwiftUI
import Testing
import UIKit

struct VerseShareTests {
    @Test func arabicReferencesPrefixNamesWithoutChangingSourceIDs() {
        let verse = Ayah(surah: 2, number: 26, text: "")
        #expect(QuranReference.display(verse.id, locale: Locale(identifier: "ar_SA")) == "البقرة \u{2066}2:26\u{2069}")
        #expect(QuranReference.display("28:4", locale: Locale(identifier: "ar")) == "القصص \u{2066}28:4\u{2069}")
        #expect(QuranReference.display(verse.id, locale: Locale(identifier: "en")) == "2:26")
        #expect(QuranReference.display("invalid", locale: Locale(identifier: "ar")) == "invalid")
        #expect(verse.id == "2:26")
    }

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
        #expect(shared.text == "Arabic source\n\nEnglish\n\n1:1")
        let arabic = VerseShareContent(ayah: ayah, translation: nil, locale: Locale(identifier: "ar"))
        #expect(arabic.text == "Arabic source\n\nالفاتحة \u{2066}1:1\u{2069}")
        let missing = VerseShareContent(ayah: Ayah(surah: 1, number: 1, text: "Arabic source"), translation: english, locale: Locale(identifier: "en"))
        #expect(missing.text.contains("Ali Quli") == false)
    }

    @Test func imageAndCopiedReferencesMatch() {
        let ayah = Ayah(surah: 2, number: 255, text: "Arabic")
        let english = VerseShareContent(ayah: ayah, translation: nil, locale: Locale(identifier: "en"))
        let arabic = VerseShareContent(ayah: ayah, translation: nil, locale: Locale(identifier: "ar"))
        #expect(english.imageReference == "2:255")
        #expect(arabic.imageReference == "البقرة \u{2066}2:255\u{2069}")
        #expect(arabic.imageReference == arabic.reference)
        #expect(english.imageReference == english.reference)
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

    @Test func hadithReferencesUseBookAndDisplayNumber() {
        let chapter = HadithChapter(id: 1, arabic: "باب", english: "Chapter", bookArabic: "كتاب", bookEnglish: "Book")
        var narration = Hadith(id: 1, collectionID: "book", number: 4, chapter: chapter, arabic: "نص", englishNarrator: "", english: "")
        narration.readingNumber = 123
        let english = HadithShareContent(narration: narration, showEnglish: false, locale: Locale(identifier: "en"))
        #expect(english.reference == "Book • 123")
        #expect(english.text.hasSuffix("Book • 123"))
        #expect(HadithShareContent(narration: narration, showEnglish: false, locale: Locale(identifier: "ar")).reference == "كتاب • 123")
        narration = Hadith(id: 1, collectionID: Hadith.supplicationCollectionID, number: 4, chapter: chapter, arabic: "نص", englishNarrator: "", english: "")
        #expect(HadithShareContent(narration: narration, showEnglish: false, locale: Locale(identifier: "en")).reference == "Book · Chapter")
    }

    @MainActor @Test func shareHighlightsRespectBlocksRangesAndNewestColor() throws {
        let raw = "رَحْمَةٌ ورحمة"
        var whole = ReadingHighlight(source: "1:1", isHadith: false, excerpt: raw, reference: "1:1")
        whole.modifiedAt = Date(timeIntervalSince1970: 1)
        let range = (raw as NSString).range(of: "ورحمة")
        var selected = try ReadingHighlight(source: "1:1", isHadith: false, block: "arabic",
                                            ranges: [#require(HighlightRange(range, in: raw))], excerpt: "ورحمة", reference: "1:1", color: .blue)
        selected.modifiedAt = Date(timeIntervalSince1970: 2)
        let segments = ShareHighlightText(text: AttributedString(raw), highlights: [selected, whole], block: "arabic").segments
        #expect(segments.map { String($0.text.characters) }.joined() == raw)
        #expect(segments.first?.color == UIColor(Color.yellow).withAlphaComponent(0.3))
        #expect(segments.last?.color == UIColor(Color.blue).withAlphaComponent(0.3))
        let translation = ShareHighlightText(text: AttributedString(raw), highlights: [selected], block: "en.qarai")
        #expect(translation.segments.allSatisfy { $0.color == nil })
        let stale = ShareHighlightText(text: AttributedString("changed source"), highlights: [selected], block: "arabic")
        #expect(stale.segments.allSatisfy { $0.color == nil })
    }

    @MainActor @Test func highlightedShareImagesPreserveMarkdownAndReferences() throws {
        let translation = try #require(QuranTranslation.catalog.first { $0.id == "en.qarai" })
        let verse = Ayah(surah: 2, number: 255, text: "اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ", translations: [translation.id: "Allah — there is no god except Him."])
        let highlight = ReadingHighlight(source: verse.id, isHadith: false, excerpt: verse.text, reference: verse.id, color: .green)
        let plain = try #require(AyahImageRenderer.image(for: verse, locale: Locale(identifier: "ar"), translation: translation))
        let colored = try #require(AyahImageRenderer.image(for: verse, locale: Locale(identifier: "ar"), translation: translation, highlights: [highlight]))
        #expect(plain.size == colored.size)
        #expect(plain.pngData() != colored.pngData())
        try Attachment.record(#require(colored.pngData()), named: "highlighted-quran.png")

        let chapter = HadithChapter(id: 1, arabic: "باب", english: "Chapter", bookArabic: "كتاب", bookEnglish: "Book")
        let markdown = "First **bold** paragraph.\n\n> Second paragraph.\n\n- List item"
        let parsed = HadithText.markdown(markdown)
        let canonical = HighlightTextContent.canonical(parsed)
        let start = (canonical as NSString).range(of: "bold").location
        let end = (canonical as NSString).range(of: "Second").location + 6
        let saved = try ReadingHighlight(source: "book:1", isHadith: true, block: "english",
                                         ranges: [#require(HighlightRange(NSRange(location: start, length: end - start), in: canonical))],
                                         excerpt: "", reference: "Book • 123", color: .pink)
        let first = try #require(HadithText.paragraphs(parsed).first)
        let segments = ShareHighlightText(text: first.text, highlights: [saved], block: "english", sourceText: canonical).segments
        #expect(segments.contains { $0.color != nil && $0.text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true } })
        let narration = Hadith(id: 1, collectionID: "book", number: 123, chapter: chapter, arabic: "نص الحديث", englishNarrator: "A narrator", english: markdown)
        let content = HadithShareContent(narration: narration, showEnglish: true, locale: Locale(identifier: "en"))
        let image = try #require(HadithImageRenderer.image(for: content, highlights: [saved]))
        let unhighlighted = try #require(HadithImageRenderer.image(for: content))
        #expect(image.size == unhighlighted.size)
        #expect(image.pngData() != unhighlighted.pngData())
        try Attachment.record(#require(image.pngData()), named: "highlighted-hadith.png")
        let hidden = HadithShareContent(narration: narration, showEnglish: false, locale: content.locale)
        #expect(HadithImageRenderer.image(for: hidden, highlights: [saved])?.pngData() == HadithImageRenderer.image(for: hidden)?.pngData())
    }
}

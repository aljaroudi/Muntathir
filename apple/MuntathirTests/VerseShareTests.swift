import Foundation
@testable import Muntathir
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

    @MainActor @Test func longestVerseImageIncludesTranslationWithoutClipping() throws {
        let database = QuranDatabase(url: Bundle.main.url(forResource: "quran", withExtension: "db"), translationURLs: {
            QuranTestResources.translationURLs.filter { $0.key == "en.qarai" }
        })
        let ayah = try #require(try database.verse(surah: 2, number: 282))
        let translation = try #require(QuranTranslation.catalog.first { $0.id == "en.qarai" })
        let arabic = try #require(AyahImageRenderer.image(for: ayah, locale: Locale(identifier: "ar")))
        let bilingual = try #require(AyahImageRenderer.image(for: ayah, locale: Locale(identifier: "en"), translation: translation))
        #expect(bilingual.size.height > arabic.size.height)
        #expect(bilingual.cgImage?.width == 1080)
        try Attachment.record(#require(bilingual.pngData()), named: "long-bilingual-verse.png")
    }
}

extension VerseShareTests {
    @MainActor @Test func hadithPaginationPreservesEveryCharacter() throws {
        let text = String(repeating: "نص الحديث العربي English narration with a long paragraph.\n", count: 300)
        let attributed = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 24)])
        let pages = HadithImageRenderer.pages(attributed)
        #expect(pages.count > 1)
        #expect(pages.map(\.string).joined() == text)
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
    }

    @MainActor @Test func hadithSharesOnlyVisibleLanguagesAndSourceReference() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let narration = try await HadithReader(database: HadithDatabase(url: fixture.url)).detail(id: 1).narration
        let arabic = HadithShareContent(narration: narration, showEnglish: false, locale: Locale(identifier: "en"))
        let bilingual = HadithShareContent(narration: narration, showEnglish: true, locale: Locale(identifier: "en"))
        #expect(!arabic.text.contains("Narrator"))
        #expect(bilingual.text.contains("Narrator"))
        #expect(bilingual.text.contains(narration.english))
        #expect(arabic.text.hasSuffix(arabic.reference))
        let files = try HadithImageRenderer.files(for: bilingual)
        let first = try #require(files.first)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }
        for file in files {
            let image = try #require(UIImage(contentsOfFile: file.path))
            #expect(image.cgImage?.width == 1080)
            #expect(image.cgImage?.height == 2600)
        }
    }
}

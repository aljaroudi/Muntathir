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
        let verses = try database.verses(surah: 112)
        #expect(verses.count == 4)
        for verse in verses {
            #expect(verse.translations[translationID]?.isEmpty == false)
        }
        let verse = try #require(verses.first)
        let image = try #require(AyahImageRenderer.image(for: verse, locale: Locale(identifier: translation.language), translation: translation))
        try Attachment.record(#require(image.pngData()), named: "quran-\(translation.language).png")
    }

    @Test func copyIncludesOnlyTheShownTranslationAndReference() throws {
        let ayah = Ayah(surah: 1, number: 1, text: "Arabic source", translations: ["en.qarai": "English", "fr.hamidullah": "French"])
        let english = try #require(QuranTranslation.catalog.first { $0.id == "en.qarai" })
        let shared = VerseShareContent(ayah: ayah, translation: english, locale: Locale(identifier: "en"))
        #expect(shared.text == "Arabic source\n\nEnglish\n\nAli Quli Qara’i\n\nAl-Faatiha · 1:1")
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

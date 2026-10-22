import Foundation
@testable import Muntathir
import SQLite3
import Testing

struct QuranReaderTests {
    private var database: QuranDatabase {
        QuranDatabase(url: Bundle.main.url(forResource: "db", withExtension: "db"))
    }

    @Test func chaptersAndReferencesMatchTheBundledQuran() async throws {
        let reader = QuranReader(database: database)
        let catalog = try await reader.catalog()
        #expect(catalog.surahs.count == 114)
        #expect(catalog.counts.values.reduce(0, +) == 6236)
        #expect(catalog.counts[1] == 7)
        #expect(catalog.counts[2] == 286)
        #expect(catalog.counts[114] == 6)
        #expect(catalog.translations.map(\.id) == ["en.qarai"])
        let chapter = try await reader.verses(surah: 2)
        #expect(chapter.map(\.number) == Array(1 ... 286))
        #expect(try database.verse(surah: 2, number: 255)?.id == "2:255")
        #expect(try database.verse(surah: 2, number: 287) == nil)
        #expect(catalog.surahs[0].matches("الفاتحة"))
        #expect(catalog.surahs[0].matches("faatiha"))
        #expect(catalog.surahs[0].matches("Al Fatiha"))
        #expect(catalog.surahs[0].matches("!!!") == false)
        #expect(catalog.surahs[1].matches("٢"))
    }

    @Test func arabicSearchNormalizesOnlySearchKeysAndLeavesDatabaseUnchanged() async throws {
        let url = try #require(database.url)
        let before = try Data(contentsOf: url)
        let reader = QuranReader(database: database)
        let plain = try await reader.search("الله", translationID: nil, limit: 6236)
        let vocalized = try await reader.search("ٱللَّهِ", translationID: nil, limit: 6236)
        #expect(plain.count > 1000)
        #expect(plain.map(\.id) == vocalized.map(\.id))
        let first = try #require(plain.first)
        #expect(first.id == "1:1")
        #expect(first.text == database.verses(ids: [1])[1]?.text)
        #expect(first.text != QuranSearchText.normalize(first.text))
        #expect(try Data(contentsOf: url) == before)
        #expect(QuranSearchText.normalize("أإآٱـا") == "ااااا")
    }

    @Test func fullTextSearchRespectsTranslationSelectionAndPagination() async throws {
        let reader = QuranReader(database: database)
        #expect(try await reader.search("merciful", translationID: nil).isEmpty)
        #expect(try await reader.search("merciful", translationID: "fr.hamidullah").isEmpty)
        let translated = try await reader.search("merciful", translationID: "en.qarai")
        #expect(translated.isEmpty == false)
        #expect(translated.allSatisfy { $0.translations["en.qarai"]?.localizedCaseInsensitiveContains("merciful") == true })
        let first = try await reader.search("الله", translationID: nil, limit: 50)
        let next = try await reader.search("الله", translationID: nil, limit: 100)
        #expect(first.count == 50)
        #expect(next.count == 100)
        #expect(first.map(\.id) == Array(next.prefix(50)).map(\.id))
        #expect(Set(next.map(\.id)).count == next.count)
        #expect(next.map { $0.surah * 1000 + $0.number } == next.map { $0.surah * 1000 + $0.number }.sorted())
    }

    @Test func referencesAcceptArabicIndicDigitsAndRejectInvalidVerses() async throws {
        let reader = QuranReader(database: database)
        #expect(try await reader.search("٢:٢٥٥", translationID: nil).map(\.id) == ["2:255"])
        #expect(try await reader.search("۲ : ۲۵۵", translationID: nil).map(\.id) == ["2:255"])
        for query in ["0:1", "115:1", "2:287", "2:0", "2:", "2:abc", "2:1:2"] {
            await #expect(throws: QuranDatabaseError.self) { try await reader.search(query, translationID: nil) }
        }
    }

    @Test func literalSearchHandlesEmptyTextAndFTSOperators() async throws {
        let reader = QuranReader(database: database)
        for query in ["", "   ", "\" * : ()", "🙂"] {
            #expect(try await reader.search(query, translationID: "en.qarai").isEmpty)
        }
        let quoted = try await reader.search("\"merciful\"*", translationID: "en.qarai")
        let plain = try await reader.search("merciful", translationID: "en.qarai")
        #expect(quoted.map(\.id) == plain.map(\.id))
        #expect(QuranSearchText.expression("mercy OR forgiveness") == "\"mercy\" AND \"OR\" AND \"forgiveness\"")
    }

    @Test func languageDefaultsAndDailyTranslationStayIndependent() throws {
        let available = try database.availableTranslations()
        #expect(QuranTranslation.preferred(in: available, locale: Locale(identifier: "en_GB"))?.id == "en.qarai")
        #expect(QuranTranslation.preferred(in: available, locale: Locale(identifier: "ar")) == nil)
        #expect(QuranTranslation.preferred(in: available, locale: Locale(identifier: "fr")) == nil)
        #expect(QuranTranslation.preferred(in: QuranTranslation.catalog, locale: Locale(identifier: "zh_Hant_TW"))?.id == "zh.majian")
        let ayah = try #require(try database.verse(surah: 1, number: 1))
        #expect(ayah.dailyTranslation(locale: Locale(identifier: "en_US")) != nil)
        #expect(ayah.dailyTranslation(locale: Locale(identifier: "ar")) == nil)
        #expect(ayah.dailyTranslation(locale: Locale(identifier: "fr")) == nil)
    }

    @Test func arabicOnlyAndMissingTranslationValuesRemainReadable() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let connection = try QuranConnection(path: url.path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
            try connection.execute("CREATE TABLE quran (\"index\" INTEGER PRIMARY KEY, sura INTEGER, aya INTEGER, text TEXT)")
            try connection.execute("INSERT INTO quran VALUES (1, 1, 1, 'نص')")
        }
        let database = QuranDatabase(url: url)
        #expect(try database.availableTranslations().isEmpty)
        #expect(database.verses(ids: [1])[1]?.text == "نص")
        do {
            let connection = try QuranConnection(path: url.path, flags: SQLITE_OPEN_READWRITE)
            try connection.execute("ALTER TABLE quran ADD COLUMN en_qarai TEXT")
            try connection.execute("ALTER TABLE quran ADD COLUMN fr_hamidullah TEXT")
            try connection.execute("UPDATE quran SET fr_hamidullah = 'texte'")
        }
        let ayah = try #require(database.verses(ids: [1])[1])
        #expect(ayah.translations == ["fr.hamidullah": "texte"])
        #expect(ayah.dailyTranslation(locale: Locale(identifier: "en")) == nil)
        #expect(try database.availableTranslations().map(\.id) == ["en.qarai", "fr.hamidullah"])
    }

    @Test func databaseFailureIsNotAnEmptySearchAndCancellationIsRespected() async throws {
        let missing = QuranReader(database: QuranDatabase(url: nil))
        await #expect(throws: QuranDatabaseError.self) { try await missing.catalog() }
        await #expect(throws: QuranDatabaseError.self) { try await missing.search("الله", translationID: nil) }
        let reader = QuranReader(database: database)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.search("الله", translationID: nil)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await reader.search("الله", translationID: nil).isEmpty == false)
    }
}

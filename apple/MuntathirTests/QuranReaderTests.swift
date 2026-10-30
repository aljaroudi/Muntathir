import Foundation
@testable import Muntathir
import SQLite3
import Testing

struct QuranReaderTests {
    private var database: QuranDatabase {
        QuranDatabase(url: Bundle.main.url(forResource: "quran", withExtension: "db"), translationURLs: {
            QuranTestResources.translationURLs
        })
    }

    @Test func chaptersAndReferencesMatchTheBundledQuran() async throws {
        let reader = QuranReader(database: database)
        let catalog = try await reader.catalog()
        #expect(catalog.surahs.count == 114)
        #expect(catalog.counts.values.reduce(0, +) == 6236)
        #expect(catalog.counts[1] == 7)
        #expect(catalog.counts[2] == 286)
        #expect(catalog.counts[114] == 6)
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
        let vocalized = try await reader.search("ٱللَّهِ", translationID: nil, limit: 6236)
        #expect(plain.count > 1000)
        #expect(plain.map(\.id) == vocalized.map(\.id))
        let first = try #require(plain.first)
        #expect(try first.text == database.verse(surah: first.surah, number: first.number)?.text)
        #expect(first.text != QuranSearchText.normalize(first.text))
        #expect(try Data(contentsOf: url) == before)
        #expect(QuranSearchText.normalize("أإآٱـا") == "ااااا")
        #expect(QuranSearchText.normalize("فى رحمة") == "في رحمه")
    }

    @Test func searchIndexesMatchUpdatedOpeningVerses() throws {
        let ids = try database.connection().query("SELECT rowid FROM quran_words WHERE quran_words MATCH ? ORDER BY rowid", parameters: ["text : \"بسم\""]) {
            Int(sqlite3_column_int($0, 0))
        }
        let matches = try database.readVerses(where: "\"index\" IN (\(ids.map { _ in "?" }.joined(separator: ",")))", parameters: ids.map(String.init))
        #expect(matches.map(\.1.id) == ["1:1", "11:41", "27:30"])
    }

    @Test func arabicSearchFindsContainedWordsRootsTyposAndShortWords() async throws {
        let reader = QuranReader(database: database)
        #expect(try await reader.search("صوم", translationID: nil, limit: 6236).map(\.id).contains("19:26"))
        #expect(try await reader.search("كتب", translationID: nil, limit: 6236).map(\.id).contains("2:79"))
        #expect(try await reader.search("يكتبون", translationID: nil, limit: 6236).map(\.id).contains("2:2"))
        #expect(try await reader.search("الرحمم", translationID: nil, limit: 6236).map(\.id).contains("1:1"))
        #expect(try await reader.search("الصلاة", translationID: nil).isEmpty == false)
        #expect(try await reader.search("في", translationID: nil).isEmpty == false)
        let exact = try await reader.search("الرحيم", translationID: nil, limit: 6236)
        #expect(exact.first.map { QuranSearchText.normalize($0.text).contains("الرحيم") } == true)
    }

    @Test func fullTextSearchRespectsTranslationSelectionAndPagination() async throws {
        let reader = QuranReader(database: database)
        #expect(try await reader.search("merciful", translationID: nil).isEmpty)
        #expect(try await reader.search("merciful", translationID: "es.bornez").isEmpty)
        let translated = try await reader.search("merciful", translationID: "en.qarai")
        #expect(translated.isEmpty == false)
        #expect(translated.allSatisfy { $0.translations["en.qarai"]?.localizedCaseInsensitiveContains("merc") == true })
        #expect(try await reader.search("believing", translationID: "en.qarai").contains { $0.translations["en.qarai"]?.contains("believers") == true })
        #expect(try await reader.search("Clementísimo", translationID: "es.bornez").map(\.id).contains("1:1"))
        #expect(try await reader.search("真主", translationID: "zh.jian").isEmpty == false)
        let first = try await reader.search("الله", translationID: nil, limit: 50)
        let next = try await reader.search("الله", translationID: nil, limit: 100)
        #expect(first.count == 50)
        #expect(next.count == 100)
        #expect(first.map(\.id) == Array(next.prefix(50)).map(\.id))
        #expect(Set(next.map(\.id)).count == next.count)
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
        #expect(QuranSearchText.terms("Mercy OR forgiveness") == ["mercy", "or", "forgiveness"])
        #expect(QuranSearchText.distance("الرحمم", "الرحمن") == 1)
    }

    @Test func languageDefaultsAndSelectedDailyTranslation() throws {
        let available = try database.availableTranslations()
        #expect(QuranTranslation.preferred(in: available, locale: Locale(identifier: "en_GB"))?.id == "en.qarai")
        #expect(QuranTranslation.preferred(in: available, locale: Locale(identifier: "ar")) == nil)
        #expect(QuranTranslation.preferred(in: available, locale: Locale(identifier: "es"))?.id == "es.bornez")
        #expect(QuranTranslation.preferred(in: QuranTranslation.catalog, locale: Locale(identifier: "zh_Hant_TW"))?.id == "zh.majian")
        let url = try #require(Bundle.main.url(forResource: "quran", withExtension: "db"))
        let selected = QuranDatabase(url: url, translationURLs: { ["es.bornez": QuranTestResources.translationURLs["es.bornez"]!] })
        let ayah = try #require(selected.verses(ids: [1])[1])
        #expect(ayah.translations.keys.sorted() == ["es.bornez"])
        #expect(ayah.selectedTranslationText != nil)
    }

    @Test func arabicOnlyAndMissingTranslationValuesRemainReadable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func create(_ name: String, text: String) throws {
            let connection = try QuranConnection(path: folder.appendingPathComponent(name).path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
            try connection.execute("CREATE TABLE quran (\"index\" INTEGER PRIMARY KEY, sura INTEGER, aya INTEGER, text TEXT)")
            try connection.execute("INSERT INTO quran VALUES (1, 1, 1, ?)", parameters: [text])
        }
        try create("quran.db", text: "نص")
        let database = QuranDatabase(url: folder.appendingPathComponent("quran.db"), translationURLs: {
            Dictionary(uniqueKeysWithValues: QuranTranslation.catalog.map { ($0.id, folder.appendingPathComponent("\($0.id).db")) })
        })
        #expect(try database.availableTranslations().isEmpty)
        #expect(database.verses(ids: [1])[1]?.text == "نص")
        try create("es.bornez.db", text: "texte")
        try create("en.qarai.db", text: " ")
        let ayah = try #require(database.verses(ids: [1])[1])
        #expect(ayah.translations == ["es.bornez": "texte"])
        #expect(ayah.selectedTranslationText == "texte")
        #expect(try database.availableTranslations().map(\.id) == ["en.qarai", "es.bornez"])
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

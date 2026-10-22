import Foundation
import SQLite3

/// Keeps the disposable Arabic search index off the main actor and inside one isolation boundary.
actor QuranReader {
    let database: QuranDatabase
    private var arabicIndex: QuranConnection?

    init(database: QuranDatabase = QuranDatabase(url: Bundle.main.url(forResource: "db", withExtension: "db"))) {
        self.database = database
    }

    func catalog() throws -> (surahs: [QuranSurah], counts: [Int: Int], translations: [QuranTranslation]) {
        let surahs = try QuranSurah.load()
        let counts = try database.chapterCounts()
        guard surahs.allSatisfy({ (counts[$0.id] ?? 0) > 0 }) else { throw QuranDatabaseError.unavailable }
        return try (surahs, counts, database.availableTranslations())
    }

    func verses(surah: Int) throws -> [Ayah] {
        try database.verses(surah: surah)
    }

    func verses(references: [String]) throws -> [Ayah] {
        try references.compactMap { reference in
            guard let parsed = try QuranSearchText.reference(reference) else { return nil }
            return try database.verse(surah: parsed.surah, number: parsed.verse)
        }.sorted { ($0.surah, $0.number) < ($1.surah, $1.number) }
    }

    func search(_ query: String, translationID: String?, limit: Int = 50) throws -> [Ayah] {
        try Task.checkCancellation()
        if let reference = try QuranSearchText.reference(query) {
            guard let verse = try database.verse(surah: reference.surah, number: reference.verse) else {
                throw QuranDatabaseError.invalidReference
            }
            return [verse]
        }
        guard let expression = QuranSearchText.expression(QuranSearchText.normalize(query)) else { return [] }
        let index = try normalizedIndex()
        var ids = try Set(index.query("SELECT rowid FROM arabic WHERE arabic MATCH ?", parameters: [expression]) { Int(sqlite3_column_int($0, 0)) })
        if let translation = try database.availableTranslations().first(where: { $0.id == translationID }),
           let expression = QuranSearchText.expression(query)
        {
            let matches = try database.connection().query("SELECT rowid FROM quran_fts WHERE quran_fts MATCH ?", parameters: ["\(translation.column) : (\(expression))"]) { Int(sqlite3_column_int($0, 0)) }
            ids.formUnion(matches)
        }
        guard !ids.isEmpty else { return [] }
        let ordered = ids.sorted()
        return try database.readVerses(where: "\"index\" IN (\(ordered.map { _ in "?" }.joined(separator: ",")))", parameters: ordered.map(String.init), limit: limit).map(\.1)
    }

    private func normalizedIndex() throws -> QuranConnection {
        if let arabicIndex {
            return arabicIndex
        }
        let index = try QuranConnection(path: ":memory:", flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        try index.execute("CREATE VIRTUAL TABLE arabic USING fts5(text, tokenize = 'unicode61 remove_diacritics 2')")
        try index.execute("BEGIN")
        let verses = try database.connection().query("SELECT \"index\", text FROM quran") {
            (Int(sqlite3_column_int($0, 0)), QuranConnection.text($0, 1))
        }
        for (id, text) in verses {
            try index.execute("INSERT INTO arabic(rowid, text) VALUES (?, ?)", parameters: [String(id), QuranSearchText.normalize(text)])
        }
        try index.execute("COMMIT")
        arabicIndex = index
        return index
    }
}

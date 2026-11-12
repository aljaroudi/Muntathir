import Foundation
import SQLite3

/// Keeps search off the main actor.
actor QuranReader {
    typealias Catalog = (surahs: [QuranSurah], counts: [Int: Int], readingWords: [Int: Int])
    let database: QuranDatabase
    private var cachedCatalog: Catalog?

    init(database: QuranDatabase = QuranDatabase()) {
        self.database = database
    }

    func catalog() throws -> Catalog {
        if let cachedCatalog {
            return cachedCatalog
        }
        let surahs = try QuranSurah.load()
        let (counts, readingWords) = try chapterStatistics()
        guard surahs.allSatisfy({ (counts[$0.id] ?? 0) > 0 }) else { throw QuranDatabaseError.unavailable }
        let catalog = (surahs, counts, readingWords)
        cachedCatalog = catalog
        return catalog
    }

    private func chapterStatistics() throws -> (counts: [Int: Int], readingWords: [Int: Int]) {
        let rows = try database.connection().query("SELECT sura, text FROM quran") {
            try Task.checkCancellation()
            return (Int(sqlite3_column_int($0, 0)), ReadingTime.words(arabic: QuranConnection.text($0, 1)))
        }
        var counts: [Int: Int] = [:]
        var readingWords: [Int: Int] = [:]
        for (surah, words) in rows {
            counts[surah, default: 0] += 1
            readingWords[surah, default: 0] += words
        }
        return (counts, readingWords)
    }

    func verses(surah: Int) throws -> [Ayah] {
        try database.verses(surah: surah)
    }

    func page(_ number: Int) throws -> QuranPage {
        try database.page(number)
    }

    func page(surah: Int, verse: Int) throws -> Int? {
        try database.page(surah: surah, verse: verse)
    }

    func verses(references: [String]) throws -> [Ayah] {
        try references.compactMap { reference in
            guard let parsed = try QuranSearchText.reference(reference) else { return nil }
            return try database.verse(surah: parsed.surah, number: parsed.verse)
        }.sorted { ($0.surah, $0.number) < ($1.surah, $1.number) }
    }

    /// Literal phrases, then literal substrings; Arabic wins ties between languages.
    func search(_ query: String, translationID: String?, limit: Int = 50, surah: Int? = nil) throws -> [Ayah] {
        try Task.checkCancellation()
        if let surah, let number = QuranSearchText.number(query) {
            guard let verse = try database.verse(surah: surah, number: number) else {
                throw QuranDatabaseError.invalidReference
            }
            return [verse]
        }
        if let reference = try QuranSearchText.reference(query) {
            guard surah == nil || reference.surah == surah else { return [] }
            guard let verse = try database.verse(surah: reference.surah, number: reference.verse) else {
                throw QuranDatabaseError.invalidReference
            }
            return [verse]
        }
        let terms = QuranSearchText.terms(query)
        guard !terms.isEmpty else { return [] }
        let arabicConnection = try database.connection()
        let arabic = try ranked(matches(terms, in: arabicConnection), terms: terms, in: arabicConnection)
        var translated = [[Int]](repeating: [], count: 2)
        if let translation = try database.availableTranslations().first(where: { $0.id == translationID }) {
            // Optional assets can disappear or be invalid; Arabic search must still work.
            do {
                let connection = try database.connection(to: translation)
                let found = try matches(terms, in: connection)
                translated = try ranked(found, terms: terms, in: connection)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep Arabic results when a translation cannot be read.
            }
        }
        var seen = Set<Int>()
        var ids = (0 ... 1).flatMap { arabic[$0] + translated[$0] }.filter { seen.insert($0).inserted }
        if let surah {
            let chapterIDs = try Set(database.connection().query("SELECT \"index\" FROM quran WHERE sura = ?", parameters: [String(surah)]) {
                Int(sqlite3_column_int($0, 0))
            })
            ids = ids.filter { chapterIDs.contains($0) }
        }
        let eligible = try Set(arabicConnection.query("SELECT \"index\", text FROM quran") {
            QuranSearchText.isSearchableVerse(QuranConnection.text($0, 1)) ? Int(sqlite3_column_int($0, 0)) : -1
        })
        ids = ids.filter { eligible.contains($0) }
        let page = ids.prefix(max(0, limit)).map(String.init)
        guard !page.isEmpty else { return [] }
        let verses = try Dictionary(uniqueKeysWithValues: database.readVerses(where: "\"index\" IN (\(page.map { _ in "?" }.joined(separator: ",")))", parameters: page))
        return page.compactMap { Int($0).flatMap { verses[$0] } }
    }

    private func ranked(_ ids: [Int], terms: [String], in connection: QuranConnection) throws -> [[Int]] {
        guard !ids.isEmpty else { return [[], []] }
        let texts = try Dictionary(uniqueKeysWithValues: connection.query("SELECT \"index\", text FROM quran") {
            (Int(sqlite3_column_int($0, 0)), QuranConnection.text($0, 1))
        })
        var groups = [[Int]](repeating: [], count: 2)
        for id in ids {
            try Task.checkCancellation()
            let rank = QuranSearchText.literalRank(texts[id] ?? "", terms: terms)
            if rank < 2 {
                groups[rank].append(id)
            }
        }
        groups[0].sort()
        groups[1].sort()
        return groups
    }

    /// Trigrams narrow candidates; literal ranking verifies every query term.
    private func matches(_ terms: [String], in database: QuranConnection) throws -> [Int] {
        let indexed = terms.filter { $0.count >= 3 }
        if !indexed.isEmpty {
            return try database.query("SELECT rowid FROM quran_fts WHERE quran_fts MATCH ? ORDER BY rowid", parameters: [indexed.map { "\"\($0)\"" }.joined(separator: " AND ")]) {
                Int(sqlite3_column_int($0, 0))
            }
        }
        // Trigrams cannot retrieve one- or two-letter infixes.
        return try database.query("SELECT \"index\" FROM quran ORDER BY \"index\"") { Int(sqlite3_column_int($0, 0)) }
    }
}

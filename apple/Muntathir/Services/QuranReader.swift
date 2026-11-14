import Foundation
import SQLite3

/// Keeps search off the main actor.
actor QuranReader {
    typealias Catalog = (surahs: [QuranSurah], counts: [Int: Int], readingWords: [Int: Int])
    let database: QuranDatabase
    private struct SearchKey: Equatable {
        let query: String
        let translationID: String?
        let limit: Int
        let surah: Int?
        let revision: Int
    }
    private var recentSearches: [(SearchKey, [Ayah])] = []
    private var cachedCatalog: Catalog?
    private(set) var relatedIDs: Set<String> = []

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

    /// Exact phrases, then all-word matches; Arabic wins ties between languages.
    func search(_ query: String, translationID: String?, limit: Int = 50, surah: Int? = nil, revision: Int = 0) throws -> [Ayah] {
        try Task.checkCancellation()
        let key = SearchKey(query: query, translationID: translationID, limit: limit, surah: surah, revision: revision)
        recentSearches.removeAll { $0.0.revision != revision }
        if let index = recentSearches.firstIndex(where: { $0.0 == key }) {
            let entry = recentSearches.remove(at: index)
            recentSearches.append(entry)
            return entry.1
        }
        let result = try performSearch(query, translationID: translationID, limit: limit, surah: surah)
        if limit <= 201 {
            recentSearches.append((key, result))
            if recentSearches.count > 8 { recentSearches.removeFirst() }
        }
        return result
    }

    private func performSearch(_ query: String, translationID: String?, limit: Int, surah: Int?) throws -> [Ayah] {
        try Task.checkCancellation()
        relatedIDs = []
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
        var translated = [[Int]](repeating: [], count: 3)
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
        let relatedIndexes = Set(arabic[2] + translated[2]).subtracting(arabic[0] + arabic[1] + translated[0] + translated[1])
        var seen = Set<Int>()
        var ids = (0 ... 2).flatMap { arabic[$0] + translated[$0] }.filter { seen.insert($0).inserted }
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
        relatedIDs = Set(relatedIndexes.compactMap { verses[$0]?.id })
        return page.compactMap { Int($0).flatMap { verses[$0] } }
    }

    private func ranked(_ ids: [Int], terms: [String], in connection: QuranConnection) throws -> [[Int]] {
        guard !ids.isEmpty else { return [[], [], []] }
        let texts = try Dictionary(uniqueKeysWithValues: connection.query("SELECT \"index\", text FROM quran") {
            (Int(sqlite3_column_int($0, 0)), QuranConnection.text($0, 1))
        })
        var groups = [[(Int, SearchRelevance)]](repeating: [], count: 3)
        for id in ids {
            try Task.checkCancellation()
            if let score = SearchRelevance.score(texts[id] ?? "", terms: terms), score.tier < 2 {
                groups[score.tier].append((id, score))
            }
        }
        return groups.map { group in
            group.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }.map(\.0)
        }
    }

    /// Basic offline retrieval uses one word index, including one- and two-letter words.
    private func matches(_ terms: [String], in database: QuranConnection) throws -> [Int] {
        let hasIndex = try !database.query("SELECT name FROM sqlite_master WHERE name='quran_words'") { QuranConnection.text($0, 0) }.isEmpty
        if hasIndex {
            let indexed = terms.map { "text : \"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")
            return try database.query("SELECT rowid FROM quran_words WHERE quran_words MATCH ? ORDER BY rowid", parameters: [indexed]) {
                Int(sqlite3_column_int($0, 0))
            }
        }
        // Chinese translations have no whitespace word index; their 6,236 rows use literal matching.
        return try database.query("SELECT \"index\", text FROM quran ORDER BY \"index\"") {
            (Int(sqlite3_column_int($0, 0)), QuranConnection.text($0, 1))
        }.filter { QuranSearchText.literalRank($0.1, terms: terms) < 2 }.map(\.0)
    }
}

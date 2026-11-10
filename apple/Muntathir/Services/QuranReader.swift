import Foundation
import SQLite3

/// Keeps search off the main actor.
actor QuranReader {
    let database: QuranDatabase

    init(database: QuranDatabase = QuranDatabase()) {
        self.database = database
    }

    func catalog() throws -> (surahs: [QuranSurah], counts: [Int: Int]) {
        let surahs = try QuranSurah.load()
        let counts = try database.chapterCounts()
        guard surahs.allSatisfy({ (counts[$0.id] ?? 0) > 0 }) else { throw QuranDatabaseError.unavailable }
        return (surahs, counts)
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

    /// Literal words, literal substrings, then broader hits; Arabic wins ties between languages.
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
        let arabic = try ranked(matches(terms, in: arabicConnection, roots: true), terms: terms, in: arabicConnection)
        var translated = [[Int]](repeating: [], count: 3)
        if let translation = try database.availableTranslations().first(where: { $0.id == translationID }) {
            // Optional assets can disappear or be invalid; Arabic search must still work.
            do {
                let connection = try database.connection(to: translation)
                let found = try translation.id.hasPrefix("zh.") ? substrings(terms, in: connection) : matches(terms, in: connection, roots: false)
                translated = try ranked(found, terms: terms, in: connection)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep Arabic results when a translation cannot be read.
            }
        }
        var seen = Set<Int>()
        var ids = (0 ... 2).flatMap { arabic[$0] + translated[$0] }.filter { seen.insert($0).inserted }
        if let surah {
            let chapterIDs = try Set(database.connection().query("SELECT \"index\" FROM quran WHERE sura = ?", parameters: [String(surah)]) {
                Int(sqlite3_column_int($0, 0))
            })
            ids = ids.filter { chapterIDs.contains($0) }
        }
        let page = ids.prefix(max(0, limit)).map(String.init)
        guard !page.isEmpty else { return [] }
        let verses = try Dictionary(uniqueKeysWithValues: database.readVerses(where: "\"index\" IN (\(page.map { _ in "?" }.joined(separator: ",")))", parameters: page))
        return page.compactMap { Int($0).flatMap { verses[$0] } }
    }

    private func ranked(_ ids: [Int], terms: [String], in connection: QuranConnection) throws -> [[Int]] {
        guard !ids.isEmpty else { return [[], [], []] }
        let texts = try Dictionary(uniqueKeysWithValues: connection.query("SELECT \"index\", text FROM quran") {
            (Int(sqlite3_column_int($0, 0)), QuranConnection.text($0, 1))
        })
        var groups = [[Int]](repeating: [], count: 3)
        for id in ids {
            try Task.checkCancellation()
            groups[QuranSearchText.literalRank(texts[id] ?? "", terms: terms)].append(id)
        }
        groups[0].sort()
        groups[1].sort()
        return groups
    }

    /// Ranked whole-word, prefix, and root hits; then verses where every term only appears inside longer words.
    private func matches(_ terms: [String], in database: QuranConnection, roots: Bool) throws -> [Int] {
        var groups: [String] = []
        for term in terms {
            var options = ["text : \"\(term)\"*"]
            if roots {
                options += try database.query("SELECT root FROM quran_roots WHERE word = ?", parameters: [term]) { "root : \"\(QuranConnection.text($0, 0))\"" }
                options.append("root : \"\(term)\"")
            }
            if try database.query("SELECT count(*) FROM quran_words WHERE quran_words MATCH ?", parameters: [options.joined(separator: " OR ")], row: { sqlite3_column_int($0, 0) }).first == 0 {
                options += try similar(term, in: database).map { "text : \"\($0)\"" }
            }
            groups.append("(\(options.joined(separator: " OR ")))")
        }
        let rank = roots ? "bm25(quran_words, 4.0, 1.0)" : "bm25(quran_words)"
        var ids = try database.query("SELECT rowid FROM quran_words WHERE quran_words MATCH ? ORDER BY \(rank), rowid", parameters: [groups.joined(separator: " AND ")]) { Int(sqlite3_column_int($0, 0)) }
        // Trigrams need 3+ characters per term.
        if terms.allSatisfy({ $0.count >= 3 }) {
            let seen = Set(ids)
            ids += try database.query("SELECT rowid FROM quran_fts WHERE quran_fts MATCH ? ORDER BY rowid", parameters: [terms.map { "\"\($0)\"" }.joined(separator: " AND ")]) {
                Int(sqlite3_column_int($0, 0))
            }.filter { !seen.contains($0) }
        }
        return ids
    }

    /// Up to three indexed words within one (short terms) or two edits, most frequent first.
    private func similar(_ term: String, in database: QuranConnection) throws -> [String] {
        guard term.count >= 3 else { return [] }
        let allowed = term.count <= 4 ? 1 : 2
        let candidates = try database.query("SELECT term, doc FROM quran_words_vocab WHERE col = 'text' AND length(term) BETWEEN CAST(? AS INTEGER) AND CAST(? AS INTEGER)", parameters: [String(term.count - allowed), String(term.count + allowed)]) {
            (QuranConnection.text($0, 0), Int(sqlite3_column_int($0, 1)))
        }
        return candidates.compactMap { word, count in
            let distance = QuranSearchText.distance(term, word)
            return distance <= allowed ? (word, distance, count) : nil
        }
        .sorted { ($0.1, -$0.2) < ($1.1, -$1.2) }
        .prefix(3)
        .map(\.0)
    }

    /// For scripts without word boundaries (Chinese), every term must appear in the verse.
    private func substrings(_ terms: [String], in database: QuranConnection) throws -> [Int] {
        try database.query("SELECT \"index\" FROM quran WHERE \(terms.map { _ in "text LIKE ?" }.joined(separator: " AND ")) ORDER BY \"index\"", parameters: terms.map { "%\($0)%" }) {
            Int(sqlite3_column_int($0, 0))
        }
    }
}

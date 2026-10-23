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

    func verses(references: [String]) throws -> [Ayah] {
        try references.compactMap { reference in
            guard let parsed = try QuranSearchText.reference(reference) else { return nil }
            return try database.verse(surah: parsed.surah, number: parsed.verse)
        }.sorted { ($0.surah, $0.number) < ($1.surah, $1.number) }
    }

    /// Arabic matches first, then matches found only in the selected translation.
    func search(_ query: String, translationID: String?, limit: Int = 50) throws -> [Ayah] {
        try Task.checkCancellation()
        if let reference = try QuranSearchText.reference(query) {
            guard let verse = try database.verse(surah: reference.surah, number: reference.verse) else {
                throw QuranDatabaseError.invalidReference
            }
            return [verse]
        }
        let terms = QuranSearchText.terms(query)
        guard !terms.isEmpty else { return [] }
        var ids = try matches(terms, in: database.connection(), roots: true)
        if let translation = try database.availableTranslations().first(where: { $0.id == translationID }) {
            // Optional assets can disappear or be invalid; Arabic search must still work.
            do {
                let connection = try database.connection(to: translation)
                let seen = Set(ids)
                let found = try translation.id.hasPrefix("zh.") ? substrings(terms, in: connection) : matches(terms, in: connection, roots: false)
                ids += found.filter { !seen.contains($0) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep Arabic results when a translation cannot be read.
            }
        }
        let page = ids.prefix(max(0, limit)).map(String.init)
        guard !page.isEmpty else { return [] }
        let verses = try Dictionary(uniqueKeysWithValues: database.readVerses(where: "\"index\" IN (\(page.map { _ in "?" }.joined(separator: ",")))", parameters: page))
        return page.compactMap { Int($0).flatMap { verses[$0] } }
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

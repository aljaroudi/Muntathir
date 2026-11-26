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

    private struct RankKey: Equatable {
        let query: String
        let translationID: String?
        let surah: Int?
        let revision: Int
    }

    /// Arabic text, chapter and searchability per verse index; read once, since the bundled text never changes.
    private struct Corpus {
        let connection: QuranConnection
        let texts: [Int: String]
        let surahs: [Int: Int]
        let searchable: Set<Int>
        let indexed: Bool
        /// The word index's terms, for matching typed spellings to the mushaf's; absent without an index.
        let vocabulary: QuranVocabulary?
    }

    /// The active translation's texts, dropped whenever its revision changes.
    private struct TranslationCorpus {
        let id: String
        let revision: Int
        let connection: QuranConnection
        let texts: [Int: String]
        let indexed: Bool
    }

    private var recentSearches: [(SearchKey, [Ayah])] = []
    private var cachedCatalog: Catalog?
    private var corpus: Corpus?
    private var translationCorpus: TranslationCorpus?
    /// "Load more" slices this ranked list instead of searching again.
    private var ranked: (key: RankKey, ids: [Int])?
    private(set) var relatedIDs: Set<String> = []

    /// Shared by the Quran list and the readers it opens, so their caches stay warm across screens.
    static let shared = QuranReader()

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
        let parsed = try references.compactMap { try QuranSearchText.reference($0) }
        guard !parsed.isEmpty else { return [] }
        // One read for every reference instead of a database round trip per verse.
        let condition = parsed.map { _ in "(sura = ? AND aya = ?)" }.joined(separator: " OR ")
        return try database.readVerses(where: condition, parameters: parsed.flatMap { [String($0.surah), String($0.verse)] }).map(\.1)
    }

    /// Compact search previews prepared off the main actor, keyed by verse ID.
    func highlights(_ verses: [Ayah], query: String, translationID: String?) throws -> [String: QuranSearchHighlight] {
        var result: [String: QuranSearchHighlight] = [:]
        for ayah in verses {
            try Task.checkCancellation()
            let arabic = SearchMatch.text(ayah.text, query: query)
            let translation = SearchMatch.text(translationID.flatMap { ayah.translations[$0] } ?? "", query: query)
            result[ayah.id] = QuranSearchHighlight(arabic: SearchMatch.preview(arabic, compact: true),
                                                   translation: SearchMatch.preview(translation, compact: true))
        }
        return result
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
        let result = try performSearch(query, translationID: translationID, limit: limit, surah: surah, revision: revision)
        if limit <= 201 {
            recentSearches.append((key, result))
            if recentSearches.count > 8 {
                recentSearches.removeFirst()
            }
        }
        return result
    }

    private func performSearch(_ query: String, translationID: String?, limit: Int, surah: Int?, revision: Int) throws -> [Ayah] {
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
        let terms = QuranSearchText.queryTerms(query)
        guard !terms.isEmpty else { return [] }
        let key = RankKey(query: query, translationID: translationID, surah: surah, revision: revision)
        let ids: [Int]
        if let ranked, ranked.key == key {
            ids = ranked.ids
        } else {
            ids = try rankedIDs(terms, translationID: translationID, surah: surah, revision: revision)
            ranked = (key, ids)
        }
        let page = ids.prefix(max(0, limit)).map(String.init)
        guard !page.isEmpty else { return [] }
        let verses = try Dictionary(uniqueKeysWithValues: database.readVerses(where: "\"index\" IN (\(page.map { _ in "?" }.joined(separator: ",")))", parameters: page))
        return page.compactMap { Int($0).flatMap { verses[$0] } }
    }

    /// Exact phrases, then all-word matches; Arabic wins ties between languages.
    private func rankedIDs(_ terms: [String], translationID: String?, surah: Int?, revision: Int) throws -> [Int] {
        let arabicCorpus = try loadCorpus()
        // Typed spellings are matched to the mushaf's only for the Arabic text; translations keep what was typed.
        let arabicTerms = arabicCorpus.vocabulary.map { QuranSpelling.resolve(terms, in: $0) } ?? terms
        let arabic = try rank(matches(arabicTerms, in: arabicCorpus.connection, indexed: arabicCorpus.indexed, texts: arabicCorpus.texts), terms: arabicTerms, texts: arabicCorpus.texts)
        var translated = [[Int]](repeating: [], count: 2)
        if let translationID {
            // Optional assets can disappear or be invalid; Arabic search must still work.
            do {
                if let translation = try loadTranslation(translationID, revision: revision) {
                    translated = try rank(matches(terms, in: translation.connection, indexed: translation.indexed, texts: translation.texts), terms: terms, texts: translation.texts)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep Arabic results when a translation cannot be read.
            }
        }
        var seen = Set<Int>()
        return (0 ... 1).flatMap { arabic[$0] + translated[$0] }.filter { id in
            arabicCorpus.searchable.contains(id) && (surah == nil || arabicCorpus.surahs[id] == surah) && seen.insert(id).inserted
        }
    }

    private func loadCorpus() throws -> Corpus {
        if let corpus {
            return corpus
        }
        let connection = try database.connection()
        var texts: [Int: String] = [:]
        var surahs: [Int: Int] = [:]
        var searchable = Set<Int>()
        for (id, surah, text) in try connection.query("SELECT \"index\", sura, text FROM quran", row: {
            (Int(sqlite3_column_int($0, 0)), Int(sqlite3_column_int($0, 1)), QuranConnection.text($0, 2))
        }) {
            try Task.checkCancellation()
            texts[id] = text
            surahs[id] = surah
            if QuranSearchText.isSearchableVerse(text) {
                searchable.insert(id)
            }
        }
        let indexed = try Self.hasIndex(connection)
        let value = Corpus(connection: connection, texts: texts, surahs: surahs, searchable: searchable, indexed: indexed,
                           vocabulary: indexed ? try? Self.vocabulary(connection) : nil)
        corpus = value
        return value
    }

    private func loadTranslation(_ id: String, revision: Int) throws -> TranslationCorpus? {
        if let translationCorpus, translationCorpus.id == id, translationCorpus.revision == revision {
            return translationCorpus
        }
        translationCorpus = nil
        guard let translation = try database.availableTranslations().first(where: { $0.id == id }) else { return nil }
        let connection = try database.connection(to: translation)
        let texts = try Dictionary(connection.query("SELECT \"index\", text FROM quran") {
            (Int(sqlite3_column_int($0, 0)), QuranConnection.text($0, 1))
        }, uniquingKeysWith: { first, _ in first })
        let value = try TranslationCorpus(id: id, revision: revision, connection: connection, texts: texts, indexed: Self.hasIndex(connection))
        translationCorpus = value
        return value
    }

    private static func vocabulary(_ connection: QuranConnection) throws -> QuranVocabulary {
        try QuranVocabulary(connection.query("SELECT term, doc FROM quran_words_vocab") {
            (QuranConnection.text($0, 0), Int(sqlite3_column_int($0, 1)))
        })
    }

    private static func hasIndex(_ connection: QuranConnection) throws -> Bool {
        try !connection.query("SELECT name FROM sqlite_master WHERE name='quran_words'") { QuranConnection.text($0, 0) }.isEmpty
    }

    private func rank(_ ids: [Int], terms: [String], texts: [Int: String]) throws -> [[Int]] {
        guard !ids.isEmpty else { return [[], []] }
        var groups = [[(Int, SearchRelevance)]](repeating: [], count: 2)
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

    /// Basic offline retrieval uses one word index, including one- and two-letter words; the last word matches as a prefix.
    private func matches(_ terms: [String], in database: QuranConnection, indexed: Bool, texts: [Int: String]) throws -> [Int] {
        if indexed {
            return try database.query("SELECT rowid FROM quran_words WHERE quran_words MATCH ? ORDER BY rowid", parameters: [QuranSearchText.ftsQuery(terms, column: "text").words]) {
                Int(sqlite3_column_int($0, 0))
            }
        }
        // Chinese translations have no whitespace word index; their 6,236 rows use literal matching.
        return try texts.keys.sorted().filter { id in
            try Task.checkCancellation()
            return QuranSearchText.literalRank(texts[id] ?? "", terms: terms) < 2
        }
    }
}

struct QuranSearchHighlight: Sendable {
    let arabic: AttributedString
    let translation: AttributedString
}

import Foundation
import SQLite3

actor DictionaryReader: LibraryPackReader {
    static let sources = ["القاموس المحيط", "الفائق في غريب الحديث", "الصحاح", "النهاية في غريب الحديث والأثر", "لسان العرب", "تهذيب اللغة"]
    private var db: SQLiteConnection?
    /// Every dictionary heading with how many sources define it, loaded the first time a word needs suggestions.
    private var headings: [(root: String, letters: String, sources: Int)]?

    func install(_ url: URL?) throws {
        db = nil
        headings = nil
        guard let url else { return }
        let connection = try SQLiteConnection(path: url.path, flags: SQLITE_OPEN_READONLY, failure: HadithDatabaseError.unavailable)
        guard try connection.query("pragma user_version", row: { sqlite3_column_int($0, 0) }) == [1],
              try connection.query("pragma quick_check", row: { SQLiteConnection.text($0, 0) }) == ["ok"],
              try connection.query("select root from words where spelling='الكتاب' order by rank limit 1", row: { SQLiteConnection.text($0, 0) }) == ["كتب"],
              try !connection.query("select 1 from family limit 1", row: { sqlite3_column_int($0, 0) }).isEmpty,
              try !connection.query("select 1 from rootless limit 1", row: { sqlite3_column_int($0, 0) }).isEmpty
        else { throw HadithDatabaseError.incompatible }
        db = connection
    }

    func replace(_ destination: URL, with staged: URL) throws {
        db = nil
        headings = nil
        guard rename(staged.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try install(destination)
    }

    /// Roots for one word, best first. A phrase has no root of its own; its words are looked up one at a time.
    func search(_ text: String) throws -> [String] {
        guard let db else { throw HadithDatabaseError.unavailable }
        let words = text.split(whereSeparator: \.isWhitespace).map { Self.spell(String($0)) }.filter { !$0.isEmpty }
        return words.count == 1 ? try roots(for: words[0], in: db) : []
    }

    /// The pack ranks roots for every word the lexicons list and every word in the app's text
    /// (see shared/lexicon/build.py), and lists the ones it found none for. Other selections, such
    /// as part of a word, retry without clitics.
    private func roots(for word: String, in db: SQLiteConnection) throws -> [String] {
        let checked = try !db.query("SELECT 1 FROM rootless WHERE spelling=?", parameters: [word]) { sqlite3_column_int($0, 0) }.isEmpty
        for stem in checked ? [] : [word] + Self.stems(of: word) {
            let exact = try db.query("SELECT root FROM words WHERE spelling=? ORDER BY rank", parameters: [stem]) { SQLiteConnection.text($0, 0) }
            if !exact.isEmpty {
                return exact
            }
            let folded = try db.query("""
            SELECT root FROM words WHERE norm=? GROUP BY root ORDER BY min(rank), count(*) DESC, root LIMIT 4
            """, parameters: [Self.normalize(stem)]) { SQLiteConnection.text($0, 0) }
            if !folded.isEmpty {
                return folded
            }
        }
        return []
    }

    struct Definition: Identifiable {
        let id: Int64
        let source: Int
        /// The heading this source files the definition under, which can be another spelling of the root (سمو for سما).
        let root: String
        let body: String
    }

    func entry(_ root: String) throws -> [Definition] {
        guard let db else { throw HadithDatabaseError.unavailable }
        return try db.query("""
        SELECT rowid,source,root,body FROM entries WHERE root=?1 OR root IN (SELECT member FROM family WHERE root=?1)
        ORDER BY source, root<>?1, root
        """, parameters: [root]) {
            Definition(id: sqlite3_column_int64($0, 0), source: Int(sqlite3_column_int($0, 1)), root: SQLiteConnection.text($0, 2), body: SQLiteConnection.text($0, 3))
        }
    }

    /// Headings whose letters appear in order in the word, for `DictionaryRootSuggester` to choose
    /// from when lookup finds nothing. A root's weak letters and hamza may be absent from the word
    /// (قال, وعد -> عد), but at least two other letters must be there. Most-documented roots first.
    func candidateRoots(for word: String, limit: Int = 40) throws -> [String] {
        guard let db else { throw HadithDatabaseError.unavailable }
        let headings = try headings ?? db.query("SELECT root, count(*) FROM entries GROUP BY root") {
            let root = SQLiteConnection.text($0, 0)
            return (root: root, letters: Self.normalize(root), sources: Int(sqlite3_column_int($0, 1)))
        }
        self.headings = headings
        let letters = Array(Self.normalize(word))
        guard letters.count >= 3 else { return [] }
        let matches = headings.compactMap { heading -> (root: String, complete: Bool, sources: Int)? in
            let root = Array(heading.letters)
            guard (2 ... 4).contains(root.count) else { return nil }
            let strong = root.filter { !"اويء".contains($0) }
            guard strong.count >= 2, Self.appears(strong, in: letters) else { return nil }
            return (heading.root, Self.appears(root, in: letters), heading.sources)
        }
        return matches.sorted { ($0.complete ? 1 : 0, $0.sources, $1.root) > ($1.complete ? 1 : 0, $1.sources, $0.root) }
            .prefix(limit).map(\.root)
    }

    private static func appears(_ letters: [Character], in word: [Character]) -> Bool {
        var remaining = word[...]
        for letter in letters {
            guard let index = remaining.firstIndex(of: letter) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }
}

extension DictionaryReader {
    // Ports of shared/lexicon/normalize.py; shared/fixtures/lexicon-normalize.json holds the cases they must agree on.
    private static let marks = "[\u{0610}-\u{061A}\u{0640}\u{064B}-\u{0670}\u{06D6}-\u{06ED}]"
    private static let nonLetters = "[^\u{0621}-\u{063A}\u{0641}-\u{064A}\u{0671}\u{06A9}\u{06CC}]"
    private static let spelling: [Character: Character] = ["ٱ": "ا", "ة": "ه", "ک": "ك", "ی": "ي"]
    private static let hamza: [Character: Character] = ["أ": "ا", "إ": "ا", "آ": "ا", "ى": "ي", "ؤ": "و", "ئ": "ي"]

    /// A word as the pack's `words.spelling` keys it: no vowels or marks, standard spelling for
    /// Uthmani forms, hamza seats kept.
    static func spell(_ text: String) -> String {
        String(letters(text).replacingOccurrences(of: nonLetters, with: "", options: .regularExpression).map { spelling[$0] ?? $0 })
    }

    /// `spell` with hamza seats and alef maqsura folded, as `words.norm` keys it.
    static func normalize(_ text: String) -> String {
        String(spell(text).map { hamza[$0] ?? $0 })
    }

    private static func letters(_ text: String) -> String {
        // Uthmani: alef maqsura carrying a superscript alef is just the maqsura; any other
        // superscript alef is a written alef (السمٰوٰت -> السماوات), and ءا is آ (ءامن، قرءان).
        let text = text.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "ىٰ", with: "ى")
            .replacingOccurrences(of: "\u{0670}", with: "ا")
        return text.replacingOccurrences(of: marks, with: "", options: .regularExpression)
            .replacingOccurrences(of: "ءا(?=\\w)", with: "آ", options: .regularExpression)
    }

    /// Readings of a word with its clitics removed, longest first: conjunction, preposition or
    /// article in front, pronoun behind. The article never takes a pronoun, and stems keep three letters.
    static func stems(of word: String) -> [String] {
        var found: [String] = []
        for conjunction in ["", "و", "ف"] where word.hasPrefix(conjunction) {
            let rest = word.dropFirst(conjunction.count)
            for attached in ["", "ب", "ك", "ل", "ال", "بال", "كال", "لل"] where rest.hasPrefix(attached) {
                var stem = String(rest.dropFirst(attached.count))
                // ل before the article drops its alef: للذين = ل + الذين.
                if attached == "لل" {
                    stem = "ال" + stem
                } else if attached.hasSuffix("ال"), stem.hasPrefix("ال") {
                    continue
                }
                if !conjunction.isEmpty || !attached.isEmpty {
                    found.append(stem)
                }
                guard !attached.hasSuffix("ال"), attached != "لل", !stem.hasPrefix("ال") else { continue }
                for pronoun in ["ه", "ها", "هما", "هم", "هن", "ك", "كما", "كم", "كن", "ي", "نا", "ني"] where stem.hasSuffix(pronoun) {
                    found.append(String(stem.dropLast(pronoun.count)))
                }
            }
        }
        var seen: Set<String> = []
        return found.filter { $0.count >= 3 && seen.insert($0).inserted }.sorted { $0.count > $1.count }
    }
}

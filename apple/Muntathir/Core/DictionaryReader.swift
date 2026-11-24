import Foundation
import SQLite3

actor DictionaryReader: LibraryPackReader {
    static let sources = ["القاموس المحيط", "الفائق في غريب الحديث", "الصحاح", "النهاية في غريب الحديث والأثر", "لسان العرب", "تهذيب اللغة"]
    private var db: SQLiteConnection?

    func install(_ url: URL?) throws {
        db = nil
        guard let url else { return }
        let connection = try SQLiteConnection(path: url.path, flags: SQLITE_OPEN_READONLY, failure: HadithDatabaseError.unavailable)
        guard try connection.query("pragma user_version", row: { sqlite3_column_int($0, 0) }) == [1],
              try connection.query("pragma quick_check", row: { SQLiteConnection.text($0, 0) }) == ["ok"],
              try !connection.query("select source from entries where root='كتب' limit 1", row: { sqlite3_column_int($0, 0) }).isEmpty,
              try !connection.query("select rowid from passages where passages match 'كتاب' limit 1", row: { sqlite3_column_int64($0, 0) }).isEmpty
        else { throw HadithDatabaseError.incompatible }
        db = connection
    }

    func replace(_ destination: URL, with staged: URL) throws {
        db = nil
        guard rename(staged.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try install(destination)
    }

    struct Passage: Hashable {
        let root: String
        let source: Int
        let preview: String
    }

    struct Matches {
        var roots: [String] = []
        var passages: [Passage] = []
    }

    func search(_ text: String) throws -> Matches {
        guard let db else { throw HadithDatabaseError.unavailable }
        let norm = text.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "[ؐ-ؚـً-ٰٟۖ-ۭ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[أإآٱ]", with: "ا", options: .regularExpression)
            .replacingOccurrences(of: "[ىئ]", with: "ي", options: .regularExpression)
            .replacingOccurrences(of: "ؤ", with: "و")
        guard !norm.isEmpty else { return Matches() }
        let roots = try db.query("""
        SELECT root FROM (SELECT root,0 priority FROM forms WHERE form=? UNION ALL SELECT root,1 FROM forms WHERE norm=?) AS root_candidate
        WHERE EXISTS (SELECT 1 FROM entries WHERE entries.root=root_candidate.root)
        GROUP BY root ORDER BY min(priority),root
        """, parameters: [text, norm]) { SQLiteConnection.text($0, 0) }
        let phrase = "\"" + norm.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let passages = try db.query("""
        SELECT e.root,e.source,snippet(passages,0,'','','…',18) FROM passages JOIN entries e ON e.rowid=passages.rowid
        WHERE passages MATCH ? ORDER BY rank LIMIT 100
        """, parameters: [phrase]) { Passage(root: SQLiteConnection.text($0, 0), source: Int(sqlite3_column_int($0, 1)), preview: SQLiteConnection.text($0, 2)) }
        return Matches(roots: roots, passages: passages)
    }

    struct Definition: Identifiable {
        let id: Int
        let body: String
    }

    func entry(_ root: String) throws -> [Definition] {
        guard let db else { throw HadithDatabaseError.unavailable }
        return try db.query("SELECT source,body FROM entries WHERE root=? ORDER BY source", parameters: [root]) {
            Definition(id: Int(sqlite3_column_int($0, 0)), body: SQLiteConnection.text($0, 1))
        }
    }
}

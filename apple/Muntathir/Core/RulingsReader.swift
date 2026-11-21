import Foundation
import SQLite3

struct Rulings: Identifiable, Sendable {
    struct ID: Codable, Hashable, Sendable {
        let authority: String
        let language: String
        let siteID: String
    }

    let id: ID
    let question: String
    let answer: String
    let source: URL?
    var context = ""
    var kind = "qa"
    var preview: String {
        kind == "qa" ? question : question + " · " + answer.prefix(160)
    }
}

struct RulingFootnote: Identifiable, Sendable {
    let id: Int64
    let label: String
    let body: String
    let chapter: Bool
}

struct RulingsAuthority: Identifiable, Sendable {
    let id: String
    let arabic: String
    let english: String
}

struct RulingsLanguage: Identifiable, Sendable {
    let id: String
    let name: String
    let rightToLeft: Bool
}

struct RulingsSection: Identifiable, Sendable {
    let id: Int64
    let title: String
}

actor RulingsReader {
    private var version: Int32 = 1
    private var columns: String {
        "q.authority_code, q.language_code, q.site_id, q.question, q.answer, q.url" + (version == 2 ? ", q.context, q.kind" : "")
    }

    private var database: HadithConnection?

    func install(_ url: URL?) throws {
        database = nil
        if let url {
            let db = try HadithConnection(url: url)
            version = try db.query("PRAGMA user_version") { sqlite3_column_int($0, 0) }.first ?? 0
            guard try db.query("PRAGMA application_id", row: { sqlite3_column_int($0, 0) }).first == 1_179_809_601,
                  [1, 2].contains(version)
            else {
                throw HadithDatabaseError.incompatible
            }
            guard try db.query("PRAGMA quick_check", row: { Self.text($0, 0) }) == ["ok"],
                  try db.query("PRAGMA foreign_key_check", row: { Self.text($0, 0) }).isEmpty
            else {
                throw HadithDatabaseError.incompatible
            }
            _ = try db.query("SELECT code, name_ar, name_en, sort_order FROM authority LIMIT 1") { Self.text($0, 0) }
            _ = try db.query("SELECT code, name, direction FROM language LIMIT 1") { Self.text($0, 0) }
            _ = try db.query("SELECT id, title, parent_id FROM topic LIMIT 1") { Self.text($0, 0) }
            _ = try db.query("SELECT topic_id, question_id, position FROM placement LIMIT 1") { Self.text($0, 0) }
            _ = try db.query("SELECT authority_code, language_code, site_id, question, answer, url FROM question LIMIT 1") { Self.text($0, 0) }
            _ = try db.query("SELECT rowid FROM question_fts WHERE question_fts MATCH ? LIMIT 1", parameters: ["test"]) { sqlite3_column_int64($0, 0) }
            _ = try db.query("SELECT \(columns) FROM question q LIMIT 0", row: Self.rulings)
            database = db
        }
    }

    private func connection() throws -> HadithConnection {
        guard let database else { throw HadithDatabaseError.unavailable }
        return database
    }

    func authorities() throws -> [RulingsAuthority] {
        try connection().query("SELECT code, name_ar, name_en FROM authority ORDER BY sort_order") {
            RulingsAuthority(id: Self.text($0, 0), arabic: Self.text($0, 1), english: Self.text($0, 2))
        }
    }

    func languages(authority: String) throws -> [RulingsLanguage] {
        try connection().query("SELECT code, name, direction FROM language WHERE code IN (SELECT DISTINCT language_code FROM question WHERE authority_code = ?) ORDER BY code", parameters: [authority]) {
            RulingsLanguage(id: Self.text($0, 0), name: Self.text($0, 1), rightToLeft: Self.text($0, 2) == "rtl")
        }
    }

    /// The number of questions in each of an authority's languages, keyed by language code.
    func questionCounts(authority: String) throws -> [String: Int] {
        let rows = try connection().query("SELECT language_code, COUNT(*) FROM question WHERE authority_code = ? GROUP BY language_code", parameters: [authority]) {
            (Self.text($0, 0), Int(sqlite3_column_int64($0, 1)))
        }
        return Dictionary(rows, uniquingKeysWith: { first, _ in first })
    }

    static func preferredLanguage(saved: String?, locale: String, available: [RulingsLanguage]) -> String? {
        if let saved, available.contains(where: { $0.id == saved }) {
            return saved
        }
        let code = Locale(identifier: locale).language.languageCode?.identifier
        return available.first(where: { $0.id == code })?.id
    }

    func contents(authority: String, language: String, parent: Int64? = nil) throws -> [RulingsSection] {
        let db = try connection()
        func children(_ parent: Int64?) throws -> [RulingsSection] {
            try db.query("SELECT id,title FROM topic WHERE authority_code=? AND language_code=? AND " +
                (parent == nil ? "parent_id IS NULL" : "parent_id=?") + " ORDER BY position,id",
                parameters: [authority, language] + (parent.map { [String($0)] } ?? []))
            {
                RulingsSection(id: sqlite3_column_int64($0, 0), title: Self.text($0, 1))
            }
        }
        let sections = try children(parent)
        if version == 2, parent == nil, sections.count == 1 {
            return try children(sections[0].id)
        }
        return sections
    }

    func footnotes(for id: Rulings.ID) throws -> [RulingFootnote] {
        let db = try connection()
        guard try !db.query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='footnote'", row: { _ in true }).isEmpty else { return [] }
        return try db.query("""
        SELECT f.rowid,f.label,f.body,f.entry_id IS NULL FROM entry e
        JOIN placement p ON p.question_id=e.id JOIN footnote f ON f.topic_id=p.topic_id
        WHERE e.authority_code=? AND e.language_code=? AND e.site_id=?
          AND (f.entry_id=e.id OR f.entry_id IS NULL) ORDER BY f.rowid
        """, parameters: [id.authority, id.language, id.siteID]) {
            RulingFootnote(id: sqlite3_column_int64($0, 0), label: Self.text($0, 1),
                           body: Self.text($0, 2), chapter: sqlite3_column_int($0, 3) != 0)
        }
    }

    func sections(for id: Rulings.ID) throws -> [RulingsSection] {
        if version == 2 {
            return try connection().query("""
            SELECT t.id,t.title FROM topic t JOIN placement p ON p.topic_id=t.id JOIN question q ON q.id=p.question_id
            WHERE q.authority_code=? AND q.language_code=? AND q.site_id=? ORDER BY t.position,t.id
            """, parameters: [id.authority, id.language, id.siteID]) {
                RulingsSection(id: sqlite3_column_int64($0, 0), title: Self.text($0, 1))
            }
        }
        // Resolve nested topics in legacy packs to their main sections.
        return try connection().query("""
        WITH RECURSIVE sections(id, parent_id, title, position) AS (
            SELECT t.id, t.parent_id, t.title, t.position FROM topic t
            JOIN placement p ON p.topic_id = t.id
            JOIN question q ON q.id = p.question_id
            WHERE q.authority_code = ?1 AND q.language_code = ?2 AND q.site_id = ?3
              AND t.authority_code = ?1 AND t.language_code = ?2
            UNION
            SELECT t.id, t.parent_id, t.title, t.position FROM topic t
            JOIN sections s ON s.parent_id = t.id
            WHERE t.authority_code = ?1 AND t.language_code = ?2
        )
        SELECT id, title FROM sections WHERE parent_id IS NULL ORDER BY position, id
        """, parameters: [id.authority, id.language, id.siteID]) {
            RulingsSection(id: sqlite3_column_int64($0, 0), title: Self.text($0, 1))
        }
    }

    func questions(authority: String, language: String, section: RulingsSection) throws -> [Rulings] {
        try connection().query("""
        WITH RECURSIVE sections(id) AS (
            SELECT id FROM topic WHERE authority_code = ?1 AND language_code = ?2 AND id = ?3
            UNION
            SELECT t.id FROM topic t JOIN sections s ON t.parent_id = s.id
            WHERE t.authority_code = ?1 AND t.language_code = ?2 AND \(version == 1 ? "1" : "0")
        )
        SELECT \(columns)
        FROM question q JOIN placement p ON p.question_id = q.id JOIN sections s ON s.id = p.topic_id
        WHERE q.authority_code = ?1 AND q.language_code = ?2
        GROUP BY q.id ORDER BY MIN(p.position), q.site_id
        """, parameters: [authority, language, String(section.id)], row: Self.rulings)
    }

    func questions(authority: String, language: String, query: String = "") throws -> [Rulings] {
        let terms = QuranSearchText.searchQuery(query).split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var sql = "SELECT \(columns) FROM question q"
        var parameters: [String] = []
        if !terms.isEmpty {
            sql += " JOIN question_fts f ON f.rowid = q.id"
        }
        sql += " WHERE q.authority_code = ? AND q.language_code = ?"
        parameters += [authority, language]
        if terms.isEmpty {
            sql += " ORDER BY random() LIMIT 20"
        } else {
            sql += " AND question_fts MATCH ? ORDER BY bm25(question_fts), q.site_id LIMIT 100"
            parameters.append(terms.joined(separator: " AND "))
        }
        return try connection().query(sql, parameters: parameters, row: Self.rulings)
    }

    func question(_ id: Rulings.ID) throws -> Rulings? {
        try connection().query("SELECT \(columns) FROM question q WHERE authority_code = ? AND language_code = ? AND site_id = ?", parameters: [id.authority, id.language, id.siteID], row: Self.rulings).first
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private static func rulings(_ statement: OpaquePointer) -> Rulings {
        let url = URL(string: text(statement, 5))
        return Rulings(id: .init(authority: text(statement, 0), language: text(statement, 1), siteID: text(statement, 2)), question: text(statement, 3), answer: text(statement, 4), source: url.flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil }, context: sqlite3_column_count(statement) > 6 ? text(statement, 6) : "", kind: sqlite3_column_count(statement) > 7 ? text(statement, 7) : "qa")
    }
}

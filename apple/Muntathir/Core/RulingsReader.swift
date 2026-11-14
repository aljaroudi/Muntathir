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

struct RulingsTopic: Identifiable, Sendable {
    let id: Int
    let title: String
    let parent: Int?
}

actor RulingsReader {
    private var database: HadithConnection?

    func install(_ url: URL?) throws {
        database = nil
        if let url {
            let db = try HadithConnection(url: url)
            guard try db.query("PRAGMA application_id", row: { sqlite3_column_int($0, 0) }).first == 1_179_809_601,
                  try db.query("PRAGMA user_version", row: { sqlite3_column_int($0, 0) }).first == 1
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

    static func preferredLanguage(saved: String?, locale: String, available: [RulingsLanguage]) -> String? {
        if let saved, available.contains(where: { $0.id == saved }) {
            return saved
        }
        let code = Locale(identifier: locale).language.languageCode?.identifier
        return available.first(where: { $0.id == code })?.id
    }

    func topics(authority: String, language: String) throws -> [RulingsTopic] {
        try connection().query("SELECT id, title, parent_id FROM topic WHERE authority_code = ? AND language_code = ? ORDER BY position, id", parameters: [authority, language]) {
            RulingsTopic(id: Int(sqlite3_column_int64($0, 0)), title: Self.text($0, 1), parent: sqlite3_column_type($0, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int64($0, 2)))
        }
    }

    func questions(authority: String, language: String, query: String = "", topic: Int? = nil) throws -> [Rulings] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var sql = "SELECT q.authority_code, q.language_code, q.site_id, q.question, q.answer, q.url FROM question q"
        var parameters: [String] = []
        if !terms.isEmpty {
            sql += " JOIN question_fts f ON f.rowid = q.id"
        }
        if topic != nil {
            sql += " JOIN placement p ON p.question_id = q.id"
        }
        sql += " WHERE q.authority_code = ? AND q.language_code = ?"
        parameters += [authority, language]
        if let topic {
            sql += " AND p.topic_id = ?"; parameters.append(String(topic))
        }
        if !terms.isEmpty {
            sql += " AND question_fts MATCH ?"; parameters.append(terms.joined(separator: " AND "))
        }
        sql += terms.isEmpty ? " ORDER BY \(topic == nil ? "q.site_id" : "p.position")" : " ORDER BY bm25(question_fts), q.site_id"
        // shortcut: search shows the best 100 matches; add paging if users need deeper results.
        if !terms.isEmpty {
            sql += " LIMIT 100"
        }
        return try connection().query(sql, parameters: parameters, row: Self.rulings)
    }

    func question(_ id: Rulings.ID) throws -> Rulings? {
        try connection().query("SELECT authority_code, language_code, site_id, question, answer, url FROM question WHERE authority_code = ? AND language_code = ? AND site_id = ?", parameters: [id.authority, id.language, id.siteID], row: Self.rulings).first
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private static func rulings(_ statement: OpaquePointer) -> Rulings {
        let url = URL(string: text(statement, 5))
        return Rulings(id: .init(authority: text(statement, 0), language: text(statement, 1), siteID: text(statement, 2)), question: text(statement, 3), answer: text(statement, 4), source: url.flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil })
    }
}

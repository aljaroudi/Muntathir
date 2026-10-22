import Foundation
import SQLite3

/// Each lookup opens the bundled database read-only; no SQLite connection crosses isolation boundaries.
struct QuranDatabase: Sendable {
    let url: URL?

    func connection() throws -> QuranConnection {
        guard let url else { throw QuranDatabaseError.unavailable }
        return try QuranConnection(path: url.path, flags: SQLITE_OPEN_READONLY)
    }

    func availableTranslations() throws -> [QuranTranslation] {
        try availableTranslations(in: connection())
    }

    private func availableTranslations(in database: QuranConnection) throws -> [QuranTranslation] {
        let columns = try database.query("PRAGMA table_info(quran)") { QuranConnection.text($0, 1) }
        guard columns.contains("text"), columns.contains("sura"), columns.contains("aya") else {
            throw QuranDatabaseError.unavailable
        }
        return QuranTranslation.catalog.filter { columns.contains($0.column) }
    }

    func chapterCounts() throws -> [Int: Int] {
        let rows = try connection().query("SELECT sura, count(*) FROM quran GROUP BY sura ORDER BY sura") {
            (Int(sqlite3_column_int($0, 0)), Int(sqlite3_column_int($0, 1)))
        }
        return Dictionary(uniqueKeysWithValues: rows)
    }

    func verses(ids: Set<Int>) -> [Int: Ayah] {
        guard !ids.isEmpty else { return [:] }
        return (try? records(ids: ids)) ?? [:]
    }

    private func records(ids: Set<Int>) throws -> [Int: Ayah] {
        let ids = ids.filter { $0 > 0 }.sorted()
        guard !ids.isEmpty else { return [:] }
        let rows = try readVerses(where: "\"index\" IN (\(ids.map { _ in "?" }.joined(separator: ",")))", parameters: ids.map(String.init))
        return Dictionary(uniqueKeysWithValues: rows)
    }

    func verses(surah: Int) throws -> [Ayah] {
        try readVerses(where: "sura = ?", parameters: [String(surah)]).map(\.1)
    }

    func verse(surah: Int, number: Int) throws -> Ayah? {
        try readVerses(where: "sura = ? AND aya = ?", parameters: [String(surah), String(number)]).first?.1
    }

    func readVerses(where condition: String, parameters: [String], limit: Int? = nil) throws -> [(Int, Ayah)] {
        let database = try connection()
        let translations = try availableTranslations(in: database)
        let columns = (["\"index\"", "sura", "aya", "text"] + translations.map { "\"\($0.column)\"" }).joined(separator: ", ")
        let suffix = limit.map { " LIMIT \(max(0, $0))" } ?? ""
        return try database.query("SELECT \(columns) FROM quran WHERE \(condition) ORDER BY sura, aya\(suffix)", parameters: parameters) { row in
            let text = QuranConnection.text(row, 3)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuranDatabaseError.unavailable }
            var values: [String: String] = [:]
            for (offset, translation) in translations.enumerated() {
                let value = QuranConnection.text(row, Int32(offset + 4))
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    values[translation.id] = value
                }
            }
            return (Int(sqlite3_column_int(row, 0)), Ayah(surah: Int(sqlite3_column_int(row, 1)), number: Int(sqlite3_column_int(row, 2)), text: text, translations: values))
        }
    }
}

enum QuranDatabaseError: Error {
    case unavailable
    case invalidReference
}

/// Owned locally by a synchronous lookup, or exclusively by the search actor.
final class QuranConnection {
    private let handle: OpaquePointer

    init(path: String, flags: Int32) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(path, &pointer, flags, nil) == SQLITE_OK, let pointer else {
            if let pointer {
                sqlite3_close(pointer)
            }
            throw QuranDatabaseError.unavailable
        }
        handle = pointer
    }

    deinit { sqlite3_close(handle) }

    func query<T>(_ sql: String, parameters: [String] = [], row: (OpaquePointer) throws -> T) throws -> [T] {
        try Task.checkCancellation()
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
            throw QuranDatabaseError.unavailable
        }
        defer { sqlite3_finalize(pointer) }
        for (offset, parameter) in parameters.enumerated() {
            let status = parameter.withCString { sqlite3_bind_text(pointer, Int32(offset + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard status == SQLITE_OK else { throw QuranDatabaseError.unavailable }
        }
        var result: [T] = []
        while true {
            try Task.checkCancellation()
            switch sqlite3_step(pointer) {
            case SQLITE_ROW: try result.append(row(pointer))
            case SQLITE_DONE: return result
            default: throw QuranDatabaseError.unavailable
            }
        }
    }

    func execute(_ sql: String, parameters: [String] = []) throws {
        _ = try query(sql, parameters: parameters) { _ in () }
    }

    static func text(_ row: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(row, column).map { String(cString: $0) } ?? ""
    }
}

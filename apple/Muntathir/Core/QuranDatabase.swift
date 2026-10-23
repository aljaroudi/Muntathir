import Foundation
import SQLite3

/// Each lookup opens the databases read-only; no SQLite connection crosses isolation boundaries.
struct QuranDatabase: Sendable {
    /// Arabic is always bundled. An optional resolver supplies installed translations.
    let url: URL?

    private let translationURLs: (@Sendable () -> [String: URL])?

    init(url: URL?, translationURLs: @escaping @Sendable () -> [String: URL] = { [:] }) {
        self.url = url
        self.translationURLs = translationURLs
    }

    init(bundle: Bundle = .main) {
        url = bundle.url(forResource: "quran", withExtension: "db")
        translationURLs = nil
    }

    func connection() throws -> QuranConnection {
        guard let url else { throw QuranDatabaseError.unavailable }
        return try QuranConnection(path: url.path, flags: SQLITE_OPEN_READONLY)
    }

    private var installedURLs: [String: URL] {
        if let translationURLs {
            return translationURLs()
        }
        guard let translation = QuranTranslationPreferences.selected,
              let url = try? QuranTranslationPreferences.url(for: translation) else { return [:] }
        return [translation.id: url]
    }

    func connection(to translation: QuranTranslation) throws -> QuranConnection {
        guard let url = installedURLs[translation.id] else { throw QuranDatabaseError.unavailable }
        return try QuranConnection(path: url.path, flags: SQLITE_OPEN_READONLY)
    }

    func availableTranslations() throws -> [QuranTranslation] {
        let urls = installedURLs
        return QuranTranslation.catalog.filter { translation in
            guard let url = urls[translation.id] else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    static func validateTranslation(at url: URL) throws {
        let connection = try QuranConnection(path: url.path, flags: SQLITE_OPEN_READONLY)
        let count = try connection.query("SELECT count(*), min(\"index\"), max(\"index\") FROM quran WHERE trim(text) != ''") {
            (sqlite3_column_int($0, 0), sqlite3_column_int($0, 1), sqlite3_column_int($0, 2))
        }.first
        guard let count, count == (6236, 1, 6236) else { throw QuranDatabaseError.unavailable }
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
        let suffix = limit.map { " LIMIT \(max(0, $0))" } ?? ""
        var rows = try connection().query("SELECT \"index\", sura, aya, text FROM quran WHERE \(condition) ORDER BY sura, aya\(suffix)", parameters: parameters) { row in
            let text = QuranConnection.text(row, 3)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuranDatabaseError.unavailable }
            return (Int(sqlite3_column_int(row, 0)), Ayah(surah: Int(sqlite3_column_int(row, 1)), number: Int(sqlite3_column_int(row, 2)), text: text))
        }
        guard !rows.isEmpty else { return rows }
        let ids = rows.map { String($0.0) }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        for translation in try availableTranslations() {
            let values = (try? Dictionary(uniqueKeysWithValues: connection(to: translation).query("SELECT \"index\", text FROM quran WHERE \"index\" IN (\(placeholders))", parameters: ids) {
                (Int(sqlite3_column_int($0, 0)), QuranConnection.text($0, 1))
            })) ?? [:]
            try Task.checkCancellation()
            for offset in rows.indices {
                if let value = values[rows[offset].0], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    rows[offset].1.translations[translation.id] = value
                }
            }
        }
        return rows
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

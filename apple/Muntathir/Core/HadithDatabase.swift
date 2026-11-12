import Foundation
import OSLog
import SQLite3

struct HadithDatabase: Sendable {
    let url: URL?

    init(url: URL? = nil) {
        self.url = url
    }

    func connection() throws -> HadithConnection {
        guard let url else { throw HadithDatabaseError.unavailable }
        return try HadithConnection(url: url)
    }

    func validate(full _: Bool = true) throws {
        let db = try connection()
        let identity = try db.query("PRAGMA application_id") { sqlite3_column_int($0, 0) }.first
        let version = try db.query("PRAGMA user_version") { sqlite3_column_int($0, 0) }.first
        guard identity == 1_230_262_606, version == 7 else {
            Logger(subsystem: "com.aljaroudi.Muntathir", category: "HadithAssets")
                .error("Incompatible reader database: application_id=\(identity ?? -1), schema=\(version ?? -1); expected application_id=1230262606, schema=7.")
            throw HadithDatabaseError.incompatible
        }
        _ = try db.query("SELECT h.id, h.source_id, c.file_name, g.grade_ar FROM hadith h JOIN chapter c ON c.id = h.chapter_id LEFT JOIN hadith_grading g ON g.hadith_id = h.id LIMIT 1") { sqlite3_column_int($0, 0) }
        _ = try db.query("SELECT id FROM introduction LIMIT 1") { sqlite3_column_int($0, 0) }
        _ = try db.query("SELECT words, display_number FROM hadith_reading LIMIT 1") { sqlite3_column_int($0, 0) }
        for table in ["hadith_words", "hadith_fts", "hadith_en"] {
            _ = try db.query("SELECT rowid FROM \(table) WHERE \(table) MATCH ? LIMIT 1", parameters: ["test"]) { sqlite3_column_int($0, 0) }
        }
    }
}

enum HadithDatabaseError: Error {
    case unavailable
    case invalidReference
    case incompatible
}

/// A connection stays inside one synchronous actor operation, including its progress callback.
final class HadithConnection {
    private let handle: OpaquePointer

    init(url: URL) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let pointer else {
            if let pointer {
                sqlite3_close(pointer)
            }
            throw HadithDatabaseError.unavailable
        }
        handle = pointer
        sqlite3_progress_handler(handle, 1000, { _ in
            Task<Never, Never>.isCancelled ? 1 : 0
        }, nil)
        try registerLiteralRank()
    }

    deinit { sqlite3_close(handle) }

    private func registerLiteralRank() throws {
        guard sqlite3_create_function_v2(handle, "hadith_literal_rank", 3, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { context, _, values in
            guard let values else { sqlite3_result_error_code(context, SQLITE_ERROR); return }
            if Task<Never, Never>.isCancelled {
                sqlite3_result_error_code(context, SQLITE_INTERRUPT)
                return
            }
            func text(_ index: Int) -> String {
                sqlite3_value_text(values[index]).map { String(cString: $0) } ?? ""
            }
            let terms = QuranSearchText.terms(text(2))
            let arabicRank = QuranSearchText.literalRank(text(0), terms: terms)
            let rank = arabicRank == 0 ? 0 : min(arabicRank, QuranSearchText.literalRank(text(1), terms: terms))
            sqlite3_result_int(context, Int32(rank))
        }, nil, nil, nil) == SQLITE_OK else { throw HadithDatabaseError.unavailable }
    }

    func query<T>(_ sql: String, parameters: [String] = [], row: (OpaquePointer) throws -> T) throws -> [T] {
        try Task.checkCancellation()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            try Task.checkCancellation()
            throw HadithDatabaseError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in parameters.enumerated() {
            let status = value.withCString {
                sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard status == SQLITE_OK else { throw HadithDatabaseError.unavailable }
        }
        var rows: [T] = []
        while true {
            try Task.checkCancellation()
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try rows.append(row(statement))
            case SQLITE_DONE: return rows
            default:
                try Task.checkCancellation()
                throw HadithDatabaseError.unavailable
            }
        }
    }
}

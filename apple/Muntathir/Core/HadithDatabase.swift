import Foundation
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
    func validate() throws {
        let db = try connection()
        let identity = try db.query("PRAGMA application_id") { sqlite3_column_int($0, 0) }.first
        let version = try db.query("PRAGMA user_version") { sqlite3_column_int($0, 0) }.first
        guard identity == 1230262606, version == 6 else { throw HadithDatabaseError.incompatible }
        guard try db.query("PRAGMA quick_check", row: { QuranConnection.text($0, 0) }) == ["ok"] else {
            throw HadithDatabaseError.unavailable
        }
        _ = try db.query("SELECT h.id, g.grade_ar FROM hadith h LEFT JOIN hadith_grading g ON g.hadith_id = h.id LIMIT 1") { sqlite3_column_int($0, 0) }
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
        try registerOrderedMatch()
    }

    deinit { sqlite3_close(handle) }

    private func registerOrderedMatch() throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT fts5(?)", -1, &statement, nil) == SQLITE_OK else {
            throw HadithDatabaseError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        var api: UnsafeMutablePointer<fts5_api>?
        let status = withUnsafeMutablePointer(to: &api) { pointer in
            "fts5_api_ptr".withCString { name in
                sqlite3_bind_pointer(statement, 1, pointer, name, nil)
                return sqlite3_step(statement)
            }
        }
        guard status == SQLITE_ROW, let api,
              api.pointee.xCreateFunction(api, "hadith_ordered", nil, { api, context, result, _, _ in
                  guard let api else { sqlite3_result_error_code(result, SQLITE_ERROR); return }
                  var previous: Int32 = -1
                  for phrase in 0 ..< api.pointee.xPhraseCount(context) {
                      if Task<Never, Never>.isCancelled {
                          sqlite3_result_error_code(result, SQLITE_INTERRUPT)
                          return
                      }
                      var iterator = Fts5PhraseIter()
                      var column: Int32 = -1
                      var offset: Int32 = -1
                      let status = api.pointee.xPhraseFirst(context, phrase, &iterator, &column, &offset)
                      guard status == SQLITE_OK else { sqlite3_result_error_code(result, status); return }
                      // Choose the earliest occurrence after the previous term; one position cannot satisfy two terms.
                      while column >= 0, column != 0 || offset <= previous {
                          api.pointee.xPhraseNext(context, &iterator, &column, &offset)
                      }
                      guard column == 0 else { sqlite3_result_int(result, 0); return }
                      previous = offset
                  }
                  sqlite3_result_int(result, 1)
              }, nil) == SQLITE_OK
        else { throw HadithDatabaseError.unavailable }
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

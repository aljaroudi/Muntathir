import Foundation
import OSLog
import SQLite3

/// A value that can be bound to a `?` placeholder.
protocol SQLiteBindable {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32
}

extension String: SQLiteBindable {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
}

extension Int64: SQLiteBindable {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int64(statement, index, self)
    }
}

extension Int: SQLiteBindable {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int64(statement, index, Int64(self))
    }
}

/// Statement handling shared by `QuranConnection` and `HadithConnection`, which wrap it so each keeps its own error type.
final class SQLiteConnection {
    let handle: OpaquePointer
    private let failure: any Error

    init(path: String, flags: Int32, failure: any Error) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(path, &pointer, flags, nil) == SQLITE_OK, let pointer else {
            if let pointer {
                sqlite3_close(pointer)
            }
            throw failure
        }
        handle = pointer
        self.failure = failure
    }

    deinit { sqlite3_close(handle) }

    func query<T>(_ sql: String, parameters: [any SQLiteBindable] = [], row: (OpaquePointer) throws -> T) throws -> [T] {
        try Task.checkCancellation()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw try failed(sql)
        }
        defer { sqlite3_finalize(statement) }
        for (offset, parameter) in parameters.enumerated() {
            guard parameter.bind(to: statement, at: Int32(offset + 1)) == SQLITE_OK else { throw try failed(sql) }
        }
        var rows: [T] = []
        while true {
            try Task.checkCancellation()
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try rows.append(row(statement))
            case SQLITE_DONE: return rows
            default: throw try failed(sql)
            }
        }
    }

    /// A cancelled task interrupts its statement, so report cancellation rather than logging a database failure.
    private func failed(_ sql: String) throws -> any Error {
        try Task.checkCancellation()
        let message = String(cString: sqlite3_errmsg(handle))
        Logger(subsystem: "com.aljaroudi.Muntathir", category: "SQLite")
            .error("SQLite error \(sqlite3_extended_errcode(self.handle)): \(message, privacy: .public) in \(sql, privacy: .public)")
        return failure
    }

    static func text(_ row: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(row, column).map { String(cString: $0) } ?? ""
    }
}

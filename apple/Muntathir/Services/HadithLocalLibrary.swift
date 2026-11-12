import Foundation
import SQLite3

/// Hosted packs are immutable. Content choices live in an app-owned, replaceable database.
actor HadithLocalLibrary {
    let root: URL
    nonisolated var url: URL {
        root.appending(path: "library.db")
    }

    init(root: URL) {
        self.root = root
    }

    func localURL() -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func books(includeEstimates: Bool = true) throws -> [DownloadedBook] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let db = try QuranConnection(path: url.path, flags: SQLITE_OPEN_READONLY)
        let weights = includeEstimates ? try contentSizes(db) : [:]
        let total = weights.values.reduce(Int64(0), +)
        let bytes = try Int64(url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        return try db.query("""
        SELECT c.id,c.name_ar,c.name_en, EXISTS(
            SELECT 1 FROM hadith h JOIN book b ON b.id=h.book_id WHERE b.collection_id=c.id
        ) FROM download_catalog c ORDER BY c.sort_order,c.id
        """) {
            DownloadedBook(id: QuranConnection.text($0, 0), arabic: QuranConnection.text($0, 1),
                           english: QuranConnection.text($0, 2), installed: sqlite3_column_int($0, 3) != 0,
                           estimatedBytes: total > 0 && sqlite3_column_int($0, 3) != 0
                               ? Int64(Double(bytes) * Double(weights[QuranConnection.text($0, 0), default: 0]) / Double(total)) : nil)
        }
    }

    /// Books share pages and search indexes; apportion actual storage by content bytes.
    private func contentSizes(_ db: QuranConnection) throws -> [String: Int64] {
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'") {
            QuranConnection.text($0, 0)
        }
        func quoted(_ name: String) -> String {
            "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let installed = try Set(db.query("SELECT DISTINCT b.collection_id FROM hadith h JOIN book b ON b.id=h.book_id") {
            QuranConnection.text($0, 0)
        })
        var sizes: [String: Int64] = [:]
        for table in tables {
            try Task.checkCancellation()
            let name = quoted(table)
            let columns = try db.query("PRAGMA table_info(\(name))") { QuranConnection.text($0, 1) }
            let join: String
            switch table {
            case "hadith": join = "JOIN book b ON b.id=t.book_id"
            case "book": join = "JOIN book b ON b.id=t.id"
            case "chapter", "introduction": join = "JOIN book b ON b.id=t.book_id"
            default:
                guard columns.contains("hadith_id") else { continue }
                join = "JOIN hadith h ON h.id=t.hadith_id JOIN book b ON b.id=h.book_id"
            }
            let weight = columns.map { "COALESCE(length(CAST(t.\(quoted($0)) AS BLOB)),0)" }.joined(separator: "+")
            let rows = try db.query("SELECT b.collection_id,SUM(\(weight)) FROM \(name) t \(join) GROUP BY b.collection_id") {
                (QuranConnection.text($0, 0), sqlite3_column_int64($0, 1))
            }
            for (id, bytes) in rows where installed.contains(id) {
                sizes[id, default: 0] += bytes
            }
        }
        return sizes
    }

    func prepare(source: URL, restoring title: String? = nil, removing: String? = nil) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        for stale in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where stale.lastPathComponent.hasPrefix("staging-") {
            try fm.removeItem(at: stale)
        }
        let stage = root.appending(path: "staging-\(UUID().uuidString).db")
        // The previous database remains usable until this entire replacement is validated.
        do {
            var excluded = try Set(books(includeEstimates: false).filter { !$0.installed }.map(\.id))
            if let title {
                excluded.remove(title)
            }
            if let removing {
                excluded.insert(removing)
            }
            try fm.copyItem(at: source, to: stage)
            try prepareDatabase(stage, excluding: excluded)
            let validation = try QuranConnection(path: stage.path, flags: SQLITE_OPEN_READONLY)
            let integrity = try validation.query("PRAGMA integrity_check") { QuranConnection.text($0, 0) }
            guard integrity == ["ok"] else { throw HadithDatabaseError.unavailable }
            try HadithDatabase(url: stage).validate()
            try Task.checkCancellation()
            return stage
        } catch {
            try? fm.removeItem(at: stage)
            throw error
        }
    }

    private func prepareDatabase(_ stage: URL, excluding titles: Set<String>) throws {
        let db = try QuranConnection(path: stage.path, flags: SQLITE_OPEN_READWRITE)
        try db.execute("CREATE TABLE IF NOT EXISTS download_catalog AS SELECT * FROM collection")
        guard !titles.isEmpty else { return }
        try db.execute("CREATE TEMP TABLE removed_hadith(id INTEGER PRIMARY KEY)")
        for title in titles {
            try db.execute("INSERT INTO removed_hadith SELECT h.id FROM hadith h JOIN book b ON b.id=h.book_id WHERE b.collection_id=?", parameters: [title])
        }
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'") { QuranConnection.text($0, 0) }
        // Remove dependent content, including optional grading, translation, and morphology tables.
        for table in tables {
            let quoted = "\"" + table.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let columns = try db.query("PRAGMA table_info(\(quoted))") { QuranConnection.text($0, 1) }
            if columns.contains("hadith_id") {
                try db.execute("DELETE FROM \(quoted) WHERE hadith_id IN (SELECT id FROM removed_hadith)")
            }
        }
        for title in titles {
            try db.execute("DELETE FROM introduction WHERE book_id IN (SELECT id FROM book WHERE collection_id=?)", parameters: [title])
        }
        try db.execute("DELETE FROM hadith WHERE id IN (SELECT id FROM removed_hadith)")
        try db.execute("UPDATE chapter SET hadith_count=(SELECT count(*) FROM hadith WHERE chapter_id=chapter.id)")
        // Contentless indexes cannot use ordinary DELETE. Rebuild from retained text.
        for table in ["hadith_words", "hadith_fts"] {
            try db.execute("INSERT INTO \(table)(\(table)) VALUES('delete-all')")
        }
        // Bound memory while rebuilding even the largest libraries.
        var cursor = Int64.min
        while true {
            let rows = try db.query("SELECT id,arabic FROM hadith WHERE id>CAST(? AS INTEGER) ORDER BY id LIMIT 500", parameters: [String(cursor)]) {
                (sqlite3_column_int64($0, 0), QuranConnection.text($0, 1))
            }
            guard !rows.isEmpty else { break }
            try db.execute("BEGIN")
            for (id, arabic) in rows {
                let parameters = [String(id), QuranSearchText.normalize(arabic)]
                for table in ["hadith_words", "hadith_fts"] {
                    try db.execute("INSERT INTO \(table)(rowid,text) VALUES(CAST(? AS INTEGER),?)", parameters: parameters)
                }
                cursor = id
            }
            try db.execute("COMMIT")
        }
        try db.execute("INSERT INTO hadith_en(hadith_en) VALUES('rebuild')")
        for table in ["hadith_words", "hadith_fts", "hadith_en"] {
            try db.execute("INSERT INTO \(table)(\(table)) VALUES('optimize')")
        }
        try db.execute("VACUUM")
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }
}

import Foundation
import SQLite3

actor HadithReader {
    private var database: HadithDatabase
    static let pageSize = 50

    init(database: HadithDatabase = HadithDatabase()) {
        self.database = database
    }

    /// Actor serialization drains an active synchronous query before replacing/removing its file.
    func install(_ url: URL?, fullValidation: Bool = true) throws {
        database = HadithDatabase(url: nil)
        guard let url else { return }
        let candidate = HadithDatabase(url: url)
        try candidate.validate(full: fullValidation)
        database = candidate
    }

    func catalog() throws -> [HadithCollection] {
        try database.connection().query("""
        SELECT c.id, c.name_ar, c.name_en, count(h.id)
        FROM collection c JOIN book b ON b.collection_id = c.id JOIN hadith h ON h.book_id = b.id
        WHERE c.id != ?
        GROUP BY c.id ORDER BY c.sort_order, c.id
        """, parameters: [Hadith.supplicationCollectionID]) {
            HadithCollection(id: QuranConnection.text($0, 0), arabic: QuranConnection.text($0, 1),
                             english: QuranConnection.text($0, 2), count: Int(sqlite3_column_int($0, 3)))
        }
    }

    func chapters(collectionID: String? = nil) throws -> [HadithChapter] {
        try database.connection().query("""
        SELECT c.id, c.name_ar, c.name_en, \(Self.bookName("ar")), \(Self.bookName("en")), b.id, c.hadith_count, b.collection_id, c.chapter_idx
        FROM chapter c JOIN book b ON b.id = c.book_id
        WHERE b.collection_id != ? \(collectionID == nil ? "" : "AND b.collection_id = ?")
        ORDER BY b.sort_order, c.chapter_idx, c.id
        """, parameters: [Hadith.supplicationCollectionID] + (collectionID.map { [$0] } ?? [])) { row in
            var chapter = Self.chapter(row, offset: 0)
            chapter.bookID = QuranConnection.text(row, 5)
            chapter.count = Int(sqlite3_column_int(row, 6))
            chapter.collectionID = QuranConnection.text(row, 7)
            chapter.index = Int(sqlite3_column_int(row, 8))
            return chapter
        }
    }

    func page(_ request: HadithRequest) throws -> HadithPage {
        try Task.checkCancellation()
        let terms = QuranSearchText.terms(request.query)
        if !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, terms.isEmpty {
            return HadithPage(rows: [], hasMore: false)
        }
        if let number = request.number, number <= 0 {
            throw HadithDatabaseError.invalidReference
        }
        var conditions = ["b.collection_id != ?"]
        var scopeParameters = [Hadith.supplicationCollectionID]
        if let collectionID = request.collectionID {
            conditions.append("b.collection_id = ?")
            scopeParameters.append(collectionID)
        }
        if let chapterID = request.chapterID {
            conditions.append("h.chapter_id = CAST(? AS INTEGER)")
            scopeParameters.append(String(chapterID))
        }
        if let number = request.number {
            conditions.append("CASE WHEN b.collection_id IN ('openiti-wasail','openiti-bihar') THEN h.source_id ELSE h.id_in_book END = CAST(? AS INTEGER)")
            scopeParameters.append(String(number))
        }
        let connection = try database.connection()
        let predicate = conditions.joined(separator: " AND ")
        let base = "FROM hadith h JOIN book b ON b.id = h.book_id"
        var match = Self.match(terms, orderedFallback: false)
        var usedOrderedFallback = false
        if terms.count > 1 {
            let exists = try connection.query("""
            SELECT EXISTS(SELECT 1 \(base) JOIN hadith_words ON hadith_words.rowid = h.id
              WHERE \(predicate) AND hadith_words MATCH ?)
              OR EXISTS(SELECT 1 \(base) JOIN hadith_en ON hadith_en.rowid = h.id
              WHERE \(predicate) AND hadith_en MATCH ?)
            """, parameters: scopeParameters + [match] + scopeParameters + [match]) { sqlite3_column_int($0, 0) != 0 }.first == true
            if !exists {
                usedOrderedFallback = true
                match = Self.match(terms, orderedFallback: true)
            }
        }
        func ordered(_ table: String) -> String {
            usedOrderedFallback ? " AND hadith_ordered(\(table))" : ""
        }
        var selected: [(id: Int, phase: HadithCursor.Phase)] = []
        if request.cursor.phase == .words {
            let values = scopeParameters + [String(request.cursor.afterID)]
            let cursor = "\(predicate) AND h.id > CAST(? AS INTEGER)"
            let sql: String
            let parameters: [String]
            if terms.isEmpty {
                sql = "SELECT h.id \(base) WHERE \(cursor) ORDER BY h.id LIMIT 51"
                parameters = values
            } else {
                let arabic = "SELECT h.id \(base) JOIN hadith_words ON hadith_words.rowid = h.id WHERE \(cursor) AND hadith_words MATCH ?\(ordered("hadith_words")) ORDER BY h.id LIMIT 51"
                let english = "SELECT h.id \(base) JOIN hadith_en ON hadith_en.rowid = h.id WHERE \(cursor) AND hadith_en MATCH ?\(ordered("hadith_en")) ORDER BY h.id LIMIT 51"
                sql = "SELECT id FROM (\(arabic)) UNION SELECT id FROM (\(english)) ORDER BY id LIMIT 51"
                parameters = values + [match] + values + [match]
            }
            selected = try connection.query(sql, parameters: parameters) { (Int(sqlite3_column_int($0, 0)), .words) }
        }
        if selected.count < 51, !terms.isEmpty, terms.allSatisfy({ $0.count >= 3 && $0.unicodeScalars.contains { (0x0600 ... 0x06FF).contains($0.value) } }) {
            let after = request.cursor.phase == .substring ? request.cursor.afterID : 0
            let substring = terms.map { "\"\($0)\"" }.joined(separator: " AND ")
            let sql = """
            SELECT h.id \(base) JOIN hadith_fts ON hadith_fts.rowid = h.id
            WHERE \(predicate) AND h.id > CAST(? AS INTEGER) AND hadith_fts MATCH ?
              AND NOT EXISTS(SELECT 1 FROM hadith_words WHERE rowid = h.id AND hadith_words MATCH ?\(ordered("hadith_words")))
              AND NOT EXISTS(SELECT 1 FROM hadith_en WHERE rowid = h.id AND hadith_en MATCH ?\(ordered("hadith_en")))
            ORDER BY h.id LIMIT \(51 - selected.count)
            """
            selected += try connection.query(sql, parameters: scopeParameters + [String(after), substring, match, match]) {
                (Int(sqlite3_column_int($0, 0)), .substring)
            }
        }
        let visible = Array(selected.prefix(Self.pageSize))
        guard !visible.isEmpty else { return HadithPage(rows: [], hasMore: false, usedOrderedFallback: usedOrderedFallback) }
        let placeholders = visible.map { _ in "?" }.joined(separator: ",")
        let parameters = (terms.isEmpty ? [] : [match]) + visible.map { String($0.id) }
        let values = try connection.query("""
        SELECT \(Self.columns(search: !terms.isEmpty)) \(Self.joins)
        WHERE h.id IN (\(placeholders))
        """, parameters: parameters) { row in
            var narration = Self.narration(row)
            narration.arabicDisplay = HadithText.preview(narration.arabic, terms: terms)
            narration.englishDisplay = HadithText.preview(narration.english, marked: !terms.isEmpty)
            return Hadith(id: narration.id, collectionID: narration.collectionID, number: narration.number,
                          chapter: narration.chapter, arabic: String(narration.arabicDisplay.characters), englishNarrator: "",
                          english: String(narration.englishDisplay.characters),
                          source: narration.source, arabicDisplay: narration.arabicDisplay, englishDisplay: narration.englishDisplay)
        }
        let byID = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        let hasMore = selected.count > Self.pageSize
        let last = visible[visible.count - 1]
        return HadithPage(rows: visible.compactMap { byID[$0.id] }, hasMore: hasMore,
                          usedOrderedFallback: usedOrderedFallback,
                          nextCursor: hasMore ? HadithCursor(phase: last.phase, afterID: last.id) : nil)
    }

    private static func match(_ terms: [String], orderedFallback: Bool) -> String {
        let tokens = terms.map { "\"\($0)\"*" }
        return orderedFallback ? tokens.map { "text : \($0)" }.joined(separator: " AND ")
            : "text : (" + tokens.joined(separator: " + ") + ")"
    }

    func detail(id: Int, query: String = "", orderedFallback: Bool = false) throws -> HadithDetail {
        let connection = try database.connection()
        guard var narration = try connection.query("SELECT \(Self.columns(search: false)) \(Self.joins) WHERE h.id = CAST(? AS INTEGER)", parameters: [String(id)], row: Self.narration).first else {
            throw HadithDatabaseError.invalidReference
        }
        let terms = QuranSearchText.terms(query)
        narration.arabicDisplay = HadithText.highlighted(narration.arabic, terms: terms)
        narration.englishDisplay = HadithText.markdown(narration.english)
        narration.narratorDisplay = HadithText.markdown(narration.englishNarrator)
        if !terms.isEmpty {
            let marked = try connection.query("""
            SELECT highlight(hadith_en, 0, char(57344), char(57345))
            FROM hadith_en WHERE hadith_en MATCH ? AND rowid = CAST(? AS INTEGER)
            """, parameters: [Self.match(terms, orderedFallback: orderedFallback), String(id)]) { QuranConnection.text($0, 0) }.first
            if let marked {
                // The English index trims ASCII spaces around narrator + separator + body.
                let source = narration.englishNarrator + " " + narration.english
                let leading = source.unicodeScalars.prefix { $0.value == 32 }.count
                let boundary = narration.englishNarrator.unicodeScalars.count
                let narratorEnd = max(0, boundary - leading)
                let bodyStart = max(0, boundary + 1 - leading)
                narration.narratorDisplay = HadithText.highlighted(HadithText.markedSlice(marked, range: 0 ..< narratorEnd), marked: true)
                narration.englishDisplay = HadithText.highlighted(HadithText.markedSlice(marked, range: bodyStart ..< max(bodyStart, source.unicodeScalars.count - leading)), marked: true)
            }
        }
        let author = try connection.query("""
        SELECT COALESCE(b.author, ''), b.author_ar FROM hadith h JOIN book b ON b.id = h.book_id WHERE h.id = CAST(? AS INTEGER)
        """, parameters: [String(id)]) { (QuranConnection.text($0, 0), QuranConnection.text($0, 1)) }.first ?? ("", "")
        let gradings = try connection.query("""
        SELECT g.id, g.grader_id, COALESCE(r.name_ar, ''), COALESCE(r.name_en, ''),
               g.grade_ar, g.grade_en, g.reference_ar, g.reference_en, g.status, g.original_text
        FROM hadith_grading g LEFT JOIN grader r ON r.id = g.grader_id
        WHERE g.hadith_id = CAST(? AS INTEGER) ORDER BY g.id
        """, parameters: [String(id)]) {
            HadithGrading(id: Int(sqlite3_column_int($0, 0)),
                          graderID: sqlite3_column_type($0, 1) == SQLITE_NULL ? nil : QuranConnection.text($0, 1),
                          graderArabic: QuranConnection.text($0, 2), graderEnglish: QuranConnection.text($0, 3),
                          gradeArabic: QuranConnection.text($0, 4), gradeEnglish: QuranConnection.text($0, 5),
                          referenceArabic: QuranConnection.text($0, 6), referenceEnglish: QuranConnection.text($0, 7),
                          status: QuranConnection.text($0, 8), originalText: QuranConnection.text($0, 9))
        }
        func adjacent(_ comparison: String, order: String) throws -> Int? {
            try connection.query("""
            SELECT h.id FROM hadith h JOIN book b ON b.id = h.book_id
            WHERE b.collection_id = ? AND h.id \(comparison) CAST(? AS INTEGER)
            ORDER BY h.id \(order) LIMIT 1
            """, parameters: [narration.collectionID, String(id)]) { Int(sqlite3_column_int($0, 0)) }.first
        }
        return try HadithDetail(narration: narration, author: author.0, authorArabic: author.1, gradings: gradings,
                                previousID: adjacent("<", order: "DESC"), nextID: adjacent(">", order: "ASC"))
    }

    /// This small prayer collection is searched as whole texts, with title matches first.
    /// Keep full text inside the reader actor; the list receives only short previews.
    func supplications(query: String = "") throws -> [Hadith] {
        let terms = QuranSearchText.terms(query)
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, terms.isEmpty {
            return []
        }
        let rows = try database.connection().query("""
        SELECT \(Self.columns(search: false)) \(Self.joins)
        WHERE b.collection_id = ? AND c.chapter_idx > 0
        ORDER BY c.chapter_idx, h.id
        """, parameters: [Hadith.supplicationCollectionID], row: Self.narration)
        guard !rows.isEmpty else { throw HadithDatabaseError.incompatible }
        var titled: [Hadith] = []
        var content: [Hadith] = []
        for row in rows {
            try Task.checkCancellation()
            let title = QuranSearchText.normalize(row.chapter.arabic + " " + row.chapter.english).lowercased()
            let text = title + " " + QuranSearchText.normalize(row.arabic + " " + row.english).lowercased()
            guard terms.allSatisfy({ text.contains($0) }) else { continue }
            let preview = HadithText.preview(row.arabic, terms: terms)
            let result = Hadith(id: row.id, collectionID: row.collectionID, number: row.number,
                                chapter: row.chapter, arabic: String(preview.characters), englishNarrator: "",
                                english: "", source: row.source, arabicDisplay: preview)
            if terms.allSatisfy({ title.contains($0) }) {
                titled.append(result)
            } else {
                content.append(result)
            }
        }
        return titled + content
    }

    func source(id: Int) throws -> HadithSource? {
        try database.connection().query("SELECT b.id, c.file_name, h.id_in_book, h.source_id \(Self.joins) WHERE h.id = CAST(? AS INTEGER)", parameters: [String(id)]) {
            HadithSource(book: QuranConnection.text($0, 0), chapterFile: QuranConnection.text($0, 1),
                         number: Int(sqlite3_column_int($0, 2)), sourceID: sqlite3_column_type($0, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int($0, 3)))
        }.first
    }

    /// Preserve collection/volume and chapter boundaries when opting into online search.
    func meaningSearchScope(_ request: HadithRequest) throws -> (sources: [String]?, chapter: String?) {
        if let id = request.chapterID {
            guard let source = try chapterSource(id: id) else { throw URLError(.resourceUnavailable) }
            return ([source.book], source.chapterFile)
        }
        guard let collection = request.collectionID else { return (nil, nil) }
        let books = try database.connection().query("SELECT id FROM book WHERE collection_id = ? ORDER BY id", parameters: [collection]) {
            QuranConnection.text($0, 0)
        }
        guard !books.isEmpty else { throw URLError(.resourceUnavailable) }
        return (books, nil)
    }

    func chapterSource(id: Int?) throws -> HadithSource? {
        guard let id else { return nil }
        return try database.connection().query("SELECT book_id, file_name FROM chapter WHERE id = CAST(? AS INTEGER)", parameters: [String(id)]) {
            HadithSource(book: QuranConnection.text($0, 0), chapterFile: QuranConnection.text($0, 1), number: 0, sourceID: nil)
        }.first
    }

    func chapterID(for source: HadithSource) throws -> Int? {
        try database.connection().query("SELECT id FROM chapter WHERE book_id = ? AND file_name = ?", parameters: [source.book, source.chapterFile]) {
            Int(sqlite3_column_int($0, 0))
        }.first
    }

    func resolve(_ source: HadithSource) throws -> Int? {
        let matches = try database.connection().query("""
        SELECT h.id \(Self.joins) WHERE b.id = ? AND c.file_name = ?
        AND h.id_in_book = CAST(? AS INTEGER)
        AND (h.source_id = CAST(? AS INTEGER) OR (h.source_id IS NULL AND ? = '')) LIMIT 2
        """, parameters: [source.book, source.chapterFile, String(source.number), source.sourceID.map(String.init) ?? "", source.sourceID.map(String.init) ?? ""]) {
            Int(sqlite3_column_int($0, 0))
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// Compact search references omit source IDs; ambiguous assets must never open the wrong narration.
    func resolveSearch(book: String, chapter: String, number: Int) throws -> Int? {
        let matches = try database.connection().query("""
        SELECT h.id \(Self.joins) WHERE b.id = ? AND c.file_name = ?
        AND h.id_in_book = CAST(? AS INTEGER) LIMIT 2
        """, parameters: [book, chapter, String(number)]) {
            Int(sqlite3_column_int($0, 0))
        }
        return matches.count == 1 ? matches.first : nil
    }

    private static let joins = "FROM hadith h JOIN book b ON b.id = h.book_id JOIN chapter c ON c.id = h.chapter_id"

    private static func bookName(_ language: String) -> String {
        "(SELECT CASE WHEN c.name_\(language) = b.name_\(language) OR c.name_\(language) = '' THEN b.name_\(language) ELSE c.name_\(language) || ' · ' || b.name_\(language) END FROM collection c WHERE c.id = b.collection_id)"
    }

    private static func columns(search: Bool) -> String {
        // English FTS supplies exact Porter-stem spans, including matches in the narrator.
        let english = search ? "COALESCE((SELECT highlight(hadith_en, 0, char(57344), char(57345)) FROM hadith_en WHERE hadith_en MATCH ? AND rowid = h.id), h.english_text)" : "h.english_text"
        return "h.id, b.collection_id, h.id_in_book, c.id, c.name_ar, c.name_en, \(bookName("ar")), \(bookName("en")), h.arabic, h.english_narrator, \(english), b.id, c.file_name, h.source_id"
    }

    private static func chapter(_ row: OpaquePointer, offset: Int32) -> HadithChapter {
        HadithChapter(id: Int(sqlite3_column_int(row, offset)), arabic: QuranConnection.text(row, offset + 1),
                      english: QuranConnection.text(row, offset + 2), bookArabic: QuranConnection.text(row, offset + 3),
                      bookEnglish: QuranConnection.text(row, offset + 4))
    }

    private static func narration(_ row: OpaquePointer) -> Hadith {
        Hadith(id: Int(sqlite3_column_int(row, 0)), collectionID: QuranConnection.text(row, 1),
               number: Int(sqlite3_column_int(row, 2)), chapter: chapter(row, offset: 3),
               arabic: QuranConnection.text(row, 8), englishNarrator: QuranConnection.text(row, 9),
               english: QuranConnection.text(row, 10),
               source: HadithSource(book: QuranConnection.text(row, 11), chapterFile: QuranConnection.text(row, 12),
                                    number: Int(sqlite3_column_int(row, 2)),
                                    sourceID: sqlite3_column_type(row, 13) == SQLITE_NULL ? nil : Int(sqlite3_column_int(row, 13))))
    }
}

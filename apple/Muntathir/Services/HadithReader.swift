import Darwin
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
        guard let url else { database = HadithDatabase(url: nil); return }
        let candidate = HadithDatabase(url: url)
        try candidate.validate(full: fullValidation)
        database = candidate
    }

    /// Queries and the final atomic replacement share this actor's executor.
    func commit(_ staged: URL, to destination: URL) throws {
        try HadithDatabase(url: staged).validate()
        try Task.checkCancellation()
        guard rename(staged.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        database = HadithDatabase(url: destination)
    }

    func catalog() throws -> [HadithCollection] {
        try database.connection().query("""
        SELECT c.id, c.name_ar, c.name_en, count(h.id)
        FROM collection c JOIN book b ON b.collection_id = c.id JOIN hadith h ON h.book_id = b.id
        WHERE c.id NOT IN (?,?)
        GROUP BY c.id ORDER BY c.sort_order, c.id
        """, parameters: Hadith.supplicationCollectionIDs) {
            HadithCollection(id: QuranConnection.text($0, 0), arabic: QuranConnection.text($0, 1),
                             english: QuranConnection.text($0, 2), count: Int(sqlite3_column_int($0, 3)))
        }
    }

    func chapters(collectionID: String? = nil) throws -> [HadithChapter] {
        try database.connection().query("""
        SELECT c.id, c.name_ar, c.name_en, \(Self.bookName("ar")), \(Self.bookName("en")), b.id, c.hadith_count, b.collection_id, c.chapter_idx, (SELECT coalesce(sum(r.words),0) FROM hadith h JOIN hadith_reading r ON r.hadith_id=h.id WHERE h.chapter_id=c.id)
        FROM chapter c JOIN book b ON b.id = c.book_id
        WHERE c.hadith_count > 0 AND b.collection_id NOT IN (?,?) \(collectionID == nil ? "" : "AND b.collection_id = ?")
        ORDER BY b.sort_order, c.chapter_idx, c.id
        """, parameters: Hadith.supplicationCollectionIDs + (collectionID.map { [$0] } ?? [])) { row in
            var chapter = Self.chapter(row, offset: 0)
            chapter.bookID = QuranConnection.text(row, 5)
            chapter.count = Int(sqlite3_column_int(row, 6))
            chapter.collectionID = QuranConnection.text(row, 7)
            chapter.index = Int(sqlite3_column_int(row, 8))
            chapter.readingWords = Int(sqlite3_column_int(row, 9))
            return chapter
        }
    }

    func introductions(collectionID: String, chapterID: Int? = nil) throws -> [HadithIntroduction] {
        try database.connection().query("""
        SELECT i.id, i.title, i.arabic, i.english, \(Self.bookName("ar")), \(Self.bookName("en"))
        FROM introduction i JOIN book b ON b.id=i.book_id
        WHERE b.collection_id=? AND i.id=(
            SELECT first.id FROM introduction first JOIN book volume ON volume.id=first.book_id
            WHERE volume.collection_id=b.collection_id ORDER BY volume.sort_order, first.sort_order, first.id LIMIT 1
        ) \(chapterID == nil ? "" : "AND i.chapter_id=CAST(? AS INTEGER)")
        ORDER BY b.sort_order, i.sort_order, i.id
        """, parameters: [collectionID] + (chapterID.map { [String($0)] } ?? [])) {
            HadithIntroduction(id: Int(sqlite3_column_int($0, 0)), title: QuranConnection.text($0, 1),
                               arabic: "", english: "",
                               bookArabic: QuranConnection.text($0, 4), bookEnglish: QuranConnection.text($0, 5),
                               readingWords: ReadingTime.words(arabic: QuranConnection.text($0, 2), english: QuranConnection.text($0, 3)))
        }
    }

    func introduction(id: Int) throws -> HadithIntroduction {
        guard let result = try database.connection().query("""
        SELECT i.id, i.title, i.arabic, i.english, \(Self.bookName("ar")), \(Self.bookName("en"))
        FROM introduction i JOIN book b ON b.id=i.book_id WHERE i.id=CAST(? AS INTEGER)
        """, parameters: [String(id)], row: {
            HadithIntroduction(id: Int(sqlite3_column_int($0, 0)), title: QuranConnection.text($0, 1),
                               arabic: QuranConnection.text($0, 2), english: QuranConnection.text($0, 3),
                               bookArabic: QuranConnection.text($0, 4), bookEnglish: QuranConnection.text($0, 5),
                               readingWords: ReadingTime.words(arabic: QuranConnection.text($0, 2), english: QuranConnection.text($0, 3)))
        }).first else { throw HadithDatabaseError.invalidReference }
        return result
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
        var conditions = ["b.collection_id NOT IN (?,?)"]
        var scopeParameters = Hadith.supplicationCollectionIDs
        if let collectionID = request.collectionID {
            conditions.append("b.collection_id = ?")
            scopeParameters.append(collectionID)
        }
        if let chapterID = request.chapterID {
            conditions.append("h.chapter_id = CAST(? AS INTEGER)")
            scopeParameters.append(String(chapterID))
        }
        if let number = request.number {
            conditions.append("CASE WHEN b.collection_id IN ('openiti-wasail','openiti-bihar') THEN h.source_id ELSE coalesce((SELECT display_number FROM hadith_reading WHERE hadith_id=h.id),h.id_in_book) END = CAST(? AS INTEGER)")
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
        if terms.isEmpty {
            selected = try connection.query("SELECT h.id \(base) WHERE \(predicate) AND h.id > CAST(? AS INTEGER) ORDER BY h.id LIMIT 51",
                                            parameters: scopeParameters + [String(request.cursor.afterID)])
            {
                (Int(sqlite3_column_int($0, 0)), .words)
            }
        } else {
            var indexes = [("hadith_words", match), ("hadith_en", match)]
            // Keep the existing indexed substring eligibility; short queries still use word indexes.
            let hasSubstringIndex = terms.allSatisfy { $0.count >= 3 && $0.unicodeScalars.contains { (0x0600 ... 0x06FF).contains($0.value) } }
            if hasSubstringIndex {
                indexes.append(("hadith_fts", terms.map { "\"\($0)\"" }.joined(separator: " AND ")))
            }
            // Check source text because Porter stemming cannot prove an English literal match.
            let onlyBroaderMatches = usedOrderedFallback && !hasSubstringIndex
            for phase in HadithCursor.Phase.allCases where phase.rawValue >= request.cursor.phase.rawValue {
                // Without substring search, the failed phrase lookup already ruled out both literal tiers.
                if onlyBroaderMatches, phase != .broader {
                    continue
                }
                let after = phase == request.cursor.phase ? request.cursor.afterID : 0
                let remaining = 51 - selected.count
                var queries: [String] = []
                var parameters: [String] = []
                for (table, expression) in indexes {
                    let fallback = table == "hadith_fts" ? "" : ordered(table)
                    let literalFilter = onlyBroaderMatches ? "" : "AND hadith_literal_rank(h.arabic, h.english_narrator || ' ' || h.english_text, ?) = CAST(? AS INTEGER)"
                    // Keep FTS outermost: chapter filters otherwise reopen its prefix scan for every narration.
                    queries.append("""
                    SELECT id FROM (
                      SELECT h.id FROM \(table)
                      CROSS JOIN hadith h ON h.id = \(table).rowid
                      CROSS JOIN book b ON b.id = h.book_id
                      WHERE \(predicate) AND \(table) MATCH ?\(fallback)
                        AND \(table).rowid > CAST(? AS INTEGER)
                        \(literalFilter)
                      ORDER BY \(table).rowid LIMIT \(remaining))
                    """)
                    parameters += scopeParameters + [expression, String(after)]
                    if !onlyBroaderMatches {
                        parameters += [request.query, String(phase.rawValue)]
                    }
                }
                let sql = queries.joined(separator: " UNION ") + " ORDER BY id LIMIT \(remaining)"
                selected += try connection.query(sql, parameters: parameters) {
                    (Int(sqlite3_column_int($0, 0)), phase)
                }
                if selected.count == 51 {
                    break
                }
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
                          source: narration.source, arabicDisplay: narration.arabicDisplay, englishDisplay: narration.englishDisplay,
                          readingWords: narration.readingWords, readingNumber: narration.readingNumber)
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

    func detail(id: Int, query: String = "", orderedFallback: Bool = false, translation: String = "auto", languages: [String] = Locale.preferredLanguages) throws -> HadithDetail {
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
        if narration.isSupplication {
            narration.translation = try SupplicationTranslation.selected(from: translations(id: id), selection: translation, languages: languages)
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

    func translationLanguages() throws -> [String] {
        let connection = try database.connection()
        guard try hasTranslations(connection) else { return [] }
        return try connection.query("SELECT DISTINCT language FROM supplication_translation ORDER BY language") { QuranConnection.text($0, 0) }
    }

    private func hasTranslations(_ connection: HadithConnection) throws -> Bool {
        try !connection.query("SELECT name FROM sqlite_master WHERE type='table' AND name='supplication_translation'", row: { QuranConnection.text($0, 0) }).isEmpty
    }

    func translations(id: Int) throws -> [SupplicationTranslation] {
        let connection = try database.connection()
        guard try hasTranslations(connection) else { return [] }
        return try connection.query("SELECT language,edition,text FROM supplication_translation WHERE hadith_id=CAST(? AS INTEGER) ORDER BY language,edition", parameters: [String(id)]) {
            SupplicationTranslation(language: QuranConnection.text($0, 0), edition: QuranConnection.text($0, 1), text: QuranConnection.text($0, 2))
        }
    }

    /// Keep full texts inside the reader actor; lists receive only short matching previews.
    func supplications(query: String = "", translation: String = "auto", languages: [String] = Locale.preferredLanguages) throws -> [Hadith] {
        let terms = QuranSearchText.terms(query)
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, terms.isEmpty {
            return []
        }
        let rows = try database.connection().query("""
        SELECT \(Self.columns(search: false)) \(Self.joins)
        WHERE b.collection_id IN (?,?) AND c.chapter_idx > 0
        ORDER BY b.sort_order, c.chapter_idx, h.id
        """, parameters: Hadith.supplicationCollectionIDs, row: Self.narration)
        guard !rows.isEmpty else { throw HadithDatabaseError.incompatible }
        var titled: [Hadith] = []
        var content: [Hadith] = []
        for row in rows {
            try Task.checkCancellation()
            let variants = try translations(id: row.id)
            let title = QuranSearchText.normalize(row.chapter.arabic + " " + row.chapter.english).lowercased()
            func matches(_ text: String) -> Bool {
                let normalized = title + " " + QuranSearchText.normalize(text).lowercased()
                return terms.allSatisfy { normalized.contains($0) }
            }
            let titleMatch = terms.allSatisfy { title.contains($0) }
            let selected = SupplicationTranslation.selected(from: variants, selection: translation, languages: languages)
            let matched = selected.flatMap { matches($0.text) ? $0 : nil } ?? variants.first { matches($0.text) }
            guard matches(row.arabic + " " + row.english) || matched != nil else { continue }
            let preview = HadithText.preview(row.arabic, terms: terms)
            var result = Hadith(id: row.id, collectionID: row.collectionID, number: row.number,
                                chapter: row.chapter, arabic: String(preview.characters), englishNarrator: "",
                                english: "", source: row.source, arabicDisplay: preview, readingWords: row.readingWords, readingNumber: row.readingNumber)
            if !terms.isEmpty, let matched, !titleMatch {
                let excerpt = HadithText.preview(matched.text, terms: terms)
                result.translation = SupplicationTranslation(language: matched.language, edition: matched.edition, text: String(excerpt.characters))
            }
            if titleMatch {
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
        let sahifa = language == "ar" ? "WHEN c.id = '\(Hadith.supplicationCollectionID)' THEN 'الصحيفة السجادية' " : ""
        return "(SELECT CASE \(sahifa)WHEN c.name_\(language) = b.name_\(language) OR c.name_\(language) = '' THEN b.name_\(language) ELSE c.name_\(language) || ' · ' || b.name_\(language) END FROM collection c WHERE c.id = b.collection_id)"
    }

    private static func columns(search: Bool) -> String {
        // English FTS supplies exact Porter-stem spans, including matches in the narrator.
        let english = search ? "COALESCE((SELECT highlight(hadith_en, 0, char(57344), char(57345)) FROM hadith_en WHERE hadith_en MATCH ? AND rowid = h.id), h.english_text)" : "h.english_text"
        return "h.id, b.collection_id, h.id_in_book, c.id, c.name_ar, c.name_en, \(bookName("ar")), \(bookName("en")), h.arabic, h.english_narrator, \(english), b.id, c.file_name, h.source_id, (SELECT words FROM hadith_reading WHERE hadith_id=h.id), (SELECT display_number FROM hadith_reading WHERE hadith_id=h.id)"
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
                                    sourceID: sqlite3_column_type(row, 13) == SQLITE_NULL ? nil : Int(sqlite3_column_int(row, 13))),
               readingWords: sqlite3_column_type(row, 14) == SQLITE_NULL
                   ? ReadingTime.words(arabic: QuranConnection.text(row, 8), english: QuranConnection.text(row, 10))
                   : Int(sqlite3_column_int(row, 14)),
               readingNumber: sqlite3_column_type(row, 15) == SQLITE_NULL ? nil : Int(sqlite3_column_int(row, 15)))
    }
}

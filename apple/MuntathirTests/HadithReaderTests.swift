import Foundation
@testable import Muntathir
import SQLite3
import SwiftUI
import Testing

struct HadithReaderTests {
    @Test func bookLabelsIncludeCollectionAndVolume() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        let detail = try await reader.detail(id: 1)
        #expect(detail.narration.chapter.bookTitle(locale: Locale(identifier: "en")) == "Book · Volume 1")
        #expect(detail.narration.chapter.bookTitle(locale: Locale(identifier: "ar")) == "كتاب · المجلد الأول")
        let chapters = try await reader.chapters(collectionID: "merged")
        #expect(chapters.first?.bookEnglish == "Book · Volume 1")
        let page = try await reader.page(HadithRequest(collectionID: "merged"))
        #expect(page.rows.first?.chapter.bookArabic == "كتاب · المجلد الأول")
    }

    @Test func importedCollectionsUsePrintedNumbersOnly() async throws {
        let fixture = try HadithFixture(count: 2)
        defer { fixture.remove() }
        var handle: OpaquePointer?
        #expect(sqlite3_open(fixture.url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "UPDATE collection SET id='openiti-wasail' WHERE id='merged'; UPDATE book SET collection_id='openiti-wasail' WHERE collection_id='merged'; UPDATE hadith SET source_id=77 WHERE id=1; UPDATE hadith SET source_id=NULL WHERE id=2;", nil, nil, nil) == SQLITE_OK)
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        var request = HadithRequest(collectionID: "openiti-wasail")
        request.number = 77
        let rows = try await reader.page(request).rows
        #expect(rows.map(\.id) == [1])
        #expect(rows.first?.displayNumber == 77)
        #expect(try await reader.detail(id: 2).narration.displayNumber == nil)
        request.number = 2
        #expect(try await reader.page(request).rows.isEmpty)
    }

    @Test func supplicationsSearchTitlesAndContentWithoutHadithNavigation() async throws {
        let reader = HadithReader(database: HadithDatabase(url: Bundle(for: HadithTestBundle.self).url(forResource: "supplications", withExtension: "db")))
        let prayers = try await reader.supplications()
        #expect(prayers.count == 54)
        #expect(prayers.allSatisfy { $0.isSupplication } /* swiftformat:disable:this preferKeyPath */ )
        #expect(prayers.first?.chapter.arabic.hasPrefix("(1)") == true)
        #expect(prayers.last?.chapter.arabic.hasPrefix("(54)") == true)
        let titleMatches = try await reader.supplications(query: "مَكَارِم الأخْلاق")
        let prayer = try #require(titleMatches.first)
        #expect(prayer.chapter.arabic.hasPrefix("(20)"))
        let contentMatches = try await reader.supplications(query: "بلغ بإيماني أكمل الإيمان")
        #expect(contentMatches.contains { $0.id == prayer.id })
        #expect(try await reader.supplications(query: "zzzzunknown").isEmpty)
        #expect(try await reader.supplications(query: "!!!").isEmpty)
        let detail = try await reader.detail(id: prayer.id)
        #expect(detail.narration.arabic.count > prayer.arabic.count)
        let reference = HadithShareContent(narration: detail.narration, showEnglish: false, locale: Locale(identifier: "ar")).reference
        #expect(reference.contains("(20)"))
        #expect(!reference.hasSuffix(" · 21"))
        #expect(try await reader.catalog().allSatisfy { $0.id != Hadith.supplicationCollectionID })
        #expect(try await reader.chapters().allSatisfy { $0.collectionID != Hadith.supplicationCollectionID })
        #expect(try await reader.page(HadithRequest(query: "الله", collectionID: Hadith.supplicationCollectionID)).rows.isEmpty)
        #expect(try await reader.page(HadithRequest(query: "الله")).rows.allSatisfy { !$0.isSupplication })
    }

    @Test func kafiOriginalChapterNamesFollowAppLocale() async throws {
        let reader = HadithReader(database: HadithDatabase(url: Bundle(for: HadithTestBundle.self).url(forResource: "hadith", withExtension: "db")))
        let chapters = try await reader.chapters(collectionID: "alkafi")
        #expect(chapters.count == 36)
        #expect(chapters.allSatisfy { !$0.arabic.isEmpty })
        let chapter = try #require(chapters.first { $0.english == "The Book about people with Divine Authority" })
        let arabic = Locale(identifier: "ar_SA")
        let english = Locale(identifier: "en_US")
        #expect(chapter.chapterTitle(locale: arabic) == "كتاب الحجة")
        #expect(chapter.chapterTitle(locale: english) == chapter.english)
        #expect(chapter.chapterTitle(locale: Locale(identifier: "fa")) == chapter.english)
        #expect(chapter.title(locale: arabic).contains("كتاب الحجة"))
        let page = try await reader.page(HadithRequest(collectionID: "alkafi", chapterID: chapter.id))
        let narration = try #require(page.rows.first)
        #expect(narration.chapter.chapterTitle(locale: arabic) == "كتاب الحجة")
        let detail = try await reader.detail(id: narration.id)
        #expect(detail.narration.chapter == narration.chapter)
        let arabicOnly = HadithChapter(id: 0, arabic: "كتاب الحجة", english: "", bookArabic: "الكافي", bookEnglish: "Al-Kafi")
        #expect(arabicOnly.chapterTitle(locale: english) == "كتاب الحجة")
    }

    @Test func structuredGradingsPreserveDetailsAndLocaleFallback() async throws {
        let fixture = try HadithFixture(count: 1, searchRows: """
        INSERT INTO grader VALUES ('majlisi','المجلسي','al-Majlisi');
        INSERT INTO hadith_grading VALUES
          (1,1,'majlisi','صحيح','Sahih','مرجع','Reference','judgment','Original assessment'),
          (2,1,'majlisi','ضعيف','','','Another reference','judgment','Second assessment'),
          (3,1,NULL,'','','','','not_included','Not included');
        """)
        defer { fixture.remove() }
        let detail = try await HadithReader(database: HadithDatabase(url: fixture.url)).detail(id: 1)
        #expect(detail.authorName(locale: Locale(identifier: "ar")) == "مؤلف")
        #expect(detail.authorName(locale: Locale(identifier: "en")) == "Test Author")
        #expect(detail.gradings.count == 3)
        let first = try #require(detail.gradings.first)
        #expect(first.graderID == "majlisi")
        #expect(first.grader(locale: Locale(identifier: "ar")) == "المجلسي")
        #expect(first.judgment(locale: Locale(identifier: "en")) == "Sahih")
        #expect(first.reference(locale: Locale(identifier: "ar")) == "مرجع")
        #expect(first.originalText == "Original assessment")
        #expect(detail.gradings[1].judgment(locale: Locale(identifier: "en")) == "ضعيف")
        #expect(detail.gradings[2].graderID == nil)
        #expect(detail.gradings[2].status == "not_included")
        #expect(detail.gradings[2].judgment(locale: Locale(identifier: "en")).isEmpty)
    }

    @Test func packagedCatalogSearchReferencesAndDetails() async throws {
        let reader = HadithReader(database: HadithDatabase(url: Bundle(for: HadithTestBundle.self).url(forResource: "hadith", withExtension: "db")))
        let books = try await reader.catalog()
        // The smallest supported asset pack uses --sittah --four.
        #expect(books.count >= 10)
        #expect(books.reduce(0) { $0 + $1.count } >= 61799)
        #expect(books.contains { $0.id == "alkafi" })
        #expect(!books.contains { $0.id == "alkafi-1" })
        let plain = try await reader.page(HadithRequest(query: "انما الاعمال"))
        let vocalized = try await reader.page(HadithRequest(query: "إِنَّمَا الأَعْمَالُ"))
        #expect(!plain.rows.isEmpty)
        #expect(plain.rows.map(\.id) == vocalized.rows.map(\.id))
        let english = try await reader.page(HadithRequest(query: "intentions"))
        #expect(!english.rows.isEmpty)
        #expect(english.rows.allSatisfy { $0.englishDisplay.runs.contains { $0.backgroundColor != nil } })
        #expect(plain.rows.allSatisfy { $0.arabicDisplay.runs.contains { $0.backgroundColor != nil } })
        #expect(books.contains { $0.id == "additional-Tahdhib-al-Ahkam-Tusi" })
        let extra = try await reader.page(HadithRequest(collectionID: "additional-Tahdhib-al-Ahkam-Tusi"))
        #expect(!extra.rows.isEmpty)
        #expect(extra.rows[0].chapter.title(locale: Locale(identifier: "ar")).contains(" · "))
        let punctuation = try await reader.page(HadithRequest(query: "\"intentions\" OR zzzzzzzzzzzz * ()"))
        #expect(punctuation.rows.isEmpty) // OR is a literal required word, never an FTS operator.
        #expect(try await reader.page(HadithRequest(query: "\"*():")).rows.isEmpty)
        let chapters = try await reader.chapters(collectionID: "abudawud")
        let chapter = try #require(chapters.first)
        let repeated = try await reader.page(HadithRequest(collectionID: "abudawud", number: 1))
        #expect(repeated.rows.count > 1)
        #expect(Set(repeated.rows.map(\.chapter.id)).count == repeated.rows.count)
        let single = try await reader.page(HadithRequest(collectionID: "abudawud", chapterID: chapter.id, number: 1))
        #expect(single.rows.count == 1)
        let narration = try #require(single.rows.first)
        let full = try await reader.detail(id: narration.id)
        #expect(full.narration.chapter.id == chapter.id)
        #expect(narration.arabicDisplay == HadithText.preview(full.narration.arabic))
        #expect(full.previousID == nil)
        #expect(full.nextID != nil)
        #expect(try await reader.page(HadithRequest(collectionID: "abudawud", number: Int.max)).rows.isEmpty)
        for digits in ["12", "١٢", "۱۲"] {
            #expect(QuranSearchText.number(digits) == 12)
        }
        for query in ["-1", "1.5", "abc", ""] {
            #expect(QuranSearchText.number(query) == nil)
        }
        await #expect(throws: HadithDatabaseError.self) {
            _ = try await reader.page(HadithRequest(number: 0))
        }
    }

    @Test func phrasesPrecedeOrderedFallbackAcrossFiltersAndPages() async throws {
        let fixture = try HadithFixture(count: 1, searchRows: """
        INSERT INTO hadith VALUES
          (200001,'v1',1,2,'book is','A narrator','books is useful'),
          (200002,'v2',2,2,'book here is','','books here is useful'),
          (200003,'v2',2,3,'is a bookstore','','this is a bookstore'),
          (200004,'v2',2,4,'book','','book'),
          (200005,'v2',2,5,'book and book','','books and books'),
          (200006,'v2',2,6,'انما بعض الاعمال','',''),
          (200007,'v1',1,7,'انما الاعمال','',''),
          (200008,'v2',2,8,'الاعمال انما','',''),
          (200009,'v2',2,9,'','','books are useful');
        """)
        defer { fixture.remove() }
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        let adjacent = try await reader.page(HadithRequest(query: "book is"))
        #expect(adjacent.rows.map(\.id) == [200_001])
        #expect(!adjacent.usedOrderedFallback)
        #expect(adjacent.rows[0].englishDisplay.runs.contains { $0.backgroundColor != nil })
        let full = try await reader.detail(id: 200_001, query: "book is")
        #expect(full.author == "Test Author")
        #expect(String(full.narration.englishDisplay.characters) == "books is useful")
        #expect(String(full.narration.narratorDisplay.characters) == "A narrator")
        #expect(full.narration.englishDisplay.runs.contains { $0.backgroundColor != nil })
        let acrossBoundary = try await reader.detail(id: 200_001, query: "narrator book")
        #expect(acrossBoundary.narration.narratorDisplay.runs.contains { $0.backgroundColor != nil })
        #expect(acrossBoundary.narration.englishDisplay.runs.contains { $0.backgroundColor != nil })
        #expect(!String(acrossBoundary.narration.englishDisplay.characters).contains(HadithText.startMarker))
        let exhausted = try await reader.page(HadithRequest(query: "book is", cursor: HadithCursor(afterID: 200_001)))
        #expect(exhausted.rows.isEmpty)
        #expect(!exhausted.usedOrderedFallback)
        let fallback = try await reader.page(HadithRequest(query: "book is", chapterID: 2))
        #expect(fallback.rows.map(\.id) == [200_002])
        #expect(fallback.usedOrderedFallback)
        let fullFallback = try await reader.detail(id: 200_002, query: "book is", orderedFallback: true)
        #expect(fullFallback.narration.englishDisplay.runs.filter { $0.backgroundColor != nil }.count == 2)
        let plainDetail = try await reader.detail(id: 200_002)
        #expect(plainDetail.narration.englishDisplay.runs.allSatisfy { $0.backgroundColor == nil })
        #expect(fallback.rows[0].englishDisplay.runs.contains { $0.backgroundColor != nil })
        #expect(try await reader.page(HadithRequest(query: "book book")).rows.map(\.id) == [200_005])
        #expect(try await reader.page(HadithRequest(query: "book book book")).rows.isEmpty)
        #expect(try await reader.page(HadithRequest(query: "book are")).rows.map(\.id) == [200_009])
        #expect(try await reader.page(HadithRequest(query: "book, is!")).rows.map(\.id) == [200_001])
        #expect(try await reader.page(HadithRequest(query: "book OR is")).rows.isEmpty)
        #expect(try await reader.page(HadithRequest(query: "*():")).rows.isEmpty)
        let arabic = try await reader.page(HadithRequest(query: "إِنَّمَا الأَعْمَالُ"))
        #expect(arabic.rows.map(\.id) == [200_007, 200_006, 200_008])
        #expect(!arabic.usedOrderedFallback)
        let arabicGaps = try await reader.page(HadithRequest(query: "إِنَّمَا الأَعْمَالُ", chapterID: 2))
        #expect(arabicGaps.rows.map(\.id) == [200_006, 200_008])
        #expect(arabicGaps.usedOrderedFallback)
        #expect(try await reader.page(HadithRequest(query: "book is", number: 2, cursor: HadithCursor(afterID: 200_001))).rows.isEmpty)
    }

    @Test func pagingIsBoundedAndCompleteAcrossOneHundredThousandNarrations() async throws {
        let fixture = try HadithFixture()
        defer { fixture.remove() }
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        let first = try await reader.page(HadithRequest(query: "intent"))
        #expect(first.rows.count == 50)
        #expect(first.hasMore)
        #expect(first.rows.map(\.id) == Array(1 ... 50))
        #expect(first.rows.allSatisfy { $0.arabic.count <= 300 && $0.english.count <= 300 && $0.englishNarrator.isEmpty })
        let ordered = try await reader.page(HadithRequest(query: "Narrator 000"))
        #expect(ordered.usedOrderedFallback)
        #expect(ordered.rows.map(\.id) == Array(1 ... 50))
        #expect(ordered.hasMore)
        let orderedLast = try await reader.page(HadithRequest(query: "Narrator 000", cursor: HadithCursor(phase: .broader, afterID: 99950)))
        #expect(orderedLast.rows.map(\.id) == Array(99951 ... 100_000))
        #expect(!orderedLast.hasMore)
        #expect(orderedLast.usedOrderedFallback)
        let second = try await reader.page(HadithRequest(query: "intent", cursor: HadithCursor(phase: .substring, afterID: 50)))
        #expect(second.rows.map(\.id) == Array(51 ... 100))
        let deep = try await reader.page(HadithRequest(query: "intent", cursor: HadithCursor(phase: .substring, afterID: 99950)))
        #expect(deep.rows.map(\.id) == Array(99951 ... 100_000))
        #expect(!deep.hasMore)
        #expect(try await reader.page(HadithRequest(query: "intent", cursor: HadithCursor(phase: .substring, afterID: 100_000))).rows.isEmpty)
        let filtered = try await reader.page(HadithRequest(query: "intent", collectionID: "merged", chapterID: 2))
        #expect(filtered.rows.first?.id == 50001)
        #expect(filtered.rows.allSatisfy { $0.chapter.id == 2 })
        let repeated = try await reader.page(HadithRequest(collectionID: "merged", number: 1))
        #expect(repeated.rows.map(\.id) == [1, 50001])
        let lastVolumeOne = try await reader.detail(id: 50000)
        #expect(lastVolumeOne.nextID == 50001)
        let last = try await reader.detail(id: 100_000)
        #expect(last.nextID == nil)
        #expect(last.narration.arabic.count > 300)
        let absentEnglish = try await reader.detail(id: 100_001)
        #expect(absentEnglish.narration.english.isEmpty)
        #expect(!absentEnglish.narration.arabic.isEmpty)
        // Both indexes contain "intentions" for these rows: UNION must not duplicate them.
        #expect(Set(first.rows.map(\.id)).count == first.rows.count)
        let plan = try HadithDatabase(url: fixture.url).connection().query("""
        EXPLAIN QUERY PLAN SELECT id FROM hadith WHERE book_id = ? AND id_in_book = CAST(? AS INTEGER)
        """, parameters: ["v1", "49999"]) { QuranConnection.text($0, 3) }
        #expect(plan.contains { $0.contains("hadith_book_iib") })
    }

    @Test func missingCorruptAndCancelledRequestsFailSafely() async throws {
        let missing = HadithReader(database: HadithDatabase(url: nil))
        await #expect(throws: HadithDatabaseError.self) { _ = try await missing.catalog() }
        let corrupt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not sqlite".utf8).write(to: corrupt)
        defer { try? FileManager.default.removeItem(at: corrupt) }
        let broken = HadithReader(database: HadithDatabase(url: corrupt))
        await #expect(throws: HadithDatabaseError.self) { _ = try await broken.catalog() }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await HadithReader().page(HadithRequest(query: "الله"))
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
    }

    @Test func substringPaginationKeepsPrimaryResultsFirstAndDeduplicates() async throws {
        let fixture = try HadithFixture(count: 0, searchRows: """
        WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<75)
        INSERT INTO hadith SELECT 200000+x,'v1',1,x,
          CASE WHEN x<=25 THEN 'صلاه' ELSE 'بالصلاه' END,'','' FROM n;
        INSERT INTO hadith VALUES (300000,'v2',2,1,'بالصلاه','','');
        """)
        defer { fixture.remove() }
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        var request = HadithRequest(query: "صلاة", chapterID: 1)
        let first = try await reader.page(request)
        #expect(first.rows.map(\.id) == Array(200_001 ... 200_050))
        #expect(first.nextCursor?.phase == .substring)
        request.cursor = try #require(first.nextCursor)
        let second = try await reader.page(request)
        #expect(second.rows.map(\.id) == Array(200_051 ... 200_075))
        #expect(!second.hasMore)
        #expect(second.rows.allSatisfy { $0.arabicDisplay.runs.contains { $0.backgroundColor != nil } })
        let detail = try await reader.detail(id: 200_051, query: "صلاة")
        #expect(detail.narration.arabicDisplay.runs.contains { $0.backgroundColor != nil })
        let filtered = try await reader.page(HadithRequest(query: "صلاة", chapterID: 2))
        #expect(filtered.rows.map(\.id) == [300_000])
        // Short queries do not fall through to substring matching.
        #expect(try await reader.page(HadithRequest(query: "صل", chapterID: 2)).rows.isEmpty)
    }

    @Test func literalTiersPaginateBeforeStemmedMatches() async throws {
        let fixture = try HadithFixture(count: 1, searchRows: """
        WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<55)
        INSERT INTO hadith SELECT 200000+x,'v1',1,x,'','','believers' FROM n;
        WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<55)
        INSERT INTO hadith SELECT 300000+x,'v1',1,x,'','','believingly' FROM n;
        WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<55)
        INSERT INTO hadith SELECT 400000+x,'v1',1,x,'','','believing' FROM n;
        INSERT INTO hadith VALUES (500000,'v2',2,1,'','','believing');
        """)
        defer { fixture.remove() }
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        var request = HadithRequest(query: "believing", chapterID: 1)
        var ids: [Int] = []
        var phases: [HadithCursor.Phase] = []
        repeat {
            let page = try await reader.page(request)
            ids += page.rows.map(\.id)
            guard let cursor = page.nextCursor else { break }
            phases.append(cursor.phase)
            request.cursor = cursor
            #expect(ids.count <= 165)
            if ids.count > 165 {
                break
            }
        } while true
        #expect(ids == Array(400_001 ... 400_055) + Array(300_001 ... 300_055) + Array(200_001 ... 200_055))
        #expect(phases == [.words, .substring, .broader])
        #expect(try await reader.page(HadithRequest(query: "believing", chapterID: 2)).rows.map(\.id) == [500_000])
    }

    @Test func sqliteProgressHandlerInterruptsWorkBeforeProducingRows() async throws {
        let fixture = try HadithFixture(count: 1)
        defer { fixture.remove() }
        // Signal after opening the connection, then cancel while SQLite is aggregating a huge recursive CTE.
        let (started, signal) = AsyncStream<Void>.makeStream()
        let task = Task.detached {
            let connection = try HadithDatabase(url: fixture.url).connection()
            signal.yield(())
            signal.finish()
            return try connection.query("""
            WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x < 1000000000)
            SELECT sum(x) FROM n
            """) { sqlite3_column_int64($0, 0) }
        }
        for await _ in started {
            break
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}

struct HadithFixture: Sendable {
    let url: URL

    init(count: Int = 100_000, searchRows: String = "") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("hadith-\(UUID().uuidString).db")
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { throw HadithDatabaseError.unavailable }
        defer { sqlite3_close(handle) }
        let sql = """
        PRAGMA application_id = 1230262606;
        PRAGMA user_version = 7;
        CREATE TABLE collection(id TEXT PRIMARY KEY, name_ar TEXT, name_en TEXT, sort_order INTEGER);
        CREATE TABLE book(id TEXT PRIMARY KEY, collection_id TEXT, name_ar TEXT, name_en TEXT, sort_order INTEGER, author TEXT DEFAULT 'Test Author', author_ar TEXT DEFAULT 'مؤلف');
        CREATE TABLE chapter(id INTEGER PRIMARY KEY, book_id TEXT, chapter_idx INTEGER, name_ar TEXT, name_en TEXT);
        CREATE TABLE hadith(id INTEGER PRIMARY KEY, book_id TEXT, chapter_id INTEGER, id_in_book INTEGER, arabic TEXT, english_narrator TEXT, english_text TEXT);
        CREATE TABLE introduction(id INTEGER PRIMARY KEY, book_id TEXT, chapter_id INTEGER, title TEXT, arabic TEXT, english TEXT, url TEXT, sort_order INTEGER);
        CREATE TABLE hadith_reading(hadith_id INTEGER PRIMARY KEY, words INTEGER, display_number INTEGER);
        CREATE TABLE grader(id TEXT PRIMARY KEY, name_ar TEXT, name_en TEXT);
        CREATE TABLE hadith_grading(id INTEGER PRIMARY KEY, hadith_id INTEGER, grader_id TEXT,
          grade_ar TEXT, grade_en TEXT, reference_ar TEXT, reference_en TEXT, status TEXT, original_text TEXT);
        CREATE INDEX hadith_book_iib ON hadith(book_id, id_in_book);
        CREATE INDEX hadith_chapter ON hadith(chapter_id);
        CREATE INDEX book_collection ON book(collection_id);
        CREATE VIRTUAL TABLE hadith_words USING fts5(text, root, lemma, content='', prefix='2 3');
        CREATE VIRTUAL TABLE hadith_fts USING fts5(text, content='', tokenize='trigram');
        CREATE VIEW hadith_english_content AS SELECT id, trim(english_narrator || ' ' || english_text) AS text FROM hadith;
        CREATE VIRTUAL TABLE hadith_en USING fts5(text, content='hadith_english_content', content_rowid='id', tokenize='porter unicode61');
        INSERT INTO collection VALUES ('merged','كتاب','Book',0),('other','آخر','Other',1);
        INSERT INTO book(id,collection_id,name_ar,name_en,sort_order) VALUES ('v1','merged','المجلد الأول','Volume 1',0),('v2','merged','المجلد الثاني','Volume 2',1),('other','other','آخر','Other',2);
        INSERT INTO chapter VALUES (1,'v1',0,'باب','Chapter'),(2,'v2',0,'باب','Chapter'),(3,'other',0,'باب','Chapter');
        WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x < \(count))
        INSERT INTO hadith SELECT x, CASE WHEN x <= 50000 THEN 'v1' ELSE 'v2' END,
          CASE WHEN x <= 50000 THEN 1 ELSE 2 END, (x-1)%50000+1,
          'الأعمال بالنيات' || printf('%0600d',0), 'Narrator', 'intentions ' || printf('%0600d',0) FROM n;
        \(searchRows)
        INSERT INTO hadith_words(rowid,text) SELECT id,CASE WHEN id >= 200000 THEN arabic ELSE 'الاعمال بالنيات intentions' END FROM hadith;
        INSERT INTO hadith_fts(rowid,text) SELECT id,arabic FROM hadith;
        INSERT INTO hadith_en(rowid,text) SELECT id,text FROM hadith_english_content;
        INSERT INTO hadith VALUES (100001,'other',3,1,'نص عربي','','');
        ALTER TABLE chapter ADD COLUMN hadith_count INTEGER NOT NULL DEFAULT 0;
        UPDATE chapter SET hadith_count = (SELECT count(*) FROM hadith WHERE chapter_id = chapter.id);
        ALTER TABLE chapter ADD COLUMN file_name TEXT NOT NULL DEFAULT '1.json';
        ALTER TABLE hadith ADD COLUMN source_id INTEGER;
        UPDATE hadith SET source_id = id_in_book;
        """
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw HadithDatabaseError.unavailable }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class HadithTestBundle: NSObject {}

extension HadithReaderTests {
    @Test func sourceReferencesSurviveGeneratedRowChanges() async throws {
        let fixture = try HadithFixture(count: 2)
        defer { fixture.remove() }
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        let source = try #require(try await reader.detail(id: 1).narration.source)
        #expect(HadithSource(key: source.key) == source)
        #expect(try await reader.resolve(source) == 1)
        var handle: OpaquePointer?
        #expect(sqlite3_open(fixture.url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "UPDATE hadith SET id = 123456 WHERE id = 1", nil, nil, nil) == SQLITE_OK)
        #expect(try await reader.resolve(source) == 123_456)
        #expect(try await reader.resolve(HadithSource(book: "missing", chapterFile: "1.json", number: 1, sourceID: 1)) == nil)
    }
}

extension HadithReaderTests {
    @Test func introductionsStayOutsideNarrationsAndEstimatesUseFullText() async throws {
        let fixture = try HadithFixture(count: 2)
        defer { fixture.remove() }
        var handle: OpaquePointer?
        #expect(sqlite3_open(fixture.url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, """
        INSERT INTO introduction VALUES(1,'v1',NULL,'Introduction','نص المقدمة','','',0);
        INSERT INTO hadith_reading VALUES(1,401,1),(2,201,2);
        """, nil, nil, nil) == SQLITE_OK)
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        let introductions = try await reader.introductions(collectionID: "merged")
        #expect(introductions.count == 1)
        #expect(introductions.first?.arabic.isEmpty == true)
        #expect(try await reader.introduction(id: 1).arabic == "نص المقدمة")
        let page = try await reader.page(HadithRequest(collectionID: "merged"))
        #expect(page.rows.map(\.id) == [1, 2])
        #expect(page.rows.first?.readingWords == 401)
        #expect(page.rows.first?.arabic.count ?? 0 < 300)
        #expect(try await reader.detail(id: 1).narration.readingWords == 401)
        #expect(try await reader.detail(id: 1).previousID == nil)
        #expect(try await reader.detail(id: 1).nextID == 2)
        #expect(try await reader.chapters(collectionID: "merged").first?.readingWords == 602)
        #expect(try await reader.page(HadithRequest(query: "المقدمة", collectionID: "merged")).rows.isEmpty)
    }

    @Test func displayNumbersDoNotChangeSavedSourceKeys() async throws {
        let fixture = try HadithFixture(count: 2)
        defer { fixture.remove() }
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        let original = try #require(await reader.source(id: 2))
        var handle: OpaquePointer?
        #expect(sqlite3_open(fixture.url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "INSERT INTO hadith_reading VALUES(2,200,1);", nil, nil, nil) == SQLITE_OK)
        let detail = try await reader.detail(id: 2)
        #expect(detail.narration.displayNumber == 1)
        #expect(detail.narration.source?.key == original.key)
        #expect(try await reader.resolve(original) == 2)
    }
}

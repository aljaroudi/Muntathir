package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.highlight.HighlightRange
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.sql.JdbcDriver
import com.aljaroudi.muntathir.core.sql.query
import com.aljaroudi.muntathir.core.text.HadithText
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.core.text.TextStyle
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import java.io.File
import java.util.Locale
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of Swift `HadithReaderTests`, `HadithContentsTests` and `HadithBookGroupTests`. */
class HadithReaderTest {
    private val fixtures = mutableListOf<HadithFixture>()

    @AfterTest
    fun cleanUp() = fixtures.forEach(HadithFixture::remove)

    private fun fixture(
        count: Int = 100_000,
        searchRows: String = "",
    ) = HadithFixture(count, searchRows).also { fixtures += it }

    private fun reader(file: File) = HadithReader(JdbcDriver).also { runBlocking { it.install(file) } }

    private fun packaged(name: String): HadithReader {
        val file = Fixtures.repository("build/hadith/dist/$name")
        assumeTrue("build/hadith/dist/$name isn't built", file.isFile)
        return reader(file)
    }

    private val english = Locale.ENGLISH
    private val arabic = Locale.forLanguageTag("ar")

    private fun StyledText?.matched() = this?.has(TextStyle.Match) == true

    private fun List<com.aljaroudi.muntathir.core.text.HadithParagraph>.text() = HadithText.flattened(this).text

    private fun List<com.aljaroudi.muntathir.core.text.HadithParagraph>.matches() =
        sumOf {
            it.text.spans(TextStyle.Match).size
        }

    @Test
    fun recentPagesAreCachedUntilLibraryInstallation() =
        runBlocking<Unit> {
            val fixture = fixture(2)
            val reader = reader(fixture.file)
            val request = HadithRequest("intentions")
            val first = reader.page(request)
            HadithFixture.script(
                fixture.file,
                """
                INSERT INTO hadith_words(hadith_words) VALUES('delete-all');
                UPDATE hadith SET english_text='',english_narrator='';
                INSERT INTO hadith_en(hadith_en) VALUES('rebuild');
                """,
            )
            assertEquals(first.rows.map { it.id }, reader.page(request).rows.map { it.id })
            reader.install(fixture.file)
            assertTrue(reader.page(request).rows.isEmpty())
        }

    @Test
    fun bookLabelsIncludeCollectionAndVolume() =
        runBlocking<Unit> {
            val reader = reader(fixture(1).file)
            val detail = reader.detail(1)
            assertEquals("Book · Volume 1", detail.narration.chapter.bookTitle(english))
            assertEquals("كتاب · المجلد الأول", detail.narration.chapter.bookTitle(arabic))
            assertEquals("Book · Volume 1", reader.chapters("merged").first().bookEnglish)
            assertEquals(
                "كتاب · المجلد الأول",
                reader
                    .page(HadithRequest(collectionID = "merged"))
                    .rows
                    .first()
                    .chapter.bookArabic,
            )
        }

    @Test
    fun importedCollectionsUsePrintedNumbersOnly() =
        runBlocking<Unit> {
            val fixture = fixture(2)
            HadithFixture.script(
                fixture.file,
                """
                UPDATE collection SET id='openiti-wasail' WHERE id='merged';
                UPDATE book SET collection_id='openiti-wasail' WHERE collection_id='merged';
                UPDATE hadith SET source_id=77 WHERE id=1;
                UPDATE hadith SET source_id=NULL WHERE id=2;
                """,
            )
            val reader = reader(fixture.file)
            val rows = reader.page(HadithRequest(collectionID = "openiti-wasail", number = 77)).rows
            assertEquals(listOf(1), rows.map { it.id })
            assertEquals(77, rows.first().displayNumber)
            assertNull(reader.detail(2).narration.displayNumber)
            assertTrue(reader.page(HadithRequest(collectionID = "openiti-wasail", number = 2)).rows.isEmpty())
        }

    @Test
    fun supplicationsSearchTitlesAndContentWithoutHadithNavigation() =
        runBlocking<Unit> {
            val reader = packaged("supplications.db")
            val prayers = reader.supplications()
            assertEquals(57, prayers.size)
            assertTrue(prayers.all { it.isSupplication })
            assertTrue(
                prayers
                    .first()
                    .chapter.arabic
                    .startsWith("(1)"),
            )
            assertEquals("الصحيفة السجادية", prayers.first().chapter.bookTitle(arabic))
            assertEquals("Al-Sahifa al-Sajjadiyya", prayers.first().chapter.bookTitle(english))
            assertTrue(
                prayers
                    .last { it.collectionID == Hadith.SUPPLICATION_COLLECTION_ID }
                    .chapter.arabic
                    .startsWith("(54)"),
            )
            val prayer = reader.supplications("مَكَارِم الأخْلاق").first()
            assertTrue(prayer.chapter.arabic.startsWith("(20)"))
            assertTrue(reader.supplications("بلغ بإيماني أكمل الإيمان").any { it.id == prayer.id })
            assertTrue(reader.supplications("zzzzunknown").isEmpty())
            assertTrue(reader.supplications("!!!").isEmpty())
            val detail = reader.detail(prayer.id)
            assertTrue(detail.narration.arabic.length > prayer.arabic.length)
            val reference = HadithShareContent(detail.narration, showEnglish = false, locale = arabic).reference
            assertTrue("(20)" in reference)
            assertFalse(reference.endsWith(" · 21"))
            assertTrue(reader.catalog().none { it.id == Hadith.SUPPLICATION_COLLECTION_ID })
            assertTrue(reader.chapters().none { it.collectionID == Hadith.SUPPLICATION_COLLECTION_ID })
            assertTrue(reader.page(HadithRequest("الله", Hadith.SUPPLICATION_COLLECTION_ID)).rows.isEmpty())
            assertTrue(reader.page(HadithRequest("الله")).rows.none { it.isSupplication })
        }

    @Test
    fun kafiOriginalChapterNamesFollowAppLocale() =
        runBlocking<Unit> {
            val reader = packaged("hadith.db")
            val chapters = reader.chapters("alkafi")
            assertEquals(36, chapters.size)
            assertTrue(chapters.all { it.arabic.isNotEmpty() })
            val chapter = chapters.first { it.english == "The Book about people with Divine Authority" }
            val saudi = Locale.forLanguageTag("ar-SA")
            assertEquals("كتاب الحجة", chapter.chapterTitle(saudi))
            assertEquals(chapter.english, chapter.chapterTitle(Locale.US))
            assertEquals(chapter.english, chapter.chapterTitle(Locale.forLanguageTag("fa")))
            assertTrue("كتاب الحجة" in chapter.title(saudi))
            val narration = reader.page(HadithRequest(collectionID = "alkafi", chapterID = chapter.id)).rows.first()
            assertEquals("كتاب الحجة", narration.chapter.chapterTitle(saudi))
            assertEquals(narration.chapter, reader.detail(narration.id).narration.chapter)
            assertEquals("كتاب الحجة", HadithChapter(0, "كتاب الحجة", "", "الكافي", "Al-Kafi").chapterTitle(Locale.US))
        }

    @Test
    fun structuredGradingsPreserveDetailsAndLocaleFallback() =
        runBlocking<Unit> {
            val fixture =
                fixture(
                    1,
                    """
                    INSERT INTO grader VALUES ('majlisi','المجلسي','al-Majlisi');
                    INSERT INTO hadith_grading VALUES
                      (1,1,'majlisi','صحيح','Sahih','مرجع','Reference','judgment','Original assessment'),
                      (2,1,'majlisi','ضعيف','','','Another reference','judgment','Second assessment'),
                      (3,1,NULL,'','','','','not_included','Not included');
                    """,
                )
            val detail = reader(fixture.file).detail(1)
            assertEquals("مؤلف", detail.authorName(arabic))
            assertEquals("Test Author", detail.authorName(english))
            assertEquals(3, detail.gradings.size)
            val first = detail.gradings.first()
            assertEquals("majlisi", first.graderID)
            assertEquals("المجلسي", first.grader(arabic))
            assertEquals("Sahih", first.judgment(english))
            assertEquals("مرجع", first.reference(arabic))
            assertEquals("Original assessment", first.originalText)
            assertEquals("ضعيف", detail.gradings[1].judgment(english))
            assertNull(detail.gradings[2].graderID)
            assertEquals("not_included", detail.gradings[2].status)
            assertTrue(detail.gradings[2].judgment(english).isEmpty())
        }

    @Test
    fun packagedCatalogSearchReferencesAndDetails() =
        runBlocking<Unit> {
            val reader = packaged("hadith.db")
            val books = reader.catalog()
            assertTrue(books.size >= 10)
            assertTrue(books.sumOf { it.count } >= 61_799)
            assertTrue(books.any { it.id == "alkafi" })
            assertTrue(books.none { it.id == "alkafi-1" })
            val plain = reader.page(HadithRequest("انما الاعمال"))
            val vocalized = reader.page(HadithRequest("إِنَّمَا الأَعْمَالُ"))
            assertTrue(plain.rows.isNotEmpty())
            assertEquals(plain.rows.map { it.id }, vocalized.rows.map { it.id })
            val english = reader.page(HadithRequest("intentions"))
            assertTrue(english.rows.isNotEmpty())
            assertTrue(english.rows.all { it.englishPreview.matched() })
            assertTrue(plain.rows.all { it.arabicPreview.matched() })
            val extra = reader.page(HadithRequest(collectionID = "additional-Tahdhib-al-Ahkam-Tusi"))
            assertTrue(extra.rows.isNotEmpty())
            assertTrue(" · " in extra.rows[0].chapter.title(arabic))
            // OR is a literal required word, never an FTS operator.
            assertTrue(reader.page(HadithRequest("\"intentions\" OR zzzzzzzzzzzz * ()")).rows.isEmpty())
            assertTrue(reader.page(HadithRequest("\"*():")).rows.isEmpty())
            val chapter = reader.chapters("abudawud").first()
            val repeated = reader.page(HadithRequest(collectionID = "abudawud", number = 1))
            assertTrue(repeated.rows.size > 1)
            assertEquals(
                repeated.rows.size,
                repeated.rows
                    .map { it.chapter.id }
                    .toSet()
                    .size,
            )
            val single = reader.page(HadithRequest(collectionID = "abudawud", chapterID = chapter.id, number = 1))
            assertEquals(1, single.rows.size)
            val narration = single.rows.first()
            val full = reader.detail(narration.id)
            assertEquals(chapter.id, full.narration.chapter.id)
            assertEquals(HadithText.preview(full.narration.arabic), narration.arabicPreview)
            assertNull(full.previousID)
            assertNotNull(full.nextID)
            assertTrue(reader.page(HadithRequest(collectionID = "abudawud", number = Int.MAX_VALUE)).rows.isEmpty())
            for (digits in listOf("12", "١٢", "۱۲")) assertEquals(12, QuranSearchText.number(digits))
            for (query in listOf("-1", "1.5", "abc", "")) assertNull(QuranSearchText.number(query))
            assertFailsWith<HadithDatabaseException> { reader.page(HadithRequest(number = 0)) }
        }

    @Test
    fun phrasesPrecedeAllWordMatchesAcrossFiltersAndPages() =
        runBlocking<Unit> {
            val fixture =
                fixture(
                    1,
                    """
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
                    """,
                )
            val reader = reader(fixture.file)
            val adjacent = reader.page(HadithRequest("book is"))
            assertEquals(listOf(200_001, 200_002), adjacent.rows.map { it.id })
            assertTrue(adjacent.rows[0].englishPreview.matched())
            val full = reader.detail(200_001, "book is")
            assertEquals("Test Author", full.author)
            assertEquals("books is useful", full.englishText.text())
            assertEquals("A narrator", full.narratorText.text())
            assertTrue(full.englishText.matches() > 0)
            val acrossBoundary = reader.detail(200_001, "narrator book")
            assertTrue(acrossBoundary.narratorText.matches() > 0)
            assertTrue(acrossBoundary.englishText.matches() > 0)
            assertFalse(HadithText.START_MARKER in acrossBoundary.englishText.text())
            val exhausted = reader.page(HadithRequest("book is", cursor = HadithCursor(afterID = 200_001)))
            assertEquals(listOf(200_002), exhausted.rows.map { it.id })
            val chapter = reader.page(HadithRequest("book is", chapterID = 2))
            assertEquals(listOf(200_002), chapter.rows.map { it.id })
            assertEquals(2, reader.detail(200_002, "book is").englishText.matches())
            assertEquals(0, reader.detail(200_002).englishText.matches())
            assertTrue(chapter.rows[0].englishPreview.matched())
            assertEquals(
                listOf(200_001, 200_002, 200_004, 200_005),
                reader.page(HadithRequest("book book")).rows.map { it.id },
            )
            assertEquals(4, reader.page(HadithRequest("book book book")).rows.size)
            assertTrue(reader.page(HadithRequest("book are")).rows.isEmpty())
            assertEquals(listOf(200_001, 200_002), reader.page(HadithRequest("book, is!")).rows.map { it.id })
            assertTrue(reader.page(HadithRequest("book OR is")).rows.isEmpty())
            assertTrue(reader.page(HadithRequest("*():")).rows.isEmpty())
            assertEquals(
                listOf(200_007, 200_006, 200_008),
                reader.page(HadithRequest("إِنَّمَا الأَعْمَالُ")).rows.map { it.id },
            )
            assertEquals(
                listOf(
                    200_006,
                    200_008,
                ),
                reader.page(HadithRequest("إِنَّمَا الأَعْمَالُ", chapterID = 2)).rows.map {
                    it.id
                },
            )
            assertEquals(
                listOf(200_002),
                reader
                    .page(
                        HadithRequest("book is", number = 2, cursor = HadithCursor(afterID = 200_001)),
                    ).rows
                    .map { it.id },
            )
        }

    @Test
    fun pagingIsBoundedAndCompleteAcrossOneHundredThousandNarrations() =
        runBlocking<Unit> {
            val fixture = fixture()
            val reader = reader(fixture.file)
            val first = reader.page(HadithRequest("intentions"))
            assertEquals(50, first.rows.size)
            assertTrue(first.hasMore)
            assertEquals((1..50).toList(), first.rows.map { it.id })
            assertTrue(
                first.rows.all {
                    it.arabic.length <= 300 && it.english.length <= 300 &&
                        it.englishNarrator.isEmpty()
                },
            )
            val ordered = reader.page(HadithRequest("Narrator intentions"))
            assertEquals((1..50).toList(), ordered.rows.map { it.id })
            assertTrue(ordered.hasMore)
            val orderedLast =
                reader.page(
                    HadithRequest("Narrator intentions", cursor = HadithCursor(HadithCursor.Phase.Substring, 99_950)),
                )
            assertEquals((99_951..100_000).toList(), orderedLast.rows.map { it.id })
            assertFalse(orderedLast.hasMore)
            val second =
                reader.page(
                    HadithRequest("intentions", cursor = HadithCursor(HadithCursor.Phase.Substring, 50)),
                )
            assertEquals((51..100).toList(), second.rows.map { it.id })
            val deep =
                reader.page(
                    HadithRequest("intentions", cursor = HadithCursor(HadithCursor.Phase.Substring, 99_950)),
                )
            assertEquals((99_951..100_000).toList(), deep.rows.map { it.id })
            assertFalse(deep.hasMore)
            assertTrue(
                reader
                    .page(
                        HadithRequest("intentions", cursor = HadithCursor(HadithCursor.Phase.Substring, 100_000)),
                    ).rows
                    .isEmpty(),
            )
            val filtered = reader.page(HadithRequest("intentions", "merged", 2))
            assertEquals(50_001, filtered.rows.first().id)
            assertTrue(filtered.rows.all { it.chapter.id == 2 })
            assertEquals(
                listOf(1, 50_001),
                reader.page(HadithRequest(collectionID = "merged", number = 1)).rows.map { it.id },
            )
            assertEquals(50_001, reader.detail(50_000).nextID)
            val last = reader.detail(100_000)
            assertNull(last.nextID)
            assertTrue(last.narration.arabic.length > 300)
            val absentEnglish = reader.detail(100_001)
            assertTrue(absentEnglish.narration.english.isEmpty())
            assertFalse(absentEnglish.narration.arabic.isEmpty())
            // Both indexes contain "intentions" for these rows: UNION must not duplicate them.
            assertEquals(
                first.rows.size,
                first.rows
                    .map { it.id }
                    .toSet()
                    .size,
            )
            val plan =
                JdbcDriver.open(fixture.file, writable = false).use { sql ->
                    sql.query(
                        "EXPLAIN QUERY PLAN SELECT id FROM hadith WHERE book_id = ? AND id_in_book = CAST(? AS INTEGER)",
                        "v1",
                        "49999",
                    ) { it.text(3) }
                }
            assertTrue(plan.any { "hadith_book_iib" in it })
        }

    @Test
    fun missingCorruptAndCancelledRequestsFailSafely() =
        runBlocking<Unit> {
            assertFailsWith<HadithDatabaseException> { HadithReader(JdbcDriver).catalog() }
            val corrupt = File.createTempFile("corrupt", ".db").apply { writeText("not sqlite") }
            try {
                assertFailsWith<HadithDatabaseException> { HadithReader(JdbcDriver).install(corrupt) }
            } finally {
                corrupt.delete()
            }
        }

    @Test
    fun basicSearchExcludesInfixesAndCorrections() =
        runBlocking<Unit> {
            val fixture =
                fixture(
                    0,
                    """
                    INSERT INTO hadith VALUES (200001,'v1',1,1,'صلاه','','prayer');
                    INSERT INTO hadith VALUES (200002,'v1',1,2,'بالصلاه','','prayers');
                    INSERT INTO hadith VALUES (200003,'v2',2,1,'','','بالصلاه');
                    """,
                )
            val reader = reader(fixture.file)
            assertEquals(listOf(200_001), reader.page(HadithRequest("صلاة")).rows.map { it.id })
            assertTrue(reader.page(HadithRequest("صل")).rows.isEmpty())
            assertTrue(reader.page(HadithRequest("pryaer")).rows.isEmpty())
            assertEquals(listOf(200_001), reader.page(HadithRequest("prayer")).rows.map { it.id })
            assertEquals(listOf(200_003), reader.page(HadithRequest("بالصلاه", chapterID = 2)).rows.map { it.id })
            HadithDatabase.validate(JdbcDriver, fixture.file)
        }

    @Test
    fun literalTiersPaginateWithoutStemmedMatches() =
        runBlocking<Unit> {
            val fixture =
                fixture(
                    1,
                    """
                    WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<55)
                    INSERT INTO hadith SELECT 200000+x,'v1',1,x,'','','believers' FROM n;
                    WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<55)
                    INSERT INTO hadith SELECT 300000+x,'v1',1,x,'','','believingly' FROM n;
                    WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<55)
                    INSERT INTO hadith SELECT 400000+x,'v1',1,x,'','','believing' FROM n;
                    INSERT INTO hadith VALUES (500000,'v2',2,1,'','','believing');
                    """,
                )
            val reader = reader(fixture.file)
            var request = HadithRequest("believing", chapterID = 1)
            val ids = mutableListOf<Int>()
            val phases = mutableListOf<HadithCursor.Phase>()
            while (ids.size <= 165) {
                val page = reader.page(request)
                ids += page.rows.map { it.id }
                val cursor = page.nextCursor ?: break
                phases += cursor.phase
                request = request.copy(cursor = cursor)
            }
            assertEquals((400_001..400_055).toList(), ids)
            assertEquals(listOf(HadithCursor.Phase.Words), phases)
            assertEquals(listOf(500_000), reader.page(HadithRequest("believing", chapterID = 2)).rows.map { it.id })
        }

    @Test
    fun sourceReferencesSurviveGeneratedRowChanges() =
        runBlocking<Unit> {
            val fixture = fixture(2)
            val reader = reader(fixture.file)
            val source = reader.detail(1).narration.source!!
            assertEquals(source, HadithSource.fromKey(source.key))
            assertEquals(1, reader.resolve(source))
            HadithFixture.script(fixture.file, "UPDATE hadith SET id = 123456 WHERE id = 1;")
            assertEquals(123_456, reader.resolve(source))
            assertNull(reader.resolve(HadithSource("missing", "1.json", 1, 1)))
        }

    @Test
    fun introductionsStayOutsideNarrationsAndEstimatesUseFullText() =
        runBlocking<Unit> {
            val fixture = fixture(2)
            HadithFixture.script(
                fixture.file,
                """
                INSERT INTO introduction VALUES(1,'v1',NULL,'Introduction','نص المقدمة','','',0);
                INSERT INTO hadith_reading VALUES(1,401,1),(2,201,2);
                """,
            )
            val reader = reader(fixture.file)
            val introductions = reader.introductions("merged")
            assertEquals(1, introductions.size)
            assertTrue(introductions.first().arabic.isEmpty())
            assertEquals("نص المقدمة", reader.introduction(1).arabic)
            val page = reader.page(HadithRequest(collectionID = "merged"))
            assertEquals(listOf(1, 2), page.rows.map { it.id })
            assertEquals(401, page.rows.first().readingWords)
            assertTrue(
                page.rows
                    .first()
                    .arabic.length < 300,
            )
            assertEquals(401, reader.detail(1).narration.readingWords)
            assertNull(reader.detail(1).previousID)
            assertEquals(2, reader.detail(1).nextID)
            assertEquals(602, reader.chapters("merged").first().readingWords)
            assertTrue(reader.page(HadithRequest("المقدمة", "merged")).rows.isEmpty())
        }

    @Test
    fun displayNumbersDoNotChangeSavedSourceKeys() =
        runBlocking<Unit> {
            val fixture = fixture(2)
            val reader = reader(fixture.file)
            val original = reader.source(2)!!
            HadithFixture.script(fixture.file, "INSERT INTO hadith_reading VALUES(2,200,1);")
            val detail = reader.detail(2)
            assertEquals(1, detail.narration.displayNumber)
            assertEquals(original.key, detail.narration.source?.key)
            assertEquals(2, reader.resolve(original))
        }

    @Test
    fun multilingualSupplicationsSearchSelectShareAndResolve() =
        runBlocking<Unit> {
            val reader = packaged("supplications.db")
            assertEquals(listOf("en", "ur"), reader.translationLanguages())
            val prayer = reader.supplications("embraces all things", SupplicationTranslation.NONE).first()
            assertEquals("mafatih-supplications", prayer.collectionID)
            assertEquals("en", prayer.translation?.language)
            assertTrue(prayer.translation?.text?.contains("embraces") == true)
            val detail = reader.detail(prayer.id, translation = "ur")
            val translated = detail.narration.translation!!
            assertEquals("ur", translated.language)
            assertTrue(translated.isRightToLeft)
            assertNull(detail.narration.displayNumber)
            val source = detail.narration.source!!
            assertEquals(prayer.id, reader.resolve(source))
            val share = HadithShareContent(detail.narration, showEnglish = false, locale = english)
            assertTrue(translated.text in share.text)
            assertFalse(" · 1" in share.reference)
            val text = detail.highlightBlocks.getValue(translated.block)
            val range = HighlightRange.of(TextRange(0, 10), text)!!
            val highlight =
                ReadingHighlight(
                    source = source.key,
                    isHadith = true,
                    block = translated.block,
                    ranges = listOf(range),
                    excerpt = text.take(10),
                    reference = share.reference,
                )
            assertTrue(highlight.isAvailable(detail.highlightBlocks))
            assertFalse(highlight.isAvailable(mapOf("translation:en:duas.org-en" to text)))
            val restoredID = translated.block.removePrefix("translation:")
            assertEquals(translated, reader.detail(prayer.id, translation = restoredID).narration.translation)
            assertNull(reader.detail(prayer.id, translation = SupplicationTranslation.NONE).narration.translation)
            assertNull(reader.detail(prayer.id, translation = "fr").narration.translation)
            assertEquals(
                "ur",
                reader
                    .detail(
                        prayer.id,
                        languages = listOf(Locale.forLanguageTag("ur-PK")),
                    ).narration.translation
                    ?.language,
            )
            assertNull(reader.detail(prayer.id, languages = listOf(arabic, english)).narration.translation)
            assertTrue(
                reader.supplications("تیری رحمت", "ur").any {
                    it.id == prayer.id &&
                        it.translation?.language == "ur"
                },
            )
            assertTrue(reader.catalog().isEmpty())
            assertTrue(reader.chapters().isEmpty())
            assertTrue(reader.page(HadithRequest("اللهم")).rows.isEmpty())
        }

    @Test
    fun legacySupplicationsWithoutTranslationTableRemainReadable() =
        runBlocking<Unit> {
            val fixture =
                fixture(
                    1,
                    """
                    UPDATE collection SET id='openiti-Sahifa-Sajjadiyya' WHERE id='merged';
                    UPDATE book SET collection_id='openiti-Sahifa-Sajjadiyya' WHERE collection_id='merged';
                    UPDATE chapter SET chapter_idx=1 WHERE id=1;
                    """,
                )
            val reader = reader(fixture.file)
            assertTrue(reader.translationLanguages().isEmpty())
            assertEquals(1, reader.supplications().size)
            assertTrue(
                reader
                    .detail(1, translation = "ur")
                    .narration.arabic
                    .isNotEmpty(),
            )
            assertNull(reader.detail(1, translation = "ur").narration.translation)
        }

    @Test
    fun onlyFirstIntroductionAcrossVolumesIsShown() =
        runBlocking<Unit> {
            val fixture =
                fixture(
                    2,
                    """
                    INSERT INTO introduction VALUES(9,'v1',NULL,'Introduction','المقدمة الأولى','','',0);
                    INSERT INTO introduction VALUES(10,'v1',1,'Fragment','جملة قصيرة','','',1);
                    INSERT INTO introduction VALUES(11,'v2',2,'Volume','جملة أخرى','','',0);
                    """,
                )
            val reader = reader(fixture.file)
            assertEquals(listOf(9), reader.introductions("merged").map { it.id })
            assertTrue(reader.introductions("merged", 2).isEmpty())
            assertEquals(1, reader.detail(1).narration.id)
        }

    @Test
    fun parsesOnlyStandaloneReferences() {
        for (query in listOf("123", " ١ ٢ ٣ ", "۱۲۳")) assertEquals(123, HadithSearch.number(query), query)
        for (query in listOf("0", "-1", "1.2", "²", "123 prayer")) assertNull(HadithSearch.number(query), query)
        for (query in listOf("ch3", "CH٣", " ج۳ ")) assertEquals(3, HadithSearch.chapter(query), query)
        for (query in listOf("ch3 prayer", "ج ٣", "ch0", "chapter 3")) assertNull(HadithSearch.chapter(query), query)
    }

    @Test
    fun groupsUseSourceIdentityAndKeepOrder() {
        val chapters =
            listOf(
                HadithChapter(9, "الإيمان", "Faith", "كتاب", "Book", bookID = "second", count = 12),
                HadithChapter(2, "", "Prayer", "كتاب", "Book", bookID = "second", count = 5),
                HadithChapter(1, "الإيمان", "Faith", "كتاب", "Book", bookID = "first", count = 7),
            )
        val groups = HadithContentsGroup.groups(chapters)
        assertEquals(listOf("second", "first"), groups.map { it.id })
        assertEquals(listOf(9, 2), groups[0].chapters.map { it.id })
        assertEquals(listOf("second", "first"), HadithContentsGroup.groups(chapters, "إيمان").map { it.id })
        assertEquals(
            listOf(2),
            HadithContentsGroup
                .groups(chapters, "Prayer")
                .first()
                .chapters
                .map { it.id },
        )
        assertEquals("Prayer", chapters[1].chapterTitle(arabic))
        assertTrue(HadithContentsGroup.groups(chapters, "missing").isEmpty())
    }

    @Test
    fun contentsLoadNarrationChaptersWithIdentityAndCounts() =
        runBlocking<Unit> {
            val chapters = reader(fixture(3).file).chapters("merged")
            assertEquals(listOf("v1"), chapters.map { it.bookID })
            assertEquals(listOf(3), chapters.map { it.count })
            assertEquals(listOf(0), chapters.map { it.index })
            assertEquals(listOf("merged"), chapters.map { it.collectionID })
        }

    @Test
    fun oldSessionsDecodeWithoutNavigationFields() {
        val saved = HadithSession(request = HadithRequest(collectionID = "bukhari", chapterID = 1))
        val json =
            kotlinx.serialization.json.Json
                .parseToJsonElement(saved.encode())
                .let { it as kotlinx.serialization.json.JsonObject }
        val old =
            kotlinx.serialization.json.JsonObject(
                json - setOf("screen", "contentsQuery", "contentsOffset", "listRow", "contentsRow"),
            )
        val restored = HadithSession.decode(old.toString())
        assertEquals(saved.request, restored.request)
        assertNull(restored.screen)
    }

    @Test
    fun groupsCollectionsBySourceIdentity() {
        for (id in listOf("bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah")) {
            assertEquals(HadithBookGroup.Six, HadithBookGroup.of(id))
        }
        for (id in listOf(
            "alkafi",
            "additional-Man-La-Yahduruh-al-Faqih-Saduq",
            "additional-Tahdhib-al-Ahkam-Tusi",
            "additional-Al-Istibsar-Tusi",
        )) {
            assertEquals(HadithBookGroup.Four, HadithBookGroup.of(id))
        }
        assertEquals(HadithBookGroup.Other, HadithBookGroup.of("additional-Nahj-al-Balagha-Radi"))
        assertEquals(HadithBookGroup.Other, HadithBookGroup.of("new-book"))
        assertEquals(listOf(HadithBookGroup.Four, HadithBookGroup.Six, HadithBookGroup.Other), HadithBookGroup.entries)
    }

    @Test
    fun compactHadithLookupRejectsAmbiguity() =
        runBlocking<Unit> {
            val fixture = fixture(2)
            val reader = reader(fixture.file)
            assertEquals(1, reader.resolveSearch("v1", "1.json", 1))
            HadithFixture.script(fixture.file, "UPDATE hadith SET id_in_book = 1 WHERE id = 2;")
            assertNull(reader.resolveSearch("v1", "1.json", 1))
            assertNull(reader.resolveSearch("missing", "1.json", 1))
        }

    @Test
    fun onlineScopePreservesVolumesAndChapter() =
        runBlocking<Unit> {
            val reader = reader(fixture(2).file)
            assertEquals(listOf("v1", "v2") to null, reader.meaningSearchScope(HadithRequest(collectionID = "merged")))
            val chapter = reader.chapterID(HadithSource("v1", "1.json", 0))!!
            assertEquals(
                listOf("v1") to "1.json",
                reader.meaningSearchScope(HadithRequest(collectionID = "merged", chapterID = chapter)),
            )
            assertFailsWith<HadithDatabaseException> {
                reader.meaningSearchScope(
                    HadithRequest(collectionID = "missing"),
                )
            }
            assertEquals(null to null, reader.meaningSearchScope(HadithRequest()))
        }

    @Test
    fun sourceKeysMatchSwiftEncoding() {
        // Swift's JSONEncoder (sorted keys) escapes slashes and omits a nil source id.
        val source = HadithSource("a/b", "1.json", 3, null)
        assertEquals(
            "{\"book\":\"a\\/b\",\"chapterFile\":\"1.json\",\"number\":3}",
            String(
                java.util.Base64
                    .getDecoder()
                    .decode(source.key),
            ),
        )
        assertEquals(source, HadithSource.fromKey(source.key))
        assertEquals(
            "eyJib29rIjoiYnVraGFyaSIsImNoYXB0ZXJGaWxlIjoiMS5qc29uIiwibnVtYmVyIjoxLCJzb3VyY2VJRCI6MX0=",
            HadithSource("bukhari", "1.json", 1, 1).key,
        )
    }
}

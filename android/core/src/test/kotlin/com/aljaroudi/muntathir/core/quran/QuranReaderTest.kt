package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.sql.execute
import com.aljaroudi.muntathir.core.sql.query
import com.aljaroudi.muntathir.core.text.InvalidReferenceException
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.ReadingTime
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of Swift `QuranReaderTests`, against the iOS bundle's databases. */
class QuranReaderTest {
    private val reader = JdbcQuranSql.bundledReader()

    @Test
    fun chaptersAndReferencesMatchTheBundledQuran() =
        runBlocking {
            val catalog = reader.catalog()
            assertEquals(114, catalog.surahs.size)
            assertEquals(6236, catalog.counts.values.sum())
            assertEquals(7, catalog.counts[1])
            assertEquals(286, catalog.counts[2])
            assertEquals(6, catalog.counts[114])
            val chapter = reader.verses(2, null)
            assertEquals((1..286).toList(), chapter.map { it.number })
            assertEquals(chapter.sumOf { ReadingTime.words(it.text) }, catalog.readingWords[2])
            assertEquals("2:255", reader.verse(2, 255)?.id)
            assertNull(reader.verse(2, 287))
            assertTrue(catalog.surahs[0].matches("الفاتحة"))
            assertTrue(catalog.surahs[0].matches("faatiha"))
            assertTrue(catalog.surahs[0].matches("Al Fatiha"))
            assertFalse(catalog.surahs[0].matches("!!!"))
            assertTrue(catalog.surahs[1].matches("٢"))
        }

    @Test
    fun mushafPagesFollowTheFifteenLineLayout() =
        runBlocking {
            val first = reader.page(1)
            assertEquals(8, first.lines.size)
            assertEquals(QuranPage.Line.Kind.SurahName, first.lines[0].kind)
            assertEquals(
                (1..7).map { "1:$it" },
                first.verses.values
                    .map { it.id }
                    .sorted(),
            )
            val last = reader.page(QuranPage.COUNT)
            assertEquals(15, last.lines.size)
            assertEquals(
                "114:6",
                last.lines
                    .last()
                    .words
                    .last()
                    .let { last.verses[it.index]?.id },
            )
            assertEquals(30, last.juz)
            assertEquals(42, reader.pageNumber(2, 255))
            val words = reader.page(42).lines.flatMap { it.words }
            assertEquals(words.size, words.map { it.id }.toSet().size)
        }

    @Test
    fun arabicSearchNormalizesOnlySearchKeysAndLeavesDatabaseUnchanged() =
        runBlocking {
            val file = JdbcQuranSql.quranFolder.resolve("quran.db")
            val before = file.readBytes()
            val plain = reader.search("الله", null, limit = 6236)
            val vocalized = reader.search("ٱللَّهِ", null, limit = 6236)
            assertTrue(plain.size > 1000)
            assertEquals(plain.map { it.id }, vocalized.map { it.id })
            val first = plain.first()
            assertEquals(reader.verse(first.surah, first.number)?.text, first.text)
            assertNotEquals(QuranSearchText.normalize(first.text), first.text)
            assertContentEquals(before, file.readBytes())
            assertEquals("ااااا", QuranSearchText.normalize("أإآٱـا"))
            assertEquals("في رحمه", QuranSearchText.normalize("فى رحمة"))
        }

    @Test
    fun basicArabicSearchExcludesInfixesBeforePagination() =
        runBlocking {
            val matches = reader.search("يستحي", null, limit = 6236)
            assertEquals(listOf("2:26", "33:53"), matches.take(2).map { it.id })
            assertEquals(2, matches.size)
            val ranks = matches.map { QuranSearchText.literalRank(it.text, listOf("يستحي")) }
            assertEquals(ranks.sorted(), ranks)
            assertEquals(matches.take(3).map { it.id }, reader.search("يَسْتَحِي", null, limit = 3).map { it.id })
            assertTrue(reader.search("يستحي", null, limit = 1, surah = 28).isEmpty())
        }

    @Test
    fun literalTranslationMatchesExcludeBroaderArabicMatches() =
        runBlocking {
            val folder = Files.createTempDirectory("quran").toFile()
            try {
                val arabic = JdbcQuranSql(folder.resolve("quran.db"), readOnly = false)
                val english = JdbcQuranSql(folder.resolve("english.db"), readOnly = false)
                for ((sql, isEnglish) in listOf(arabic to false, english to true)) {
                    sql.execute(
                        "CREATE TABLE quran (\"index\" INTEGER PRIMARY KEY, sura INTEGER, aya INTEGER, text TEXT)",
                    )
                    sql.execute("CREATE VIRTUAL TABLE quran_words USING fts5(text, root)")
                    val texts = if (isEnglish) listOf("mercy", "mercifully", "merciful") else List(3) { "رحمة واسعة" }
                    texts.forEachIndexed { offset, text ->
                        val id = offset + 1
                        sql.execute("INSERT INTO quran VALUES (?, 1, ?, ?)", id, id, text)
                        sql.execute(
                            "INSERT INTO quran_words(rowid, text, root) VALUES (?, ?, ?)",
                            id,
                            text,
                            if (isEnglish) "" else "رحم",
                        )
                    }
                }
                val synthetic =
                    QuranReader(
                        arabic = { arabic },
                        surahs = { JdbcQuranSql.surahs },
                        translation = { if (it == "en.qarai") english else null },
                    )
                assertEquals(listOf("1:3"), synthetic.search("merciful", "en.qarai").map { it.id })
                assertEquals(listOf("1:3"), synthetic.search("merciful", "en.qarai", limit = 1).map { it.id })
                assertTrue(synthetic.search("merciful", null).isEmpty())
                english.execute("UPDATE quran SET text='kindness'")
                english.execute("DELETE FROM quran_words")
                english.execute("INSERT INTO quran_words(rowid,text) SELECT \"index\",text FROM quran")
                assertEquals(listOf("1:3"), synthetic.search("merciful", "en.qarai").map { it.id })
                assertTrue(synthetic.search("merciful", "en.qarai", revision = 1).isEmpty())
            } finally {
                folder.deleteRecursively()
            }
        }

    @Test
    fun literalRanksRequireEveryTermAndRespectWordBoundaries() {
        assertEquals(1, QuranSearchText.literalRank("وَيَستَحيۦ", listOf("يستحي")))
        assertEquals(0, QuranSearchText.literalRank("يَستَحيۦ", listOf("يستحي")))
        assertEquals(1, QuranSearchText.literalRank("رحمة الله", listOf("الله", "رحمه")))
        assertEquals(1, QuranSearchText.literalRank("رحمة بالله", listOf("الله", "رحمه")))
        assertEquals(2, QuranSearchText.literalRank("رحمة", listOf("الله", "رحمه")))
        assertEquals(2, QuranSearchText.literalRank("believers", listOf("believing")))
        assertEquals(0, QuranSearchText.literalRank("Clementísimo", listOf("clementisimo")))
    }

    @Test
    fun typedStandardSpellingsFindTheMushafsSpellings() =
        runBlocking {
            // The index holds the Uthmani spelling (الصلوه, الكتب, النبين, ءامنوا); typed text is standard.
            for ((typed, verse) in listOf(
                "الصلاة" to "2:43",
                "الزكاة" to "2:43",
                "الكتاب" to "2:2",
                "النبيين" to "2:61",
                "آمنوا" to "2:25",
                "إسرائيل" to "2:40",
                "السماوات" to "2:164",
                "القرآن" to "2:185",
            )) {
                assertTrue(reader.search(typed, null, limit = 6236).any { it.id == verse }, typed)
            }
            // Only spellings the index holds are used, so typos and unknown words still find nothing.
            assertTrue(reader.search("الرحمم", null).isEmpty())
            assertTrue(reader.search("كمبيوتر", null).isEmpty())
        }

    @Test
    fun shortVersesAreExcludedExceptForReferences() =
        runBlocking {
            assertFalse(QuranSearchText.isSearchableVerse("أَبْجَدْ هَوَ"))
            assertTrue(QuranSearchText.isSearchableVerse("أَبْجَدْ هَوَزَ"))
            assertTrue(reader.search("الم", null, limit = 6236).all { QuranSearchText.isSearchableVerse(it.text) })
            assertEquals(listOf("2:1"), reader.search("2:1", null).map { it.id })
            assertEquals(listOf("2:1"), reader.search("1", null, surah = 2).map { it.id })
        }

    @Test
    fun searchIndexesMatchUpdatedOpeningVerses() =
        runBlocking {
            val sql = JdbcQuranSql(JdbcQuranSql.quranFolder.resolve("quran.db"))
            val ids =
                sql.query("SELECT rowid FROM quran_words WHERE quran_words MATCH ? ORDER BY rowid", "text : \"بسم\"") {
                    it.int(0)
                }
            assertEquals(
                listOf("1:1", "11:41", "27:30"),
                reader
                    .verses(ids.toSet(), null)
                    .toSortedMap()
                    .values
                    .map { it.id },
            )
        }

    @Test
    fun arabicSearchFindsLiteralWordsAndExcludesRootsAndTypos() =
        runBlocking {
            assertTrue("19:26" in reader.search("صوما", null, limit = 6236).map { it.id })
            assertTrue("2:79" in reader.search("يكتبون", null, limit = 6236).map { it.id })
            assertFalse("2:2" in reader.search("يكتبون", null, limit = 6236).map { it.id })
            assertFalse("1:1" in reader.search("الرحمم", null, limit = 6236).map { it.id })
            assertTrue(reader.search("الصلوة", null).isNotEmpty())
            assertTrue(reader.search("في", null).isNotEmpty())
            val exact = reader.search("الرحيم", null, limit = 6236)
            assertTrue(QuranSearchText.normalize(exact.first().text).contains("الرحيم"))
        }

    @Test
    fun fullTextSearchRespectsTranslationSelectionAndPagination() =
        runBlocking {
            assertTrue(reader.search("merciful", null).isEmpty())
            assertTrue(reader.search("merciful", "es.bornez").isEmpty())
            val translated = reader.search("merciful", "en.qarai")
            assertTrue(translated.isNotEmpty())
            assertTrue(translated.all { it.translations["en.qarai"]?.contains("merc", ignoreCase = true) == true })
            assertTrue(
                reader.search("believing", "en.qarai").all {
                    QuranSearchText.literalRank(it.translations["en.qarai"].orEmpty(), listOf("believing")) < 2
                },
            )
            assertTrue("1:1" in reader.search("Clementísimo", "es.bornez").map { it.id })
            assertTrue(reader.search("真主", "zh.jian").isNotEmpty())
            val first = reader.search("الله", null, limit = 50)
            val next = reader.search("الله", null, limit = 100)
            assertEquals(50, first.size)
            assertEquals(100, next.size)
            assertEquals(next.take(50).map { it.id }, first.map { it.id })
            assertEquals(next.size, next.map { it.id }.toSet().size)
        }

    @Test
    fun warmSearchesStayFast() =
        runBlocking {
            reader.search("رحيم", "en.qarai") // Cold: reads the corpus and the translation once.
            val queries = listOf("الله", "الرحمن", "قال", "موسى", "الصلاة", "mercy", "lord", "prayer", "day", "the")
            val start = System.nanoTime()
            for (query in queries) reader.search(query, "en.qarai", surah = 2)
            for (query in queries) reader.search(query, "en.qarai")
            val average = (System.nanoTime() - start) / 1_000_000.0 / (queries.size * 2)
            println("Quran warm search: %.1f ms".format(average))
            assertTrue(average < 100, "$average ms")
        }

    @Test
    fun referencesAcceptArabicIndicDigitsAndRejectInvalidVerses() =
        runBlocking {
            assertEquals(listOf("2:255"), reader.search("٢:٢٥٥", null).map { it.id })
            assertEquals(listOf("2:255"), reader.search("۲ : ۲۵۵", null).map { it.id })
            for (query in listOf("0:1", "115:1", "2:287", "2:0", "2:", "2:abc", "2:1:2")) {
                assertFailsWith<InvalidReferenceException>(query) { reader.search(query, null) }
            }
        }

    @Test
    fun literalSearchHandlesEmptyTextAndFTSOperators() =
        runBlocking {
            for (query in listOf("", "   ", "\" * : ()", "🙂")) {
                assertTrue(reader.search(query, "en.qarai").isEmpty(), query)
            }
            val quoted = reader.search("\"merciful\"*", "en.qarai")
            val plain = reader.search("merciful", "en.qarai")
            assertEquals(plain.map { it.id }, quoted.map { it.id })
            assertEquals(listOf("mercy", "or", "forgiveness"), QuranSearchText.terms("Mercy OR forgiveness"))
        }

    @Test
    fun chapterSearchPreservesRankingAndFiltersBeforePagination() =
        runBlocking {
            for ((query, translation, chapter) in listOf(
                Triple("الله", "", 2),
                Triple("كتب", "", 2),
                Triple("الرحمن", "", 1),
                Triple("merciful", "en.qarai", 1),
                Triple("真主", "zh.jian", 1),
            )) {
                val global = reader.search(query, translation, limit = 6236)
                val expected = global.filter { it.surah == chapter }
                assertTrue(expected.isNotEmpty(), query)
                val scoped = reader.search(query, translation, limit = 2, surah = chapter)
                assertEquals(expected.take(2).map { it.id }, scoped.map { it.id }, query)
            }
            assertTrue(reader.search("merciful", null, surah = 1).isEmpty())
            assertTrue(reader.search("صوما", null, surah = 19).any { it.id == "19:26" })
        }

    @Test
    fun chapterSearchNumbersAndReferencesStayInScope() =
        runBlocking {
            for (query in listOf("255", "٢٥٥", "۲۵۵", "2:255", "٢:٢٥٥")) {
                assertEquals(listOf("2:255"), reader.search(query, null, surah = 2).map { it.id }, query)
            }
            assertTrue(reader.search("2:255", null, surah = 1).isEmpty())
            for (query in listOf("0", "8", "1:8", "1:abc")) {
                assertFailsWith<InvalidReferenceException>(query) { reader.search(query, null, surah = 1) }
            }
        }

    @Test
    fun selectedTranslationIsMergedAndBlankValuesAreSkipped() =
        runBlocking {
            val ayah = reader.verses(setOf(1), "es.bornez").getValue(1)
            assertEquals(listOf("es.bornez"), ayah.translations.keys.toList())
            val folder = Files.createTempDirectory("quran").toFile()
            try {
                fun create(
                    name: String,
                    text: String,
                ) = JdbcQuranSql(folder.resolve(name), readOnly = false).apply {
                    execute("CREATE TABLE quran (\"index\" INTEGER PRIMARY KEY, sura INTEGER, aya INTEGER, text TEXT)")
                    execute("INSERT INTO quran VALUES (1, 1, 1, ?)", text)
                }
                val arabic = create("quran.db", "نص")
                val spanish = create("es.bornez.db", "texte")
                val english = create("en.qarai.db", " ")
                val synthetic =
                    QuranReader(
                        arabic = { arabic },
                        surahs = { JdbcQuranSql.surahs },
                        translation = { mapOf("es.bornez" to spanish, "en.qarai" to english)[it] },
                    )
                assertEquals("نص", synthetic.verses(setOf(1), null)[1]?.text)
                assertEquals(mapOf("es.bornez" to "texte"), synthetic.verses(setOf(1), "es.bornez")[1]?.translations)
                assertEquals(emptyMap(), synthetic.verses(setOf(1), "en.qarai")[1]?.translations)
                assertEquals(emptyMap(), synthetic.verses(setOf(1), "fr.hamidullah")[1]?.translations)
                assertFalse(QuranReader.isValidTranslation(spanish))
            } finally {
                folder.deleteRecursively()
            }
        }

    @Test
    fun bundledTranslationsAreValid() {
        val translations = JdbcQuranSql.allTranslations()
        assertEquals(13, translations.size)
        for ((id, file) in translations) assertTrue(QuranReader.isValidTranslation(JdbcQuranSql(file)), id)
    }

    @Test
    fun databaseFailureIsNotAnEmptySearchAndCancellationIsRespected() =
        runBlocking {
            val missing =
                QuranReader(
                    arabic = { JdbcQuranSql(JdbcQuranSql.quranFolder.resolve("missing.db")) },
                    surahs = { JdbcQuranSql.surahs },
                )
            assertFailsWith<QuranUnavailableException> { missing.catalog() }
            assertFailsWith<QuranUnavailableException> { missing.search("الله", null) }
            val task =
                async {
                    coroutineContext[kotlinx.coroutines.Job]?.cancel()
                    reader.search("الله", null)
                }
            assertFailsWith<CancellationException> { task.await() }
            assertTrue(reader.search("الله", null).isNotEmpty())
        }
}

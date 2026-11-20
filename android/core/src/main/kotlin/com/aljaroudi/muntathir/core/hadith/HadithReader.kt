package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.sql.ContentSql
import com.aljaroudi.muntathir.core.sql.SqlDriver
import com.aljaroudi.muntathir.core.sql.query
import com.aljaroudi.muntathir.core.text.HadithText
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.ReadingTime
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Locale

/**
 * Every hadith and supplication query, over one installed database. Port of Swift `HadithReader` (an actor):
 * calls are serialized and run on [io], so replacing the file never races a query. The connection stays open
 * until the library changes.
 *
 * Unlike Swift there's no SQLite progress handler: cancellation is checked between statements, and the v7-only
 * `hadith_literal_rank` filter is skipped (Android packs are always v8).
 */
class HadithReader(
    private val driver: SqlDriver,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val mutex = Mutex()
    private var file: File? = null
    private var connection: ContentSql? = null
    private val recentPages = ArrayDeque<Pair<HadithRequest, HadithPage>>()
    private var rankedRequest: HadithRequest? = null
    private var rankedMatches: List<Pair<Int, HadithCursor.Phase>> = emptyList()

    /** Whether the open database has supplication translations; looked up once per connection. */
    private var translationTable: Boolean? = null

    /** Every supplication with its search text normalized, built once per database so typing only filters. */
    private class SupplicationEntry(
        val row: Hadith,
        val title: String,
        val text: String,
        val variants: List<SupplicationTranslation>,
        val variantTexts: Map<SupplicationTranslation, String>,
    )

    private var supplicationIndex: List<SupplicationEntry>? = null

    /** Switches to [file] once it validates (keeping the current one otherwise), or to none. */
    suspend fun install(file: File?) =
        locked {
            reset()
            if (file == null) {
                close()
                return@locked
            }
            val candidate = HadithDatabase.guarded { driver.open(file, writable = false) }
            try {
                HadithDatabase.guarded { HadithDatabase.validate(candidate) }
            } catch (error: Exception) {
                candidate.close()
                throw error
            }
            close()
            this.file = file
            connection = candidate
        }

    /** Validates [staged], then atomically moves it over [destination] and reads from there. */
    suspend fun commit(
        staged: File,
        destination: File,
    ) = locked {
        HadithDatabase.validate(driver, staged)
        currentCoroutineContext().ensureActive()
        // On failure the current file stays installed; its connection simply reopens.
        closeConnection()
        Files.move(
            staged.toPath(),
            destination.toPath(),
            StandardCopyOption.ATOMIC_MOVE,
            StandardCopyOption.REPLACE_EXISTING,
        )
        file = destination
        reset()
    }

    suspend fun catalog(): List<HadithCollection> =
        read { sql ->
            sql.query(
                """
                SELECT c.id, c.name_ar, c.name_en, count(h.id)
                FROM collection c JOIN book b ON b.collection_id = c.id JOIN hadith h ON h.book_id = b.id
                WHERE c.id NOT IN (?,?)
                GROUP BY c.id ORDER BY c.sort_order, c.id
                """.trimIndent(),
                Hadith.SUPPLICATION_COLLECTION_IDS,
            ) { HadithCollection(it.text(0), it.text(1), it.text(2), it.int(3)) }
        }

    suspend fun chapters(collectionID: String? = null): List<HadithChapter> =
        read { sql ->
            sql.query(
                """
                SELECT c.id, c.name_ar, c.name_en, ${bookName("ar")}, ${bookName("en")}, b.id, c.hadith_count,
                  b.collection_id, c.chapter_idx, (SELECT coalesce(sum(r.words),0) FROM hadith h
                  JOIN hadith_reading r ON r.hadith_id=h.id WHERE h.chapter_id=c.id)
                FROM chapter c JOIN book b ON b.id = c.book_id
                WHERE c.hadith_count > 0 AND b.collection_id NOT IN (?,?) ${if (collectionID == null) "" else "AND b.collection_id = ?"}
                ORDER BY b.sort_order, c.chapter_idx, c.id
                """.trimIndent(),
                Hadith.SUPPLICATION_COLLECTION_IDS + listOfNotNull(collectionID),
            ) { row ->
                chapter(row, 0).copy(
                    bookID = row.text(5),
                    count = row.int(6),
                    collectionID = row.text(7),
                    index = row.int(8),
                    readingWords = row.int(9),
                )
            }
        }

    /** The book's first introduction, without its text. */
    suspend fun introductions(
        collectionID: String,
        chapterID: Int? = null,
    ): List<HadithIntroduction> =
        read { sql ->
            sql.query(
                """
                SELECT i.id, i.title, i.arabic, i.english, ${bookName("ar")}, ${bookName("en")}
                FROM introduction i JOIN book b ON b.id=i.book_id
                WHERE b.collection_id=? AND i.id=(
                    SELECT first.id FROM introduction first JOIN book volume ON volume.id=first.book_id
                    WHERE volume.collection_id=b.collection_id ORDER BY volume.sort_order, first.sort_order, first.id LIMIT 1
                ) ${if (chapterID == null) "" else "AND i.chapter_id=?"}
                ORDER BY b.sort_order, i.sort_order, i.id
                """.trimIndent(),
                listOfNotNull<Any>(collectionID, chapterID),
            ) {
                HadithIntroduction(
                    it.int(0),
                    it.text(1),
                    "",
                    "",
                    it.text(4),
                    it.text(5),
                    ReadingTime.words(it.text(2), it.text(3)),
                )
            }
        }

    suspend fun introduction(id: Int): HadithIntroduction =
        read { sql ->
            sql
                .query(
                    "SELECT i.id, i.title, i.arabic, i.english, ${bookName("ar")}, ${bookName("en")} " +
                        "FROM introduction i JOIN book b ON b.id=i.book_id WHERE i.id=?",
                    id,
                ) {
                    HadithIntroduction(
                        it.int(0),
                        it.text(1),
                        it.text(2),
                        it.text(3),
                        it.text(4),
                        it.text(5),
                        ReadingTime.words(it.text(2), it.text(3)),
                    )
                }.firstOrNull() ?: throw HadithDatabaseException.InvalidReference()
        }

    /** Up to [PAGE_SIZE] narrations: browsing in id order, or search results phrase-first. The last 8 pages are cached. */
    suspend fun page(request: HadithRequest): HadithPage =
        read { sql ->
            val cached = recentPages.indexOfFirst { it.first == request }
            if (cached >= 0) {
                val entry = recentPages.removeAt(cached)
                recentPages.addLast(entry)
                return@read entry.second
            }
            loadPage(sql, request).also {
                recentPages.addLast(request to it)
                if (recentPages.size > CACHE_SIZE) recentPages.removeFirst()
            }
        }

    private suspend fun loadPage(
        sql: ContentSql,
        request: HadithRequest,
    ): HadithPage {
        val terms = QuranSearchText.queryTerms(request.query)
        if (request.query.isNotBlank() && terms.isEmpty()) return HadithPage(emptyList(), hasMore = false)
        if (request.number != null && request.number <= 0) throw HadithDatabaseException.InvalidReference()
        val conditions = mutableListOf("b.collection_id NOT IN (?,?)")
        val scope = mutableListOf<Any>(*Hadith.SUPPLICATION_COLLECTION_IDS.toTypedArray())
        request.collectionID?.let {
            conditions += "b.collection_id = ?"
            scope += it
        }
        request.chapterID?.let {
            conditions += "h.chapter_id = ?"
            scope += it
        }
        request.number?.let {
            conditions +=
                "CASE WHEN b.collection_id IN ('openiti-wasail','openiti-bihar') THEN h.source_id ELSE " +
                "coalesce((SELECT display_number FROM hadith_reading WHERE hadith_id=h.id),h.id_in_book) END = ?"
            scope += it
        }
        val predicate = conditions.joinToString(" AND ")
        val base = "FROM hadith h JOIN book b ON b.id = h.book_id"
        val selected: List<Pair<Int, HadithCursor.Phase>> =
            if (terms.isEmpty()) {
                sql.query(
                    "SELECT h.id $base WHERE $predicate AND h.id > ? ORDER BY h.id LIMIT ${PAGE_SIZE + 1}",
                    scope + request.cursor.afterID,
                ) { it.int(0) to HadithCursor.Phase.Words }
            } else {
                val key = request.copy(cursor = HadithCursor())
                if (rankedRequest != key) {
                    val words = terms.joinToString(" AND ") { "\"" + it.replace("\"", "\"\"") + "\"" }
                    val phrase = "\"" + terms.joinToString(" ").replace("\"", "\"\"") + "\""
                    // Rank ids in SQLite; never hydrate and score the whole corpus.
                    rankedMatches =
                        sql.query(
                            """
                            WITH matches AS (
                              SELECT rowid AS id FROM hadith_words WHERE hadith_words MATCH ?
                              UNION SELECT rowid FROM hadith_en WHERE hadith_en MATCH ?
                            ), phrases AS (
                              SELECT rowid AS id FROM hadith_words WHERE hadith_words MATCH ?
                              UNION SELECT rowid FROM hadith_en WHERE hadith_en MATCH ?
                            )
                            SELECT h.id, CASE WHEN h.id IN (SELECT id FROM phrases) THEN 0 ELSE 1 END AS tier
                            $base WHERE $predicate AND h.id IN (SELECT id FROM matches)
                            ORDER BY tier, h.book_id, (SELECT file_name FROM chapter WHERE id=h.chapter_id), h.id_in_book, h.id
                            """.trimIndent(),
                            listOf<Any>(words, words, phrase, phrase) + scope,
                        ) { it.int(0) to HadithCursor.Phase.entries[it.int(1)] }
                    rankedRequest = key
                }
                val start =
                    if (request.cursor.afterID == 0) {
                        0
                    } else {
                        rankedMatches.indexOfFirst { it.first == request.cursor.afterID }.let {
                            if (it <
                                0
                            ) {
                                0
                            } else {
                                it + 1
                            }
                        }
                    }
                rankedMatches.drop(start).take(PAGE_SIZE + 1)
            }
        currentCoroutineContext().ensureActive()
        val visible = selected.take(PAGE_SIZE)
        if (visible.isEmpty()) return HadithPage(emptyList(), hasMore = false)
        val hasMore = selected.size > PAGE_SIZE
        val last = visible.last()
        return HadithPage(
            rows = previews(sql, visible.map { it.first }, terms),
            hasMore = hasMore,
            nextCursor = if (hasMore) HadithCursor(last.second, last.first) else null,
            relatedIDs = visible.filter { it.second == HadithCursor.Phase.Broader }.map { it.first }.toSet(),
        )
    }

    /** Narrations as list rows (short previews styled for [query]), in [ids] order; missing ids are skipped. */
    suspend fun previews(
        ids: List<Int>,
        query: String,
    ): List<Hadith> = read { previews(it, ids, QuranSearchText.queryTerms(query)) }

    private fun previews(
        sql: ContentSql,
        ids: List<Int>,
        terms: List<String>,
    ): List<Hadith> {
        if (ids.isEmpty()) return emptyList()
        val rows =
            sql
                .query("SELECT $COLUMNS $JOINS WHERE h.id IN (${ids.joinToString(",") { "?" }})", ids) { row ->
                    val narration = narration(row)
                    val arabic = HadithText.preview(narration.arabic, terms)
                    val english = HadithText.preview(narration.englishNarrator + " " + narration.english, terms)
                    narration.copy(
                        arabic = arabic.text,
                        englishNarrator = "",
                        english = english.text,
                        arabicPreview = arabic,
                        englishPreview = english,
                    )
                }.associateBy { it.id }
        return ids.mapNotNull(rows::get)
    }

    /** Full text with [query] matches styled; supplications include the chosen translation. */
    suspend fun detail(
        id: Int,
        query: String = "",
        translation: String = SupplicationTranslation.AUTO,
        languages: List<Locale> = listOf(Locale.getDefault()),
    ): HadithDetail =
        read { sql ->
            var narration =
                sql.query("SELECT $COLUMNS $JOINS WHERE h.id = ?", id, row = ::narration).firstOrNull()
                    ?: throw HadithDatabaseException.InvalidReference()
            val terms = QuranSearchText.queryTerms(query)
            if (narration.isSupplication) {
                narration =
                    narration.copy(
                        translation = SupplicationTranslation.selected(translations(sql, id), translation, languages),
                    )
            }
            val author =
                sql
                    .query(
                        "SELECT COALESCE(b.author, ''), b.author_ar FROM hadith h JOIN book b ON b.id = h.book_id WHERE h.id = ?",
                        id,
                    ) { it.text(0) to it.text(1) }
                    .firstOrNull() ?: ("" to "")
            val gradings =
                sql.query(
                    """
                    SELECT g.id, g.grader_id, COALESCE(r.name_ar, ''), COALESCE(r.name_en, ''),
                           g.grade_ar, g.grade_en, g.reference_ar, g.reference_en, g.status, g.original_text
                    FROM hadith_grading g LEFT JOIN grader r ON r.id = g.grader_id
                    WHERE g.hadith_id = ? ORDER BY g.id
                    """.trimIndent(),
                    id,
                ) {
                    HadithGrading(
                        it.int(0),
                        it.textOrNull(1),
                        it.text(2),
                        it.text(3),
                        it.text(4),
                        it.text(5),
                        it.text(6),
                        it.text(7),
                        it.text(8),
                        it.text(9),
                    )
                }

            fun adjacent(
                comparison: String,
                order: String,
            ) = sql
                .query(
                    "SELECT h.id FROM hadith h JOIN book b ON b.id = h.book_id " +
                        "WHERE b.collection_id = ? AND h.id $comparison ? ORDER BY h.id $order LIMIT 1",
                    narration.collectionID,
                    id,
                ) { it.int(0) }
                .firstOrNull()
            HadithDetail(
                narration = narration,
                author = author.first,
                authorArabic = author.second,
                gradings = gradings,
                previousID = adjacent("<", "DESC"),
                nextID = adjacent(">", "ASC"),
                arabicText = HadithText.highlighted(narration.arabic, terms),
                englishText = HadithText.highlighted(narration.english, terms),
                narratorText = HadithText.highlighted(narration.englishNarrator, terms),
            )
        }

    suspend fun translationLanguages(): List<String> =
        read { sql ->
            if (!hasTranslations(sql)) return@read emptyList()
            sql.query("SELECT DISTINCT language FROM supplication_translation ORDER BY language") { it.text(0) }
        }

    suspend fun translations(id: Int): List<SupplicationTranslation> = read { translations(it, id) }

    private fun hasTranslations(sql: ContentSql) =
        translationTable ?: sql
            .query("SELECT name FROM sqlite_master WHERE type='table' AND name='supplication_translation'") {
                it.text(0)
            }.isNotEmpty()
            .also { translationTable = it }

    private fun translations(
        sql: ContentSql,
        id: Int,
    ): List<SupplicationTranslation> {
        if (!hasTranslations(sql)) return emptyList()
        return sql.query(
            "SELECT language,edition,text FROM supplication_translation WHERE hadith_id=? ORDER BY language,edition",
            id,
        ) { SupplicationTranslation(it.text(0), it.text(1), it.text(2)) }
    }

    /** Supplications whose title, text or a translation contains every term; title matches first. Previews only. */
    suspend fun supplications(
        query: String = "",
        translation: String = SupplicationTranslation.AUTO,
        languages: List<Locale> = listOf(Locale.getDefault()),
        locators: List<String>? = null,
    ): List<Hadith> =
        read { sql ->
            val terms = QuranSearchText.queryTerms(query)
            if (locators == null && query.isNotBlank() && terms.isEmpty()) return@read emptyList()
            val titled = mutableListOf<Hadith>()
            val content = mutableListOf<Hadith>()
            val requested = locators?.toSet()
            val ranked = mutableMapOf<String, Hadith>()
            for (entry in supplicationIndex(sql)) {
                currentCoroutineContext().ensureActive()
                val row = entry.row
                val locator = row.source?.let { "${it.book}:${it.chapterFile}:${it.number}" }
                if (requested != null && locator !in requested) continue
                val variants = entry.variants
                val title = entry.title

                fun matches(variant: SupplicationTranslation): Boolean {
                    val normalized = entry.variantTexts[variant] ?: searchText(title, variant.text)
                    return terms.all { it in normalized }
                }
                val titleMatch = terms.all { it in title }
                val selected = SupplicationTranslation.selected(variants, translation, languages)
                val matched = selected?.takeIf(::matches) ?: variants.firstOrNull(::matches)
                if (requested == null && terms.any { it !in entry.text } && matched == null) continue
                val preview = HadithText.preview(row.arabic, terms)
                var result =
                    row.copy(
                        arabic = preview.text,
                        englishNarrator = "",
                        english = "",
                        arabicPreview = preview,
                    )
                val shown = if (titleMatch || requested != null) selected else matched
                if (terms.isNotEmpty() && shown != null) {
                    result = result.copy(translation = shown.copy(text = HadithText.preview(shown.text, terms).text))
                }
                when {
                    requested != null && locator != null -> ranked[locator] = result
                    titleMatch -> titled += result
                    else -> content += result
                }
            }
            locators?.mapNotNull(ranked::get) ?: (titled + content)
        }

    suspend fun source(id: Int): HadithSource? =
        read { sql ->
            sql
                .query("SELECT b.id, c.file_name, h.id_in_book, h.source_id $JOINS WHERE h.id = ?", id) {
                    HadithSource(it.text(0), it.text(1), it.int(2), it.intOrNull(3))
                }.firstOrNull()
        }

    /** The online-search scope that keeps volume and chapter boundaries: (`sources`, `chapter`). */
    suspend fun meaningSearchScope(request: HadithRequest): Pair<List<String>?, String?> =
        read { sql ->
            request.chapterID?.let { id ->
                val source = chapterSource(sql, id) ?: throw HadithDatabaseException.InvalidReference()
                return@read listOf(source.book) to source.chapterFile
            }
            val collection = request.collectionID ?: return@read null to null
            val books = sql.query("SELECT id FROM book WHERE collection_id = ? ORDER BY id", collection) { it.text(0) }
            if (books.isEmpty()) throw HadithDatabaseException.InvalidReference()
            books to null
        }

    suspend fun chapterSource(id: Int?): HadithSource? = id?.let { read { sql -> chapterSource(sql, it) } }

    private fun chapterSource(
        sql: ContentSql,
        id: Int,
    ) = sql
        .query("SELECT book_id, file_name FROM chapter WHERE id = ?", id) { HadithSource(it.text(0), it.text(1), 0) }
        .firstOrNull()

    suspend fun chapterID(source: HadithSource): Int? =
        read { sql ->
            sql
                .query("SELECT id FROM chapter WHERE book_id = ? AND file_name = ?", source.book, source.chapterFile) {
                    it.int(0)
                }.firstOrNull()
        }

    /** The narration a saved [source] names, or `null` unless exactly one row matches. */
    suspend fun resolve(source: HadithSource): Int? =
        read { sql ->
            val sourceID = source.sourceID?.toString() ?: ""
            sql
                .query(
                    "SELECT h.id $JOINS WHERE b.id = ? AND c.file_name = ? AND h.id_in_book = ? " +
                        "AND (h.source_id = CAST(? AS INTEGER) OR (h.source_id IS NULL AND ? = '')) LIMIT 2",
                    source.book,
                    source.chapterFile,
                    source.number,
                    sourceID,
                    sourceID,
                ) { it.int(0) }
                .singleOrNull()
        }

    /** Compact search references omit source ids; ambiguous matches must never open the wrong narration. */
    suspend fun resolveSearch(
        book: String,
        chapter: String,
        number: Int,
    ): Int? =
        read { sql ->
            sql
                .query(
                    "SELECT h.id $JOINS WHERE b.id = ? AND c.file_name = ? AND h.id_in_book = ? LIMIT 2",
                    book,
                    chapter,
                    number,
                ) { it.int(0) }
                .singleOrNull()
        }

    private fun reset() {
        recentPages.clear()
        rankedRequest = null
        rankedMatches = emptyList()
        translationTable = null
        supplicationIndex = null
    }

    private fun supplicationIndex(sql: ContentSql): List<SupplicationEntry> {
        supplicationIndex?.let { return it }
        val rows =
            sql.query(
                "SELECT $COLUMNS $JOINS WHERE b.collection_id IN (?,?) AND c.chapter_idx > 0 " +
                    "ORDER BY b.sort_order, c.chapter_idx, h.id",
                Hadith.SUPPLICATION_COLLECTION_IDS,
                ::narration,
            )
        if (rows.isEmpty()) throw HadithDatabaseException.Incompatible()
        // Every translation in one query, rather than one per supplication.
        val translations =
            if (!hasTranslations(sql)) {
                emptyMap()
            } else {
                sql
                    .query(
                        "SELECT hadith_id,language,edition,text FROM supplication_translation ORDER BY language,edition",
                    ) {
                        it.int(0) to SupplicationTranslation(it.text(1), it.text(2), it.text(3))
                    }.groupBy({ it.first }, { it.second })
            }
        return rows
            .map { row ->
                val title = QuranSearchText.normalize(row.chapter.arabic + " " + row.chapter.english).lowercase()
                val variants = translations[row.id].orEmpty()
                SupplicationEntry(
                    row,
                    title,
                    searchText(title, row.arabic + " " + row.english),
                    variants,
                    variants.associateWith { searchText(title, it.text) },
                )
            }.also { supplicationIndex = it }
    }

    private fun searchText(
        title: String,
        text: String,
    ) = title + " " + QuranSearchText.normalize(text).lowercase()

    private fun close() {
        closeConnection()
        file = null
    }

    private fun closeConnection() {
        runCatching { connection?.close() }
        connection = null
    }

    private fun connection(): ContentSql {
        connection?.let { return it }
        val file = file ?: throw HadithDatabaseException.Unavailable()
        return driver.open(file, writable = false).also { connection = it }
    }

    private suspend fun <T> read(block: suspend (ContentSql) -> T): T =
        locked {
            HadithDatabase.guarded { block(connection()) }
        }

    private suspend fun <T> locked(block: suspend () -> T): T {
        currentCoroutineContext().ensureActive()
        return mutex.withLock { withContext(io) { block() } }
    }

    companion object {
        const val PAGE_SIZE = 50
        private const val CACHE_SIZE = 8

        private const val JOINS = "FROM hadith h JOIN book b ON b.id = h.book_id JOIN chapter c ON c.id = h.chapter_id"

        /** The collection name, plus the volume when it differs; the Sahifa reads as one book in Arabic. */
        private fun bookName(language: String): String {
            val sahifa =
                if (language ==
                    "ar"
                ) {
                    "WHEN c.id = '${Hadith.SUPPLICATION_COLLECTION_ID}' THEN 'الصحيفة السجادية' "
                } else {
                    ""
                }
            return "(SELECT CASE ${sahifa}WHEN c.name_$language = b.name_$language OR c.name_$language = '' " +
                "THEN b.name_$language ELSE c.name_$language || ' · ' || b.name_$language END " +
                "FROM collection c WHERE c.id = b.collection_id)"
        }

        private val COLUMNS =
            "h.id, b.collection_id, h.id_in_book, c.id, c.name_ar, c.name_en, ${bookName("ar")}, ${bookName("en")}, " +
                "h.arabic, h.english_narrator, h.english_text, b.id, c.file_name, h.source_id, " +
                "(SELECT words FROM hadith_reading WHERE hadith_id=h.id), " +
                "(SELECT display_number FROM hadith_reading WHERE hadith_id=h.id)"

        private fun chapter(
            row: ContentSql.Row,
            offset: Int,
        ) = HadithChapter(
            row.int(offset),
            row.text(offset + 1),
            row.text(offset + 2),
            row.text(offset + 3),
            row.text(offset + 4),
        )

        private fun narration(row: ContentSql.Row) =
            Hadith(
                id = row.int(0),
                collectionID = row.text(1),
                number = row.int(2),
                chapter = chapter(row, 3),
                arabic = row.text(8),
                englishNarrator = row.text(9),
                english = row.text(10),
                source = HadithSource(row.text(11), row.text(12), row.int(2), row.intOrNull(13)),
                readingWords = row.intOrNull(14) ?: ReadingTime.words(row.text(8), row.text(10)),
                readingNumber = row.intOrNull(15),
            )
    }
}

package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.sql.ContentSql
import com.aljaroudi.muntathir.core.sql.query
import com.aljaroudi.muntathir.core.text.InvalidReferenceException
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.QuranSpelling
import com.aljaroudi.muntathir.core.text.QuranVocabulary
import com.aljaroudi.muntathir.core.text.ReadingTime
import com.aljaroudi.muntathir.core.text.SearchRelevance
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Surahs with their verse counts and reading-time words. */
data class QuranCatalog(
    val surahs: List<QuranSurah>,
    val counts: Map<Int, Int>,
    val readingWords: Map<Int, Int>,
)

/**
 * Chapters, mushaf pages and search over the bundled Arabic database and an installed translation.
 * Port of Swift `QuranReader` + `QuranDatabase`. Calls are serialized; lookups block, so call off the main thread.
 *
 * [arabic] and [surahs] throw when the bundled content is missing; [translation] is `null` when that
 * translation isn't installed.
 */
class QuranReader(
    private val arabic: () -> ContentSql,
    private val surahs: () -> List<QuranSurah>,
    private val translation: (String) -> ContentSql? = { null },
) {
    private data class SearchKey(
        val query: String,
        val translation: String?,
        val limit: Int,
        val surah: Int?,
        val revision: Int,
    )

    /** Every Arabic verse by index, read once: search ranks and filters in memory instead of rereading the table. */
    private class ArabicCorpus(
        val texts: Map<Int, String>,
        val surahs: IntArray,
        val searchable: BooleanArray,
        /** The word index's terms, for matching typed spellings to the mushaf's; absent without an index. */
        val vocabulary: QuranVocabulary?,
    )

    private val mutex = Mutex()
    private val recentSearches = ArrayDeque<Pair<SearchKey, List<Ayah>>>()
    private var cachedCatalog: QuranCatalog? = null
    private var corpus: ArabicCorpus? = null

    /** The last searched translation's texts; dropped when [searchRevision] changes. */
    private var translationTexts: Pair<String, Map<Int, String>>? = null
    private var searchRevision = 0

    suspend fun catalog(): QuranCatalog =
        locked {
            cachedCatalog?.let { return@locked it }
            val surahs = runCatching(surahs).getOrElse { throw QuranUnavailableException(it) }
            if (surahs.map { it.id } != (1..114).toList()) throw QuranUnavailableException()
            val counts = mutableMapOf<Int, Int>()
            val words = mutableMapOf<Int, Int>()
            arabicQuery("SELECT sura, text FROM quran") { it.int(0) to ReadingTime.words(it.text(1)) }
                .forEach { (surah, count) ->
                    counts.merge(surah, 1, Int::plus)
                    words.merge(surah, count, Int::plus)
                }
            if (surahs.any { (counts[it.id] ?: 0) <= 0 }) throw QuranUnavailableException()
            QuranCatalog(surahs, counts, words).also { cachedCatalog = it }
        }

    suspend fun verses(
        surah: Int,
        translation: String?,
    ): List<Ayah> = locked { readVerses("sura = ?", listOf(surah), translation).map { it.second } }

    suspend fun verse(
        surah: Int,
        number: Int,
        translation: String? = null,
    ): Ayah? = locked { verseLocked(surah, number, translation) }

    /** Verses by global index; unknown indices are absent and failures read as empty. Swift `verses(ids:)`. */
    suspend fun verses(
        ids: Set<Int>,
        translation: String?,
    ): Map<Int, Ayah> =
        locked {
            val valid = ids.filter { it in 1..VERSE_COUNT }.sorted()
            if (valid.isEmpty()) return@locked emptyMap()
            try {
                valid.chunked(CHUNK).flatMap { readVerses(indexIn(it.size), it, translation) }.toMap()
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Exception) {
                emptyMap()
            }
        }

    /** Verses for `"surah:verse"` references, in mushaf order; malformed or missing references are skipped. */
    suspend fun verses(
        references: List<String>,
        translation: String?,
    ): List<Ayah> =
        locked {
            references
                .mapNotNull { reference ->
                    val (surah, verse) =
                        runCatching { QuranSearchText.reference(reference) }.getOrNull()
                            ?: return@mapNotNull null
                    verseLocked(surah, verse, translation)
                }.sortedWith(compareBy({ it.surah }, { it.number }))
        }

    suspend fun page(number: Int): QuranPage = locked { pageLocked(number) }

    /** The mushaf page of a verse, or `null` for an unknown verse. */
    suspend fun pageNumber(
        surah: Int,
        verse: Int,
    ): Int? =
        locked {
            arabicQuery("SELECT page FROM quran WHERE sura = ? AND aya = ?", surah, verse) { it.int(0) }.firstOrNull()
        }

    /**
     * Exact phrases, then all-word matches; Arabic wins ties between languages. A number within [surah] or a
     * `surah:verse` reference returns that verse, or throws [InvalidReferenceException]. Results within the same
     * [revision] are cached, so bump it whenever installed translations change.
     */
    suspend fun search(
        query: String,
        translation: String?,
        limit: Int = 50,
        surah: Int? = null,
        revision: Int = 0,
    ): List<Ayah> =
        locked {
            val key = SearchKey(query, translation, limit, surah, revision)
            if (revision != searchRevision) {
                recentSearches.clear()
                translationTexts = null
                searchRevision = revision
            }
            recentSearches.indexOfFirst { it.first == key }.takeIf { it >= 0 }?.let { index ->
                val entry = recentSearches.removeAt(index)
                recentSearches.addLast(entry)
                return@locked entry.second
            }
            val result = performSearch(query, translation, limit, surah)
            if (limit <= MAX_CACHED_LIMIT) {
                recentSearches.addLast(key to result)
                if (recentSearches.size > CACHE_SIZE) recentSearches.removeFirst()
            }
            result
        }

    private suspend fun performSearch(
        query: String,
        translation: String?,
        limit: Int,
        surah: Int?,
    ): List<Ayah> {
        val job = currentCoroutineContext()[Job]
        if (surah != null) {
            QuranSearchText.number(query)?.let { number ->
                return listOf(verseLocked(surah, number, translation) ?: throw InvalidReferenceException())
            }
        }
        QuranSearchText.reference(query)?.let { (referenceSurah, verse) ->
            if (surah != null && referenceSurah != surah) return emptyList()
            return listOf(verseLocked(referenceSurah, verse, translation) ?: throw InvalidReferenceException())
        }
        val terms = QuranSearchText.queryTerms(query)
        if (terms.isEmpty()) return emptyList()
        val corpus = corpus()
        // Typed spellings are matched to the mushaf's only for the Arabic text; translations keep what was typed.
        val arabicTerms = corpus.vocabulary?.let { QuranSpelling.resolve(terms, it) } ?: terms
        val arabicRanks =
            guarded { ranked(matches(arabicTerms, arabicSql(), corpus.texts, job), arabicTerms, corpus.texts, job) }
        val translated =
            translation?.let { id ->
                // Optional assets can disappear or be invalid; Arabic search must still work.
                try {
                    val sql = translationSql(id) ?: return@let null
                    val texts = translationTexts(id, sql)
                    ranked(matches(terms, sql, texts, job), terms, texts, job)
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Exception) {
                    null
                }
            } ?: List(TIERS) { emptyList() }
        val page =
            (0 until TIERS)
                .asSequence()
                .flatMap { arabicRanks[it] + translated[it] }
                .distinct()
                .filter { it in 1..VERSE_COUNT && corpus.searchable[it] }
                .filter { surah == null || corpus.surahs[it] == surah }
                .take(maxOf(0, limit))
                .toList()
        if (page.isEmpty()) return emptyList()
        job?.ensureActive()
        val verses = page.chunked(CHUNK).flatMap { readVerses(indexIn(it.size), it, translation) }.toMap()
        return page.mapNotNull { verses[it] }
    }

    /** Ids grouped by relevance tier (0: phrase, 1: every term), each sorted by score, then index. */
    private fun ranked(
        ids: List<Int>,
        terms: List<String>,
        texts: Map<Int, String>,
        job: Job?,
    ): List<List<Int>> {
        if (ids.isEmpty()) return List(TIERS) { emptyList() }
        val groups = List(TIERS) { mutableListOf<Pair<Int, SearchRelevance>>() }
        for (id in ids) {
            job?.ensureActive()
            val score = SearchRelevance.score(texts[id].orEmpty(), terms) ?: continue
            if (score.tier < 2) groups[score.tier] += id to score
        }
        return groups.map { group -> group.sortedWith(compareBy({ it.second }, { it.first })).map { it.first } }
    }

    /** One word index per database; Chinese translations have none and use literal matching. */
    private fun matches(
        terms: List<String>,
        sql: ContentSql,
        texts: Map<Int, String>,
        job: Job?,
    ): List<Int> {
        val hasIndex = sql.query("SELECT name FROM sqlite_master WHERE name='quran_words'") { it.text(0) }.isNotEmpty()
        if (hasIndex) {
            val match = terms.joinToString(" AND ") { "text : \"" + it.replace("\"", "\"\"") + "\"" }
            return sql.query(
                "SELECT rowid FROM quran_words WHERE quran_words MATCH ? ORDER BY rowid",
                match,
            ) { it.int(0) }
        }
        return texts.keys.sorted().filter { index ->
            job?.ensureActive()
            QuranSearchText.literalRank(texts.getValue(index), terms) < 2
        }
    }

    private fun corpus(): ArabicCorpus =
        corpus ?: run {
            val texts = HashMap<Int, String>(VERSE_COUNT * 2)
            val surahs = IntArray(VERSE_COUNT + 1)
            val searchable = BooleanArray(VERSE_COUNT + 1)
            arabicQuery("SELECT \"index\", sura, text FROM quran") { Triple(it.int(0), it.int(1), it.text(2)) }
                .forEach { (index, surah, text) ->
                    texts[index] = text
                    if (index in 1..VERSE_COUNT) {
                        surahs[index] = surah
                        searchable[index] = QuranSearchText.isSearchableVerse(text)
                    }
                }
            val vocabulary =
                runCatching {
                    QuranVocabulary(
                        arabicQuery("SELECT term, doc FROM quran_words_vocab") { it.text(0) to it.int(1) }.toMap(),
                    )
                }.getOrNull()
            ArabicCorpus(texts, surahs, searchable, vocabulary).also { corpus = it }
        }

    private fun translationTexts(
        id: String,
        sql: ContentSql,
    ): Map<Int, String> =
        translationTexts?.takeIf { it.first == id }?.second
            ?: sql
                .query("SELECT \"index\", text FROM quran") { it.int(0) to it.text(1) }
                .toMap()
                .also { translationTexts = id to it }

    private fun pageLocked(number: Int): QuranPage {
        class Bounds(
            val line: QuranPage.Line,
            val first: Pair<Int, Int>,
            val last: Pair<Int, Int>,
        )
        val rows =
            arabicQuery(
                "SELECT line, type, centered, sura, first_index, first_word, last_index, last_word " +
                    "FROM quran_lines WHERE page = ? ORDER BY line",
                number,
            ) {
                Bounds(
                    QuranPage.Line(it.int(0), QuranPage.Line.Kind.of(it.text(1)), it.int(2) != 0, it.int(3)),
                    it.int(4) to it.int(5),
                    it.int(6) to it.int(7),
                )
            }
        val ayahs = rows.filter { it.line.kind == QuranPage.Line.Kind.Ayah }
        val first = ayahs.firstOrNull()?.first ?: throw QuranUnavailableException()
        val last = ayahs.last().last
        val words =
            arabicQuery(
                "SELECT \"index\", word, text FROM quran_words_qpc " +
                    "WHERE (\"index\", word) BETWEEN (?, ?) AND (?, ?) ORDER BY \"index\", word",
                first.first,
                first.second,
                last.first,
                last.second,
            ) { QuranPage.Word(it.int(0), it.int(1), it.text(2)) }
        val position = compareBy<Pair<Int, Int>>({ it.first }, { it.second })
        val lines =
            rows.map { row ->
                if (row.line.kind != QuranPage.Line.Kind.Ayah) return@map row.line
                row.line.copy(
                    words =
                        words.filter {
                            val at = it.index to it.word
                            position.compare(at, row.first) >= 0 && position.compare(at, row.last) <= 0
                        },
                )
            }
        val verses = readVerses("\"index\" BETWEEN ? AND ?", listOf(first.first, last.first), null).toMap()

        fun division(kind: String) =
            arabicQuery("SELECT max(number) FROM quran_divisions WHERE kind = ? AND start <= ?", kind, last.first) {
                it.int(0)
            }.firstOrNull() ?: 1
        val sajdas =
            arabicQuery("SELECT start FROM quran_sajdas WHERE start BETWEEN ? AND ?", first.first, last.first) {
                it.int(0)
            }.toSet()
        return QuranPage(number, lines, verses, division("juz"), division("hizb"), sajdas)
    }

    private fun verseLocked(
        surah: Int,
        number: Int,
        translation: String?,
    ): Ayah? = readVerses("sura = ? AND aya = ?", listOf(surah, number), translation).firstOrNull()?.second

    /** Arabic rows (blank text means a broken database) with [translation] merged in when it has text. */
    private fun readVerses(
        condition: String,
        parameters: List<Any>,
        translation: String?,
    ): List<Pair<Int, Ayah>> {
        val rows =
            arabicQuery(
                "SELECT \"index\", sura, aya, text FROM quran WHERE $condition ORDER BY sura, aya",
                parameters,
            ) {
                val text = it.text(3)
                if (text.isBlank()) throw QuranUnavailableException()
                it.int(0) to Ayah(it.int(1), it.int(2), text)
            }
        if (rows.isEmpty() || translation == null) return rows
        val ids = rows.map { it.first }
        val values =
            runCatching {
                translationSql(
                    translation,
                )?.query("SELECT \"index\", text FROM quran WHERE \"index\" IN ${inList(ids.size)}", ids) {
                    it.int(0) to it.text(1)
                }
            }.getOrNull()?.toMap().orEmpty()
        return rows.map { (index, ayah) ->
            val text = values[index]?.takeIf { it.isNotBlank() } ?: return@map index to ayah
            index to ayah.copy(translations = mapOf(translation to text))
        }
    }

    private fun translationSql(id: String): ContentSql? = runCatching { translation(id) }.getOrNull()

    private fun arabicSql(): ContentSql = runCatching(arabic).getOrElse { throw QuranUnavailableException(it) }

    private fun <T> arabicQuery(
        sql: String,
        vararg parameters: Any,
        row: (ContentSql.Row) -> T,
    ): List<T> = arabicQuery(sql, parameters.toList(), row)

    private fun <T> arabicQuery(
        sql: String,
        parameters: List<Any>,
        row: (ContentSql.Row) -> T,
    ): List<T> = guarded { arabicSql().query(sql, parameters, row) }

    /** Database errors surface as [QuranUnavailableException]; reference errors and cancellation pass through. */
    private inline fun <T> guarded(block: () -> T): T =
        try {
            block()
        } catch (error: Exception) {
            when (error) {
                is CancellationException, is InvalidReferenceException, is QuranUnavailableException -> throw error
                else -> throw QuranUnavailableException(error)
            }
        }

    private suspend fun <T> locked(block: suspend () -> T): T {
        currentCoroutineContext().ensureActive()
        return mutex.withLock { block() }
    }

    companion object {
        const val VERSE_COUNT = 6236
        private const val TIERS = 2
        private const val CHUNK = 500
        private const val CACHE_SIZE = 8
        private const val MAX_CACHED_LIMIT = 201

        private fun inList(count: Int) = List(count) { "?" }.joinToString(",", "(", ")")

        private fun indexIn(count: Int) = "\"index\" IN ${inList(count)}"

        /** Swift `QuranDatabase.validateTranslation`: 6,236 non-blank verses indexed 1…6236. */
        fun isValidTranslation(sql: ContentSql): Boolean =
            runCatching {
                sql
                    .query("SELECT count(*), min(\"index\"), max(\"index\") FROM quran WHERE trim(text) != ''") {
                        Triple(it.int(0), it.int(1), it.int(2))
                    }.firstOrNull() == Triple(VERSE_COUNT, 1, VERSE_COUNT)
            }.getOrDefault(false)
    }
}

package com.aljaroudi.muntathir.core.rulings

import com.aljaroudi.muntathir.core.hadith.HadithDatabaseException
import com.aljaroudi.muntathir.core.highlight.RulingID
import com.aljaroudi.muntathir.core.sql.ContentSql
import com.aljaroudi.muntathir.core.sql.SqlDriver
import com.aljaroudi.muntathir.core.sql.query
import com.aljaroudi.muntathir.core.text.QuranSearchText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.net.URI
import java.util.Locale

/** One question and answer. Port of Swift `Rulings`. */
data class Ruling(
    val id: RulingID,
    val question: String,
    val answer: String,
    /** The official page, when it's an https URL with a host. */
    val source: String?,
    val context: String = "",
    val kind: String = "qa",
) {
    val preview: String get() = if (kind == "qa") question else "$question · ${answer.take(160)}"
}

data class RulingFootnote(
    val id: Long,
    val label: String,
    val body: String,
    val chapter: Boolean,
)

data class RulingsAuthority(
    val id: String,
    val arabic: String,
    val english: String,
) {
    fun name(locale: Locale) = if (locale.language == "ar") arabic else english
}

data class RulingsLanguage(
    val id: String,
    val name: String,
    val rightToLeft: Boolean,
)

data class RulingsSection(
    val id: Long,
    val title: String,
)

/**
 * Questions by authority and language, by section or full-text search. Port of Swift `RulingsReader` (an actor):
 * calls are serialized on [io] over one open connection.
 */
class RulingsReader(
    private val driver: SqlDriver,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private var packVersion = 1
    private val columns get() = QUESTION_COLUMNS + if (packVersion == 2) ", q.context, q.kind" else ", '', 'qa'"
    private val mutex = Mutex()
    private var connection: ContentSql? = null

    /** Opens [file] once it passes the schema and integrity checks, or closes the current one. */
    suspend fun install(file: File?) =
        locked {
            runCatching { connection?.close() }
            connection = null
            if (file == null) return@locked
            val sql = guarded { driver.open(file, writable = false) }
            try {
                guarded { validate(sql) }
            } catch (error: Exception) {
                sql.close()
                throw error
            }
            connection = sql
        }

    private fun validate(sql: ContentSql) {
        val identity = sql.query("PRAGMA application_id") { it.int(0) }.firstOrNull()
        val version = sql.query("PRAGMA user_version") { it.int(0) }.firstOrNull()
        if (identity != APPLICATION_ID || version !in 1..VERSION) throw HadithDatabaseException.Incompatible()
        if (sql.query("PRAGMA quick_check") { it.text(0) } != listOf("ok") ||
            sql.query("PRAGMA foreign_key_check") { it.text(0) }.isNotEmpty()
        ) {
            throw HadithDatabaseException.Incompatible()
        }
        packVersion = version ?: throw HadithDatabaseException.Incompatible()
        sql.query("SELECT code, name_ar, name_en, sort_order FROM authority LIMIT 1") { it.text(0) }
        sql.query("SELECT code, name, direction FROM language LIMIT 1") { it.text(0) }
        sql.query("SELECT id, title, parent_id FROM topic LIMIT 1") { it.text(0) }
        sql.query("SELECT topic_id, question_id, position FROM placement LIMIT 1") { it.text(0) }
        sql.query(
            "SELECT authority_code, language_code, site_id, question, answer, url FROM question LIMIT 1",
        ) { it.text(0) }
        sql.query("SELECT $columns FROM question q LIMIT 0", row = ::ruling)
        sql.query("SELECT rowid FROM question_fts WHERE question_fts MATCH ? LIMIT 1", "test") { it.long(0) }
    }

    suspend fun authorities(): List<RulingsAuthority> =
        read { sql ->
            sql.query("SELECT code, name_ar, name_en FROM authority ORDER BY sort_order") {
                RulingsAuthority(it.text(0), it.text(1), it.text(2))
            }
        }

    /** The languages [authority] has questions in. */
    suspend fun languages(authority: String): List<RulingsLanguage> =
        read { sql ->
            sql.query(
                "SELECT code, name, direction FROM language WHERE code IN " +
                    "(SELECT DISTINCT language_code FROM question WHERE authority_code = ?) ORDER BY code",
                authority,
            ) { RulingsLanguage(it.text(0), it.text(1), it.text(2) == "rtl") }
        }

    suspend fun contents(
        authority: String,
        language: String,
        parent: Long? = null,
    ): List<RulingsSection> =
        read { sql ->
            fun children(id: Long?): List<RulingsSection> =
                sql.query(
                    "SELECT id,title FROM topic WHERE authority_code=? AND language_code=? AND " +
                        (if (id == null) "parent_id IS NULL" else "parent_id=?") + " ORDER BY position,id",
                    listOfNotNull(authority, language, id),
                ) { RulingsSection(it.long(0), it.text(1)) }
            val sections = children(parent)
            if (packVersion == 2 && parent == null && sections.size == 1) children(sections.single().id) else sections
        }

    suspend fun footnotes(id: RulingID): List<RulingFootnote> =
        read { sql ->
            if (sql
                    .query("SELECT 1 FROM sqlite_master WHERE type='table' AND name='footnote'") {
                        it.int(0)
                    }.isEmpty()
            ) {
                return@read emptyList()
            }
            sql.query(
                """SELECT f.rowid,f.label,f.body,f.entry_id IS NULL FROM entry e
            JOIN placement p ON p.question_id=e.id JOIN footnote f ON f.topic_id=p.topic_id
            WHERE e.authority_code=? AND e.language_code=? AND e.site_id=?
              AND (f.entry_id=e.id OR f.entry_id IS NULL) ORDER BY f.rowid""",
                id.authority,
                id.language,
                id.siteID,
            ) { RulingFootnote(it.long(0), it.text(1), it.text(2), it.int(3) != 0) }
        }

    /** The main sections a question sits under; old packs with nested topics resolve to the same ones. */
    suspend fun sections(id: RulingID): List<RulingsSection> =
        read { sql ->
            if (packVersion == 2) {
                return@read sql.query(
                    """SELECT t.id,t.title FROM topic t JOIN placement p ON p.topic_id=t.id
                       JOIN question q ON q.id=p.question_id WHERE q.authority_code=? AND q.language_code=?
                       AND q.site_id=? ORDER BY t.position,t.id""",
                    id.authority,
                    id.language,
                    id.siteID,
                ) { RulingsSection(it.long(0), it.text(1)) }
            }
            sql.query(
                """
                WITH RECURSIVE sections(id, parent_id, title, position) AS (
                    SELECT t.id, t.parent_id, t.title, t.position FROM topic t
                    JOIN placement p ON p.topic_id = t.id
                    JOIN question q ON q.id = p.question_id
                    WHERE q.authority_code = ?1 AND q.language_code = ?2 AND q.site_id = ?3
                      AND t.authority_code = ?1 AND t.language_code = ?2
                    UNION
                    SELECT t.id, t.parent_id, t.title, t.position FROM topic t
                    JOIN sections s ON s.parent_id = t.id
                    WHERE t.authority_code = ?1 AND t.language_code = ?2
                )
                SELECT id, title FROM sections WHERE parent_id IS NULL ORDER BY position, id
                """.trimIndent(),
                id.authority,
                id.language,
                id.siteID,
            ) { RulingsSection(it.long(0), it.text(1)) }
        }

    /** Every question in [section] and its subsections, in the source's order. */
    suspend fun questions(
        authority: String,
        language: String,
        section: RulingsSection,
    ): List<Ruling> =
        read { sql ->
            sql.query(
                """
                WITH RECURSIVE sections(id) AS (
                    SELECT id FROM topic WHERE authority_code = ?1 AND language_code = ?2 AND id = ?3
                    UNION
                    SELECT t.id FROM topic t JOIN sections s ON t.parent_id = s.id
                    WHERE t.authority_code = ?1 AND t.language_code = ?2 AND ${if (packVersion == 1) "1" else "0"}
                )
                SELECT $columns
                FROM question q JOIN placement p ON p.question_id = q.id JOIN sections s ON s.id = p.topic_id
                WHERE q.authority_code = ?1 AND q.language_code = ?2
                GROUP BY q.id ORDER BY MIN(p.position), q.site_id
                """.trimIndent(),
                authority,
                language,
                section.id,
                row = ::ruling,
            )
        }

    /** Twenty random questions, or up to 100 matching every whitespace-separated term, best first. */
    suspend fun questions(
        authority: String,
        language: String,
        query: String = "",
    ): List<Ruling> =
        read { sql ->
            val words = QuranSearchText.searchQuery(query).split(Regex("\\s+")).filter { it.isNotEmpty() }
            val terms = words.map { "\"" + it.replace("\"", "\"\"") + "\"" }
            val select = "SELECT $columns FROM question q"
            if (terms.isEmpty()) {
                sql.query(
                    "$select WHERE q.authority_code = ? AND q.language_code = ? ORDER BY random() LIMIT 20",
                    authority,
                    language,
                    row = ::ruling,
                )
            } else {
                sql.query(
                    "$select JOIN question_fts f ON f.rowid = q.id " +
                        "WHERE q.authority_code = ? AND q.language_code = ? AND question_fts MATCH ? " +
                        "ORDER BY bm25(question_fts), q.site_id LIMIT 100",
                    authority,
                    language,
                    terms.joinToString(" AND "),
                    row = ::ruling,
                )
            }
        }

    suspend fun question(id: RulingID): Ruling? =
        read { sql ->
            sql
                .query(
                    "SELECT $columns FROM question q " +
                        "WHERE authority_code = ? AND language_code = ? AND site_id = ?",
                    id.authority,
                    id.language,
                    id.siteID,
                    row = ::ruling,
                ).firstOrNull()
        }

    private suspend fun <T> read(block: suspend (ContentSql) -> T): T =
        locked { guarded { block(connection ?: throw HadithDatabaseException.Unavailable()) } }

    private suspend fun <T> locked(block: suspend () -> T): T {
        currentCoroutineContext().ensureActive()
        return mutex.withLock { withContext(io) { block() } }
    }

    private inline fun <T> guarded(block: () -> T): T =
        try {
            block()
        } catch (error: HadithDatabaseException) {
            throw error
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw HadithDatabaseException.Unavailable(error)
        }

    companion object {
        const val APPLICATION_ID = 1_179_809_601
        const val VERSION = 2
        private const val QUESTION_COLUMNS = "q.authority_code, q.language_code, q.site_id, q.question, q.answer, q.url"

        /** The saved language when the authority has it, else the app language when it does, else none. */
        fun preferredLanguage(
            saved: String?,
            locale: Locale,
            available: List<RulingsLanguage>,
        ): String? {
            if (saved != null && available.any { it.id == saved }) return saved
            return available.firstOrNull { it.id == locale.language }?.id
        }

        private fun ruling(row: ContentSql.Row) =
            Ruling(
                RulingID(row.text(0), row.text(1), row.text(2)),
                row.text(3),
                row.text(4),
                row.text(5).takeIf {
                    runCatching { URI(it) }.getOrNull()?.let { uri ->
                        uri.scheme == "https" && !uri.host.isNullOrEmpty()
                    } ==
                        true
                },
                row.text(6),
                row.text(7),
            )
    }
}

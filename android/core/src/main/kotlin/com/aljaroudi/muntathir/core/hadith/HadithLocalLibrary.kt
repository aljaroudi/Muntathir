package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.sql.ContentSql
import com.aljaroudi.muntathir.core.sql.SqlDriver
import com.aljaroudi.muntathir.core.sql.execute
import com.aljaroudi.muntathir.core.sql.query
import com.aljaroudi.muntathir.core.sql.quotedIdentifier
import com.aljaroudi.muntathir.core.sql.use
import com.aljaroudi.muntathir.core.text.QuranSearchText
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/**
 * The app-owned copy of a pack's database, from which single books can be removed and restored. Port of Swift
 * `HadithLocalLibrary`: hosted packs are immutable, so each change prepares a staged copy that
 * [HadithReader.commit] swaps in; the current library stays readable until then.
 */
class HadithLocalLibrary(
    val root: File,
    private val driver: SqlDriver,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    /** Reserves room for a copy of [bytes] next to the library, or throws when there isn't enough. */
    private val reserveSpace: (directory: File, bytes: Long) -> Unit = { _, _ -> },
) {
    private val mutex = Mutex()

    val file: File get() = File(root, "library.db")

    suspend fun localFile(): File? = locked { file.takeIf(File::isFile) }

    /** Every title the library has held, with estimated sizes for installed ones. */
    suspend fun books(includeEstimates: Boolean = true): List<DownloadedBook> = locked { booksLocked(includeEstimates) }

    private fun booksLocked(includeEstimates: Boolean): List<DownloadedBook> {
        if (!file.isFile) return emptyList()
        return HadithDatabase.guarded {
            driver.use(file) { sql ->
                val weights = if (includeEstimates) contentSizes(sql) else emptyMap()
                val total = weights.values.sum()
                val bytes = file.length()
                sql.query(
                    """
                    SELECT c.id, c.name_ar, c.name_en, EXISTS(
                        SELECT 1 FROM hadith h JOIN book b ON b.id=h.book_id WHERE b.collection_id=c.id
                    ) FROM download_catalog c ORDER BY c.sort_order, c.id
                    """.trimIndent(),
                ) {
                    val installed = it.int(3) != 0
                    val weight = weights[it.text(0)] ?: 0
                    DownloadedBook(
                        id = it.text(0),
                        arabic = it.text(1),
                        english = it.text(2),
                        installed = installed,
                        estimatedBytes =
                            if (total > 0 && installed) (bytes.toDouble() * weight / total).toLong() else null,
                    )
                }
            }
        }
    }

    /** Books share pages and search indexes, so actual storage is apportioned by each book's content bytes. */
    private fun contentSizes(sql: ContentSql): Map<String, Long> {
        val tables =
            sql.query(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            ) { it.text(0) }
        val installed =
            sql
                .query(
                    "SELECT DISTINCT b.collection_id FROM hadith h JOIN book b ON b.id=h.book_id",
                ) { it.text(0) }
                .toSet()
        val sizes = mutableMapOf<String, Long>()
        for (table in tables) {
            val name = quotedIdentifier(table)
            val columns = sql.query("PRAGMA table_info($name)") { it.text(1) }
            val join =
                when (table) {
                    "hadith", "chapter", "introduction" -> {
                        "JOIN book b ON b.id=t.book_id"
                    }

                    "book" -> {
                        "JOIN book b ON b.id=t.id"
                    }

                    else -> {
                        if ("hadith_id" !in columns) continue
                        "JOIN hadith h ON h.id=t.hadith_id JOIN book b ON b.id=h.book_id"
                    }
                }
            val weight = columns.joinToString("+") { "COALESCE(length(CAST(t.${quotedIdentifier(it)} AS BLOB)),0)" }
            sql
                .query("SELECT b.collection_id, SUM($weight) FROM $name t $join GROUP BY b.collection_id") {
                    it.text(0) to it.long(1)
                }.filter { it.first in installed }
                .forEach { (id, bytes) -> sizes[id] = (sizes[id] ?: 0) + bytes }
        }
        return sizes
    }

    /**
     * A validated copy of [source] in [root], keeping the current choices: books already removed stay removed,
     * except [restoring]; [removing] is removed too. The caller commits the returned file, or deletes it.
     */
    suspend fun prepare(
        source: File,
        restoring: String? = null,
        removing: String? = null,
    ): File =
        locked {
            root.mkdirs()
            root.listFiles { file -> file.name.startsWith("staging-") }?.forEach(File::delete)
            val stage = File(root, "staging-${UUID.randomUUID()}.db")
            // The previous database stays usable until the whole replacement validates.
            try {
                val excluded =
                    booksLocked(
                        includeEstimates = false,
                    ).filterNot { it.installed }.map { it.id }.toMutableSet()
                restoring?.let(excluded::remove)
                removing?.let(excluded::add)
                reserveSpace(root, source.length())
                checkActive()
                source.copyTo(stage, overwrite = true)
                HadithDatabase.guarded { driver.use(stage, writable = true) { prepareDatabase(it, excluded) } }
                HadithDatabase.guarded {
                    driver.use(stage) { sql ->
                        if (sql.query("PRAGMA integrity_check") { it.text(0) } != listOf("ok")) {
                            throw HadithDatabaseException.Unavailable()
                        }
                        HadithDatabase.validate(sql)
                    }
                }
                checkActive()
                stage
            } catch (error: Throwable) {
                stage.delete()
                throw error
            }
        }

    private suspend fun prepareDatabase(
        sql: ContentSql,
        titles: Set<String>,
    ) {
        sql.execute("CREATE TABLE IF NOT EXISTS download_catalog AS SELECT * FROM collection")
        if (titles.isEmpty()) return
        sql.execute("CREATE TEMP TABLE removed_hadith(id INTEGER PRIMARY KEY)")
        for (title in titles) {
            sql.execute(
                "INSERT INTO removed_hadith SELECT h.id FROM hadith h JOIN book b ON b.id=h.book_id WHERE b.collection_id=?",
                title,
            )
        }
        // Dependent content first, including optional grading, translation and morphology tables.
        val tables =
            sql.query(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            ) { it.text(0) }
        for (table in tables) {
            checkActive()
            val name = quotedIdentifier(table)
            if ("hadith_id" in sql.query("PRAGMA table_info($name)") { it.text(1) }) {
                sql.execute("DELETE FROM $name WHERE hadith_id IN (SELECT id FROM removed_hadith)")
            }
        }
        for (title in titles) {
            sql.execute("DELETE FROM introduction WHERE book_id IN (SELECT id FROM book WHERE collection_id=?)", title)
        }
        sql.execute("DELETE FROM hadith WHERE id IN (SELECT id FROM removed_hadith)")
        sql.execute("UPDATE chapter SET hadith_count=(SELECT count(*) FROM hadith WHERE chapter_id=chapter.id)")
        // Contentless indexes can't use ordinary DELETE: rebuild them from the retained text.
        sql.execute("DROP TABLE IF EXISTS hadith_partial")
        sql.execute("DROP TABLE IF EXISTS hadith_fts")
        sql.execute("PRAGMA user_version=8")
        sql.execute("INSERT INTO hadith_words(hadith_words) VALUES('delete-all')")
        // Bounded batches keep memory flat even for the largest libraries.
        var cursor = Long.MIN_VALUE
        while (true) {
            checkActive()
            val rows =
                sql.query("SELECT id, arabic FROM hadith WHERE id > ? ORDER BY id LIMIT 500", cursor) {
                    it.long(0) to it.text(1)
                }
            if (rows.isEmpty()) break
            sql.execute("BEGIN")
            for ((id, arabic) in rows) {
                sql.execute("INSERT INTO hadith_words(rowid,text) VALUES(?,?)", id, QuranSearchText.normalize(arabic))
                cursor = id
            }
            sql.execute("COMMIT")
        }
        sql.execute("INSERT INTO hadith_en(hadith_en) VALUES('rebuild')")
        for (table in listOf("hadith_words", "hadith_en")) {
            sql.execute("INSERT INTO $table($table) VALUES('optimize')")
        }
        checkActive()
        sql.execute("VACUUM")
    }

    /** Deletes the library and anything staged. */
    suspend fun remove() =
        locked {
            if (root.exists() && !root.deleteRecursively()) throw HadithDatabaseException.Unavailable()
        }

    private suspend fun checkActive() = currentCoroutineContext().ensureActive()

    private suspend fun <T> locked(block: suspend () -> T): T {
        currentCoroutineContext().ensureActive()
        return mutex.withLock { withContext(io) { block() } }
    }
}

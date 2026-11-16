package com.aljaroudi.muntathir.data

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import androidx.sqlite.execSQL
import com.aljaroudi.muntathir.core.text.QuranSearchText
import java.io.File

class HadithDatabaseException(
    message: String,
) : Exception(message)

data class HadithMatch(
    val id: Long,
    /** 0: the whole query appears as a phrase; 1: every word appears. */
    val tier: Int,
)

/**
 * Read-only hadith or supplications database from an asset pack, opened with the bundled SQLite build so
 * FTS5 is always available. Not thread-safe; use from one thread (e.g. a single-threaded dispatcher).
 */
class HadithDatabase private constructor(
    private val connection: SQLiteConnection,
) : AutoCloseable {
    val userVersion: Int = scalar("PRAGMA user_version").toInt()

    /** Literal word search over the Arabic and English indexes, phrase matches first. */
    fun search(
        query: String,
        limit: Int = 50,
    ): List<HadithMatch> {
        val terms = QuranSearchText.terms(query)
        if (terms.isEmpty()) return emptyList()
        // Quoting every term keeps user input out of FTS syntax; terms() never contains quotes.
        val words = terms.joinToString(" AND ") { "\"$it\"" }
        val phrase = "\"${terms.joinToString(" ")}\""
        return connection.prepare(SEARCH).use { statement ->
            statement.bindText(1, words)
            statement.bindText(2, phrase)
            statement.bindLong(3, limit.toLong())
            buildList { while (statement.step()) add(HadithMatch(statement.getLong(0), statement.getLong(1).toInt())) }
        }
    }

    fun count(): Long = scalar("SELECT count(*) FROM hadith")

    override fun close() = connection.close()

    private fun scalar(sql: String): Long =
        connection.prepare(sql).use { statement ->
            statement.step()
            statement.getLong(0)
        }

    companion object {
        const val APPLICATION_ID = 1230262606L
        val supportedVersions = 7..8

        private const val SEARCH = """
            WITH matches AS (
              SELECT rowid AS id FROM hadith_words WHERE hadith_words MATCH ?1
              UNION SELECT rowid FROM hadith_en WHERE hadith_en MATCH ?1
            ), phrases AS (
              SELECT rowid AS id FROM hadith_words WHERE hadith_words MATCH ?2
              UNION SELECT rowid FROM hadith_en WHERE hadith_en MATCH ?2
            )
            SELECT h.id, CASE WHEN h.id IN (SELECT id FROM phrases) THEN 0 ELSE 1 END AS tier
            FROM hadith h WHERE h.id IN (SELECT id FROM matches)
            ORDER BY tier, h.book_id, h.id_in_book, h.id
            LIMIT ?3
        """

        private val driver = BundledSQLiteDriver()

        /** Opens [file] read-only and checks it is a supported hadith database with working FTS indexes. */
        fun open(file: File): HadithDatabase {
            if (!file.isFile) throw HadithDatabaseException("Missing ${file.name}")
            val connection = driver.open(file.absolutePath, SQLITE_OPEN_READONLY)
            try {
                val database = HadithDatabase(connection)
                val applicationId = database.scalar("PRAGMA application_id")
                if (applicationId != APPLICATION_ID || database.userVersion !in supportedVersions) {
                    throw HadithDatabaseException("Unsupported database ($applicationId v${database.userVersion})")
                }
                // Probe both indexes so a damaged pack fails here rather than mid-search.
                connection.execSQL("SELECT rowid FROM hadith_words WHERE hadith_words MATCH 'test' LIMIT 1")
                connection.execSQL("SELECT rowid FROM hadith_en WHERE hadith_en MATCH 'test' LIMIT 1")
                return database
            } catch (error: Exception) {
                connection.close()
                throw error
            }
        }
    }
}

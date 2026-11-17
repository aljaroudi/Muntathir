package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.sql.ContentSql
import com.aljaroudi.muntathir.core.sql.SqlDriver
import com.aljaroudi.muntathir.core.sql.query
import com.aljaroudi.muntathir.core.sql.use
import java.io.File

/** Swift `HadithDatabaseError`. */
sealed class HadithDatabaseException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause) {
    /** No library is installed, or it can't be read. */
    class Unavailable(
        cause: Throwable? = null,
    ) : HadithDatabaseException("Hadith database unavailable", cause)

    class InvalidReference : HadithDatabaseException("Invalid hadith reference")

    /** A database from another app or schema version. */
    class Incompatible : HadithDatabaseException("Incompatible hadith database")
}

/** Schema checks for hadith and supplication databases. Port of Swift `HadithDatabase.validate`. */
object HadithDatabase {
    const val APPLICATION_ID = 1_230_262_606
    val SUPPORTED_VERSIONS = 7..8

    /** Identity, version and a probe of every table the reader uses, including both search indexes. */
    fun validate(sql: ContentSql) {
        val identity = sql.query("PRAGMA application_id") { it.int(0) }.firstOrNull()
        val version = sql.query("PRAGMA user_version") { it.int(0) }.firstOrNull()
        if (identity != APPLICATION_ID || version !in SUPPORTED_VERSIONS) throw HadithDatabaseException.Incompatible()
        sql.query(
            "SELECT h.id, h.source_id, c.file_name, g.grade_ar FROM hadith h JOIN chapter c ON c.id = h.chapter_id " +
                "LEFT JOIN hadith_grading g ON g.hadith_id = h.id LIMIT 1",
        ) { it.int(0) }
        sql.query("SELECT id FROM introduction LIMIT 1") { it.int(0) }
        sql.query("SELECT words, display_number FROM hadith_reading LIMIT 1") { it.int(0) }
        for (table in listOf("hadith_words", "hadith_en")) {
            sql.query("SELECT rowid FROM $table WHERE $table MATCH ? LIMIT 1", "test") { it.int(0) }
        }
    }

    /** [validate] on a fresh read-only connection; unreadable files are [HadithDatabaseException.Unavailable]. */
    fun validate(
        driver: SqlDriver,
        file: File,
    ) = guarded { driver.use(file) { validate(it) } }

    /** The background integrity scan: [validate] plus SQLite's `quick_check` of every page. */
    fun scan(
        driver: SqlDriver,
        file: File,
    ) = guarded {
        driver.use(file) { sql ->
            validate(sql)
            if (sql.query("PRAGMA quick_check") { it.text(0) } !=
                listOf("ok")
            ) {
                throw HadithDatabaseException.Unavailable()
            }
        }
    }

    /** SQLite errors surface as [HadithDatabaseException.Unavailable]; cancellation and our own errors pass through. */
    internal inline fun <T> guarded(block: () -> T): T =
        try {
            block()
        } catch (error: HadithDatabaseException) {
            throw error
        } catch (error: kotlinx.coroutines.CancellationException) {
            throw error
        } catch (error: Exception) {
            throw HadithDatabaseException.Unavailable(error)
        }
}

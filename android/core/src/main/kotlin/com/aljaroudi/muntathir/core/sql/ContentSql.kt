package com.aljaroudi.muntathir.core.sql

import java.io.File

/**
 * A SQLite connection to a content database: the app adapts the bundled Android driver, tests adapt JDBC.
 * Not thread-safe; callers confine each connection to one thread at a time.
 */
interface ContentSql : AutoCloseable {
    /** Runs [sql] with positional [parameters] (`Int`, `Long`, `String` or `null`) and maps each row. */
    fun <T> query(
        sql: String,
        parameters: List<Any?>,
        row: (Row) -> T,
    ): List<T>

    /** Runs a statement that returns no rows, such as `DELETE`, `PRAGMA user_version=8` or `VACUUM`. */
    fun execute(
        sql: String,
        parameters: List<Any?> = emptyList(),
    )

    override fun close() = Unit

    interface Row {
        fun int(column: Int): Int

        fun long(column: Int): Long

        /** The column as text; `""` for NULL. */
        fun text(column: Int): String

        fun isNull(column: Int): Boolean

        fun intOrNull(column: Int): Int? = if (isNull(column)) null else int(column)

        fun textOrNull(column: Int): String? = if (isNull(column)) null else text(column)
    }
}

fun <T> ContentSql.query(
    sql: String,
    vararg parameters: Any?,
    row: (ContentSql.Row) -> T,
): List<T> = query(sql, parameters.toList(), row)

fun ContentSql.execute(
    sql: String,
    vararg parameters: Any?,
) = execute(sql, parameters.toList())

/** Opens content databases at a path. */
fun interface SqlDriver {
    /** Opens [file]; read-only unless [writable]. Throws when the file can't be opened. */
    fun open(
        file: File,
        writable: Boolean,
    ): ContentSql
}

/** Runs [block] on a connection to [file], closing it afterwards. */
inline fun <T> SqlDriver.use(
    file: File,
    writable: Boolean = false,
    block: (ContentSql) -> T,
): T = open(file, writable).use(block)

/** `"name"` with embedded quotes doubled, for table and column names. */
fun quotedIdentifier(name: String) = "\"" + name.replace("\"", "\"\"") + "\""

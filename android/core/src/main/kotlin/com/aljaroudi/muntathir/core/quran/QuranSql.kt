package com.aljaroudi.muntathir.core.quran

/** A read-only SQLite connection: the app adapts the bundled Android driver, tests adapt JDBC. */
interface QuranSql {
    /** Runs [sql] with positional [parameters] (`Int`, `Long` or `String`) and maps each row. */
    fun <T> query(
        sql: String,
        parameters: List<Any>,
        row: (Row) -> T,
    ): List<T>

    interface Row {
        fun int(column: Int): Int

        /** The column as text; `""` for NULL. */
        fun text(column: Int): String
    }
}

fun <T> QuranSql.query(
    sql: String,
    vararg parameters: Any,
    row: (QuranSql.Row) -> T,
): List<T> = query(sql, parameters.toList(), row)

/** The bundled Arabic database is missing or unreadable, or an optional database is invalid. */
class QuranUnavailableException(
    cause: Throwable? = null,
) : Exception("Quran database unavailable", cause)

package com.aljaroudi.muntathir.data

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READWRITE
import androidx.sqlite.execSQL
import com.aljaroudi.muntathir.core.sql.ContentSql
import com.aljaroudi.muntathir.core.sql.SqlDriver
import java.io.File

/** [ContentSql] over a bundled-driver connection (the platform SQLite lacks FTS5). */
class BundledContentSql(
    private val connection: SQLiteConnection,
) : ContentSql {
    override fun <T> query(
        sql: String,
        parameters: List<Any?>,
        row: (ContentSql.Row) -> T,
    ): List<T> =
        connection.prepare(sql).use { statement ->
            statement.bindAll(parameters)
            val adapter =
                object : ContentSql.Row {
                    override fun int(column: Int) = statement.getLong(column).toInt()

                    override fun long(column: Int) = statement.getLong(column)

                    override fun text(column: Int) = if (statement.isNull(column)) "" else statement.getText(column)

                    override fun isNull(column: Int) = statement.isNull(column)
                }
            buildList { while (statement.step()) add(row(adapter)) }
        }

    override fun execute(
        sql: String,
        parameters: List<Any?>,
    ) {
        if (parameters.isEmpty()) {
            connection.execSQL(sql)
            return
        }
        connection.prepare(sql).use { statement ->
            statement.bindAll(parameters)
            @Suppress("ControlFlowWithEmptyBody")
            while (statement.step()) {
            }
        }
    }

    override fun close() = connection.close()

    private fun SQLiteStatement.bindAll(parameters: List<Any?>) =
        parameters.forEachIndexed { offset, value ->
            when (value) {
                null -> bindNull(offset + 1)
                is Int -> bindLong(offset + 1, value.toLong())
                is Long -> bindLong(offset + 1, value)
                else -> bindText(offset + 1, value.toString())
            }
        }

    /** Opens databases with the bundled driver. */
    object Driver : SqlDriver {
        private val driver = BundledSQLiteDriver()

        override fun open(
            file: File,
            writable: Boolean,
        ): ContentSql =
            BundledContentSql(
                driver.open(file.absolutePath, if (writable) SQLITE_OPEN_READWRITE else SQLITE_OPEN_READONLY),
            )

        /** The raw connection, for callers that keep it open across reads. */
        fun connection(file: File): SQLiteConnection = driver.open(file.absolutePath, SQLITE_OPEN_READONLY)
    }
}

package com.aljaroudi.muntathir.core.sql

import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.sql.PreparedStatement
import java.sql.ResultSet

/**
 * [ContentSql] over sqlite-jdbc (which has FTS5). By default each call opens its own connection, like Swift's
 * `QuranConnection`; [JdbcDriver] keeps one open connection, like the app's bundled driver.
 */
open class JdbcContentSql(
    private val file: File,
    private val readOnly: Boolean = true,
    private val missing: () -> Exception = { IllegalStateException("Missing database ${file.name}") },
) : ContentSql {
    private var held: Connection? = null

    /** Keeps one connection open until [close]; transactions span calls. */
    fun hold(): JdbcContentSql = apply { held = open() }

    override fun <T> query(
        sql: String,
        parameters: List<Any?>,
        row: (ContentSql.Row) -> T,
    ): List<T> =
        connection { connection ->
            connection.prepareStatement(sql).use { statement ->
                statement.bind(parameters)
                if (!statement.execute()) return@use emptyList()
                statement.resultSet.use { result ->
                    val adapter = Row(result)
                    buildList { while (result.next()) add(row(adapter)) }
                }
            }
        }

    override fun execute(
        sql: String,
        parameters: List<Any?>,
    ) {
        connection { connection ->
            connection.prepareStatement(sql).use { statement ->
                statement.bind(parameters)
                statement.execute()
            }
        }
    }

    override fun close() {
        held?.close()
        held = null
    }

    private fun <T> connection(block: (Connection) -> T): T {
        held?.let { return block(it) }
        return open().use(block)
    }

    /** Read-only connections need an existing file; writable ones create it. */
    private fun open(): Connection {
        if (readOnly && !file.isFile) throw missing()
        return DriverManager.getConnection("jdbc:sqlite:file:${file.absolutePath}${if (readOnly) "?mode=ro" else ""}")
    }

    private fun PreparedStatement.bind(parameters: List<Any?>) =
        parameters.forEachIndexed { index, value -> setObject(index + 1, value) }

    private class Row(
        private val result: ResultSet,
    ) : ContentSql.Row {
        override fun int(column: Int) = result.getInt(column + 1)

        override fun long(column: Int) = result.getLong(column + 1)

        override fun text(column: Int): String = result.getString(column + 1).orEmpty()

        override fun isNull(column: Int) = result.getObject(column + 1) == null
    }
}

/** One open connection per database, like the app's bundled driver. */
object JdbcDriver : SqlDriver {
    override fun open(
        file: File,
        writable: Boolean,
    ): ContentSql = JdbcContentSql(file, readOnly = !writable).hold()
}

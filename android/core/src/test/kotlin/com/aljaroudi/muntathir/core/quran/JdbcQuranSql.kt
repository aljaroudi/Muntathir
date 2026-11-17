package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.Fixtures
import kotlinx.serialization.json.Json
import java.io.File
import java.sql.Connection
import java.sql.DriverManager
import java.sql.ResultSet

/** [QuranSql] over sqlite-jdbc (which has FTS5), opened per query like Swift's `QuranConnection`. */
class JdbcQuranSql(
    private val file: File,
    private val readOnly: Boolean = true,
) : QuranSql {
    override fun <T> query(
        sql: String,
        parameters: List<Any>,
        row: (QuranSql.Row) -> T,
    ): List<T> {
        if (!file.isFile) throw QuranUnavailableException()
        return open().use { connection ->
            connection.prepareStatement(sql).use { statement ->
                parameters.forEachIndexed { index, value -> statement.setObject(index + 1, value) }
                if (!statement.execute()) return@use emptyList()
                statement.resultSet.use { result ->
                    val adapter = Row(result)
                    buildList { while (result.next()) add(row(adapter)) }
                }
            }
        }
    }

    fun execute(
        sql: String,
        vararg parameters: Any,
    ) {
        open().use { connection ->
            connection.prepareStatement(sql).use { statement ->
                parameters.forEachIndexed { index, value -> statement.setObject(index + 1, value) }
                statement.execute()
            }
        }
    }

    private fun open(): Connection =
        DriverManager.getConnection("jdbc:sqlite:file:${file.absolutePath}${if (readOnly) "?mode=ro" else ""}")

    private class Row(
        private val result: ResultSet,
    ) : QuranSql.Row {
        override fun int(column: Int) = result.getInt(column + 1)

        override fun text(column: Int): String = result.getString(column + 1).orEmpty()
    }

    companion object {
        val quranFolder: File get() = Fixtures.repository("apple/Muntathir/Resources/Quran")

        val surahs: List<QuranSurah> by lazy {
            Json { ignoreUnknownKeys = true }
                .decodeFromString(Fixtures.repository("apple/Muntathir/Resources/quran-surahs.json").readText())
        }

        /** A reader over the iOS bundle's databases, with every translation installed. */
        fun bundledReader(translations: Map<String, File> = allTranslations()): QuranReader =
            QuranReader(
                arabic = { JdbcQuranSql(quranFolder.resolve("quran.db")) },
                surahs = { surahs },
                translation = { id -> translations[id]?.let(::JdbcQuranSql) },
            )

        fun allTranslations(): Map<String, File> =
            quranFolder
                .listFiles { file -> file.extension == "db" && file.name != "quran.db" }
                .orEmpty()
                .associateBy { it.nameWithoutExtension }
    }
}

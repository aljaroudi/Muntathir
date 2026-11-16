package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.Fixtures
import kotlinx.serialization.json.Json
import java.sql.Connection
import java.sql.DriverManager

/** Reads mushaf pages from the bundled iOS `quran.db` with the same queries as Swift `QuranDatabase`. */
object QuranTestDatabase {
    private val connection: Connection by lazy {
        val file = Fixtures.repository("apple/Muntathir/Resources/Quran/quran.db")
        DriverManager.getConnection("jdbc:sqlite:file:${file.absolutePath}?mode=ro")
    }

    val surahs: List<QuranSurah> by lazy {
        Json {
            ignoreUnknownKeys = true
        }.decodeFromString(Fixtures.repository("apple/Muntathir/Resources/quran-surahs.json").readText())
    }

    fun page(number: Int): QuranPage {
        class Bounds(
            val line: QuranPage.Line,
            val first: Pair<Int, Int>,
            val last: Pair<Int, Int>,
        )
        val rows =
            query(
                "SELECT line, type, centered, sura, first_index, first_word, last_index, last_word FROM quran_lines WHERE page = ? ORDER BY line",
                number,
            ) {
                Bounds(
                    QuranPage.Line(
                        it.getInt(1),
                        QuranPage.Line.Kind.of(it.getString(2)),
                        it.getInt(3) != 0,
                        it.getInt(4),
                    ),
                    it.getInt(5) to it.getInt(6),
                    it.getInt(7) to it.getInt(8),
                )
            }
        val ayahs = rows.filter { it.line.kind == QuranPage.Line.Kind.Ayah }
        val first = ayahs.first().first
        val last = ayahs.last().last
        val words =
            query(
                "SELECT \"index\", word, text FROM quran_words_qpc WHERE (\"index\", word) BETWEEN (?, ?) AND (?, ?) ORDER BY \"index\", word",
                first.first,
                first.second,
                last.first,
                last.second,
            ) { QuranPage.Word(it.getInt(1), it.getInt(2), it.getString(3)) }
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
        val verses =
            query(
                "SELECT \"index\", sura, aya, text FROM quran WHERE \"index\" BETWEEN ? AND ?",
                first.first,
                last.first,
            ) {
                it.getInt(1) to Ayah(it.getInt(2), it.getInt(3), it.getString(4))
            }.toMap()
        return QuranPage(number, lines, verses)
    }

    fun page(
        surah: Int,
        verse: Int,
    ): Int = query("SELECT page FROM quran WHERE sura = ? AND aya = ?", surah, verse) { it.getInt(1) }.single()

    private fun <T> query(
        sql: String,
        vararg parameters: Int,
        row: (java.sql.ResultSet) -> T,
    ): List<T> =
        connection.prepareStatement(sql).use { statement ->
            parameters.forEachIndexed { index, value -> statement.setInt(index + 1, value) }
            statement.executeQuery().use { result -> buildList { while (result.next()) add(row(result)) } }
        }
}

package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.sql.JdbcContentSql
import kotlinx.serialization.json.Json
import java.io.File

/** A Quran database over sqlite-jdbc, opened per query; a missing file is [QuranUnavailableException]. */
class JdbcQuranSql(
    file: File,
    readOnly: Boolean = true,
) : JdbcContentSql(file, readOnly, ::QuranUnavailableException) {
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

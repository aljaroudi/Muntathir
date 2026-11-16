package com.aljaroudi.muntathir.data

import android.content.Context
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.quran.DailyAyah
import com.aljaroudi.muntathir.core.quran.QuranSurah
import kotlinx.serialization.json.Json
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * The bundled Quran text (`assets/quran/quran.db`) and English translation, copied once per app install or
 * update into `noBackupFilesDir` and read with the bundled SQLite build. Swift `QuranDatabase`.
 */
@Singleton
class QuranDatabase
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
    ) {
        @OptIn(ExperimentalCoroutinesApi::class)
        private val dispatcher = Dispatchers.IO.limitedParallelism(1)
        private val mutex = Mutex()
        private val connections = mutableMapOf<String, SQLiteConnection?>()

        /** Verses by global index (1…6236) with the [translation] text when given; unknown indices are absent. */
        suspend fun verses(
            ids: Set<Int>,
            translation: String? = null,
        ): Map<Int, Ayah> =
            withContext(dispatcher) {
                mutex.withLock {
                    val arabic = query(QURAN, ids) ?: return@withLock emptyMap()
                    val translated = translation?.let { query(it, ids) }.orEmpty()
                    arabic.mapValues { (index, ayah) ->
                        translated[index]?.let { ayah.copy(translations = mapOf(translation!! to it.text)) } ?: ayah
                    }
                }
            }

        /** Arabic surah names by number, for Arabic verse references. */
        suspend fun surahNames(): Map<Int, String> =
            withContext(Dispatchers.IO) {
                runCatching {
                    val text = context.assets.open("quran/$SURAHS").use { it.readBytes().decodeToString() }
                    json.decodeFromString<List<QuranSurah>>(text).associate { it.id to it.arabic }
                }.getOrDefault(emptyMap())
            }

        /** The 360-day schedule, or an empty one when the bundled data is incomplete. */
        suspend fun dailyAyah(translation: String?): DailyAyah {
            val json =
                withContext(Dispatchers.IO) {
                    runCatching { context.assets.open("quran/$DAILY_IDS").use { it.readBytes().decodeToString() } }.getOrNull()
                }
            val ids = DailyAyah.ids(json)
            val records = if (ids.size == DailyAyah.COUNT) verses(ids.toSet(), translation) else emptyMap()
            return DailyAyah.load(ids, records)
        }

        private fun query(
            name: String,
            ids: Set<Int>,
        ): Map<Int, Ayah>? {
            val connection = connection(name) ?: return null
            return ids.filter { it in 1..VERSE_COUNT }.chunked(500).flatMap { chunk ->
                val marks = chunk.joinToString(",") { "?" }
                connection.prepare("SELECT \"index\", sura, aya, text FROM quran WHERE \"index\" IN ($marks)").use { statement ->
                    chunk.forEachIndexed { position, id -> statement.bindLong(position + 1, id.toLong()) }
                    buildList {
                        while (statement.step()) {
                            add(statement.getLong(0).toInt() to Ayah(statement.getLong(1).toInt(), statement.getLong(2).toInt(), statement.getText(3)))
                        }
                    }
                }
            }.toMap()
        }

        private fun connection(name: String): SQLiteConnection? =
            connections.getOrPut(name) {
                runCatching {
                    val file = install("$name.db")
                    driver.open(file.absolutePath, SQLITE_OPEN_READONLY)
                }.getOrNull()
            }

        /** Copies an asset when missing or older than the installed APK, then returns the file. */
        private fun install(asset: String): File {
            val directory = File(context.noBackupFilesDir, "quran").apply { mkdirs() }
            val file = File(directory, asset)
            val installed = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
            if (!file.isFile || file.lastModified() < installed) {
                val temporary = File(directory, "$asset.tmp")
                context.assets.open("quran/$asset").use { input -> temporary.outputStream().use(input::copyTo) }
                if (!temporary.renameTo(file)) error("Unable to install $asset")
            }
            return file
        }

        companion object {
            const val QURAN = "quran"
            const val ENGLISH = "en.qarai"
            const val DAILY_IDS = "quran-daily-ids.json"
            const val SURAHS = "quran-surahs.json"
            private val json = Json { ignoreUnknownKeys = true }
            const val VERSE_COUNT = 6236
            private val driver = BundledSQLiteDriver()
        }
    }

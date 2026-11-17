package com.aljaroudi.muntathir.data

import android.content.Context
import androidx.sqlite.SQLiteConnection
import com.aljaroudi.muntathir.core.quran.DailyAyah
import com.aljaroudi.muntathir.core.quran.QuranReader
import com.aljaroudi.muntathir.core.quran.QuranSurah
import com.aljaroudi.muntathir.core.quran.QuranTranslation
import com.aljaroudi.muntathir.core.quran.QuranUnavailableException
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * The bundled Quran text (`assets/quran/quran.db`) and English translation, copied once per app install or
 * update into `noBackupFilesDir`, plus installed translations, read with the bundled SQLite build (FTS5).
 * Connections stay open and are confined to one thread; [read] runs the core [QuranReader] there.
 */
@Singleton
class QuranDatabase
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
    ) {
        @OptIn(ExperimentalCoroutinesApi::class)
        private val dispatcher = Dispatchers.IO.limitedParallelism(1)
        private val connections = mutableMapOf<String, SQLiteConnection>()

        @Volatile private var translationFiles: Map<String, File> = emptyMap()

        private val surahList: List<QuranSurah> by lazy {
            json.decodeFromString<List<QuranSurah>>(asset(SURAHS))
        }

        private val reader =
            QuranReader(
                arabic = { BundledContentSql(connection(install("$QURAN.db"))) },
                surahs = { surahList },
                translation = { id ->
                    val file = if (id == QuranTranslation.BUNDLED_ID) install("$id.db") else translationFiles[id]
                    file?.takeIf(File::isFile)?.let { BundledContentSql(connection(it)) }
                },
            )

        /** Runs [block] on the database thread. */
        suspend fun <T> read(block: suspend QuranReader.() -> T): T =
            withContext(dispatcher) {
                closeReplacedTranslations()
                reader.block()
            }

        /** Points downloaded translations at the installed files; connections to replaced ones close on the next read. */
        fun setTranslations(files: Map<String, File>) {
            translationFiles = files
        }

        private fun closeReplacedTranslations() {
            val keep = translationFiles.values.map { it.absolutePath }.toSet()
            val bundled = directory().absolutePath
            connections.keys
                .filter { it !in keep && !it.startsWith(bundled) }
                .forEach { connections.remove(it)?.close() }
        }

        /** Whether [file] is a complete translation database (blocking). Swift `QuranDatabase.validateTranslation`. */
        fun isValidTranslation(file: File): Boolean =
            runCatching {
                BundledContentSql.Driver.open(file, writable = false).use(QuranReader::isValidTranslation)
            }.getOrDefault(false)

        /** Arabic surah names by number, for Arabic verse references. */
        suspend fun surahNames(): Map<Int, String> =
            withContext(
                Dispatchers.IO,
            ) { runCatching { surahList.associate { it.id to it.arabic } }.getOrDefault(emptyMap()) }

        /** The 360-day schedule, or an empty one when the bundled data is incomplete. */
        suspend fun dailyAyah(translation: String?): DailyAyah {
            val json = withContext(Dispatchers.IO) { runCatching { asset(DAILY_IDS) }.getOrNull() }
            val ids = DailyAyah.ids(json)
            val records = if (ids.size == DailyAyah.COUNT) read { verses(ids.toSet(), translation) } else emptyMap()
            return DailyAyah.load(ids, records)
        }

        private fun asset(name: String): String =
            context.assets.open("quran/$name").use { it.readBytes().decodeToString() }

        private fun connection(file: File): SQLiteConnection =
            connections.getOrPut(file.absolutePath) {
                try {
                    BundledContentSql.Driver.connection(file)
                } catch (error: Exception) {
                    throw QuranUnavailableException(error)
                }
            }

        private fun directory() = File(context.noBackupFilesDir, "quran").apply { mkdirs() }

        /** Copies an asset when missing or older than the installed APK, then returns the file. */
        private fun install(asset: String): File {
            val file = File(directory(), asset)
            if (file.absolutePath in connections) return file
            val installed = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
            if (!file.isFile || file.lastModified() < installed) {
                val temporary = File(directory(), "$asset.tmp")
                context.assets.open("quran/$asset").use { input -> temporary.outputStream().use(input::copyTo) }
                if (!temporary.renameTo(file)) throw QuranUnavailableException()
            }
            return file
        }

        companion object {
            const val QURAN = "quran"
            const val ENGLISH = QuranTranslation.BUNDLED_ID
            const val DAILY_IDS = "quran-daily-ids.json"
            const val SURAHS = "quran-surahs.json"
            private val json = Json { ignoreUnknownKeys = true }
        }
    }

package com.aljaroudi.muntathir.ui.dictionary

import android.app.Activity
import android.content.Context
import com.aljaroudi.muntathir.assets.AssetPackBackend
import com.aljaroudi.muntathir.assets.ContentPack
import com.aljaroudi.muntathir.assets.PlayAssetPack
import com.aljaroudi.muntathir.core.rulings.LibraryPackReader
import com.aljaroudi.muntathir.core.rulings.RulingsAssetStore
import com.aljaroudi.muntathir.core.sql.ContentSql
import com.aljaroudi.muntathir.core.sql.query
import com.aljaroudi.muntathir.core.text.LexiconSpelling
import com.aljaroudi.muntathir.data.AppScope
import com.aljaroudi.muntathir.data.BundledContentSql
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

class DictionaryReader : LibraryPackReader {
    private val io = Dispatchers.IO.limitedParallelism(1)
    private var db: ContentSql? = null

    override suspend fun install(file: File?) =
        withContext(io) {
            db?.close()
            db = null
            if (file != null) {
                val opened = BundledContentSql.Driver.open(file, false)
                try {
                    check(opened.query("pragma user_version") { it.int(0) } == listOf(1))
                    check(opened.query("pragma quick_check") { it.text(0) } == listOf("ok"))
                    check(
                        opened.query(
                            "select root from words where spelling='الكتاب' order by rank limit 1",
                        ) { it.text(0) } ==
                            listOf("كتب"),
                    )
                    check(opened.query("select 1 from family limit 1") { it.int(0) }.isNotEmpty())
                    check(opened.query("select 1 from rootless limit 1") { it.int(0) }.isNotEmpty())
                    db = opened
                } catch (error: Exception) {
                    opened.close()
                    throw error
                }
            }
        }

    /** Roots for one word, best first. A phrase has no root of its own; its words are looked up one at a time. */
    suspend fun search(text: String): List<String> =
        withContext(io) {
            val sql = checkNotNull(db)
            val words = text.split(Regex("\\s+")).map(LexiconSpelling::spell).filter { it.isNotEmpty() }
            if (words.size == 1) roots(sql, words[0]) else emptyList()
        }

    /**
     * The pack ranks roots for every word the lexicons list and every word in the app's text
     * (see shared/lexicon/build.py), and lists the ones it found none for. Other selections, such
     * as part of a word, retry without clitics.
     */
    private fun roots(
        sql: ContentSql,
        word: String,
    ): List<String> {
        if (sql.query("SELECT 1 FROM rootless WHERE spelling=?", word) { it.int(0) }.isNotEmpty()) return emptyList()
        for (stem in listOf(word) + LexiconSpelling.stems(word)) {
            val exact = sql.query("SELECT root FROM words WHERE spelling=? ORDER BY rank", stem) { it.text(0) }
            if (exact.isNotEmpty()) return exact
            val folded =
                sql.query(
                    "SELECT root FROM words WHERE norm=? GROUP BY root ORDER BY min(rank), count(*) DESC, root LIMIT 4",
                    LexiconSpelling.normalize(stem),
                ) { it.text(0) }
            if (folded.isNotEmpty()) return folded
        }
        return emptyList()
    }

    /** One source's definition; `root` is the heading it files it under, which can be another spelling (سمو for سما). */
    data class Definition(
        val source: Int,
        val root: String,
        val body: String,
    )

    suspend fun entry(root: String) =
        withContext(io) {
            checkNotNull(db).query(
                """
                SELECT source,root,body FROM entries WHERE root=?1 OR root IN (SELECT member FROM family WHERE root=?1)
                ORDER BY source, root<>?1, root
                """.trimIndent(),
                root,
            ) { Definition(it.int(0), it.text(1), it.text(2)) }
        }
}

@Serializable
data class DictionaryRecord(
    val value: String,
    val entry: Boolean,
)

@Singleton
class DictionaryLibrary
    @Inject
    constructor(
        @ApplicationContext context: Context,
        private val backend: AssetPackBackend,
        @AppScope scope: CoroutineScope,
    ) {
        private val main = CoroutineScope(scope.coroutineContext + Dispatchers.Main.immediate)
        private val pack = PlayAssetPack(backend, ContentPack.Dictionary)
        val reader = DictionaryReader()
        private val store = RulingsAssetStore(pack, reader, "lexicon.db")
        val state = store.state
        private val prefs = context.getSharedPreferences("lexicon", Context.MODE_PRIVATE)
        val history = MutableStateFlow(read<List<DictionaryRecord>>("history") ?: emptyList())
        val bookmarks = MutableStateFlow(read<List<String>>("bookmarks") ?: emptyList())

        init {
            main.launch { store.refresh() }
            main.launch { pack.events().collect { store.receive(it) } }
        }

        private inline fun <reified T> read(key: String): T? =
            prefs.getString(key, null)?.let { runCatching { Json.decodeFromString<T>(it) }.getOrNull() }

        fun setHistory(next: List<DictionaryRecord>) {
            prefs.edit().putString("history", Json.encodeToString(next)).apply()
            history.value = next
        }

        fun visit(record: DictionaryRecord) = setHistory(listOf(record) + (history.value - record))

        fun bookmark(root: String) {
            val next = if (root in bookmarks.value) bookmarks.value - root else listOf(root) + bookmarks.value
            prefs.edit().putString("bookmarks", Json.encodeToString(next)).apply()
            bookmarks.value = next
        }

        fun download() {
            main.launch { store.download() }
        }

        fun remove() {
            main.launch { store.remove() }
        }

        fun refresh() {
            main.launch { store.refresh() }
        }

        fun confirm(activity: Activity) {
            main.launch { runCatching { backend.confirm(activity) } }
        }
    }

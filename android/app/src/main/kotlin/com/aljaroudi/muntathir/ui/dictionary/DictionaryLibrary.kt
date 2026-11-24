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
import java.text.Normalizer
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
                        opened
                            .query(
                                "select 1 from passages where passages match 'كتاب' limit 1",
                            ) { it.int(0) }
                            .isNotEmpty(),
                    )
                    check(opened.query("select 1 from entries where root='كتب' limit 1") { it.int(0) }.isNotEmpty())
                    db = opened
                } catch (error: Exception) {
                    opened.close()
                    throw error
                }
            }
        }

    data class Passage(
        val root: String,
        val source: Int,
        val preview: String,
    )

    data class Matches(
        val roots: List<String> = emptyList(),
        val passages: List<Passage> = emptyList(),
    )

    suspend fun search(text: String) =
        withContext(io) {
            val sql = checkNotNull(db)
            val norm =
                Normalizer
                    .normalize(text, Normalizer.Form.NFKC)
                    .replace(
                        Regex("[ؐ-ؚـً-ٰٟۖ-ۭ]"),
                        "",
                    ).replace(Regex("[أإآٱ]"), "ا")
                    .replace('ى', 'ي')
                    .replace('ئ', 'ي')
                    .replace('ؤ', 'و')
            if (norm.isBlank()) return@withContext Matches()
            val roots =
                sql.query(
                    """
                    SELECT root FROM (SELECT root,0 priority FROM forms WHERE form=? UNION ALL SELECT root,1 FROM forms WHERE norm=?) AS candidate
                    WHERE EXISTS (SELECT 1 FROM entries WHERE entries.root=candidate.root)
                    GROUP BY root ORDER BY min(priority),root
                    """.trimIndent(),
                    text,
                    norm,
                ) { it.text(0) }
            val phrase = "\"" + norm.replace("\"", "\"\"") + "\""
            val passages =
                sql.query(
                    """
                    SELECT e.root,e.source,snippet(passages,0,'','','…',18) FROM passages JOIN entries e ON e.rowid=passages.rowid
                    WHERE passages MATCH ? ORDER BY rank LIMIT 100
                    """.trimIndent(),
                    phrase,
                ) { Passage(it.text(0), it.int(1), it.text(2)) }
            Matches(roots, passages)
        }

    suspend fun entry(root: String) =
        withContext(io) {
            checkNotNull(db).query("SELECT source,body FROM entries WHERE root=? ORDER BY source", root) {
                it.int(0) to it.text(1)
            }
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

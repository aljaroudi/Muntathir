package com.aljaroudi.muntathir.data.library

import android.content.Context
import com.aljaroudi.muntathir.core.hadith.HadithSession
import com.aljaroudi.muntathir.data.AppScope
import com.aljaroudi.muntathir.ui.navigation.HadithBrowseRoute
import com.aljaroudi.muntathir.ui.navigation.HadithDetailRoute
import com.aljaroudi.muntathir.ui.navigation.HadithRoute
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Where the reader was in the hadith library, so the app reopens there. Swift `HadithSession`
 * (`hadith.session.v1`), kept device-local in `no_backup/hadith.session.v1.json`.
 *
 * The saved chain is the hadith screens in the Hadith stack: a book's contents, one of its chapters, then a
 * narration, each stored by stable source so it survives library updates. Searches across all books, Saved and
 * introductions aren't kept, as on iOS.
 */
@Singleton
class HadithSessionStore
    @Inject
    constructor(
        @ApplicationContext context: Context,
        @param:AppScope private val scope: CoroutineScope,
        private val libraries: ContentLibraries,
    ) {
        enum class Level { Results, Contents }

        private val file = File(context.noBackupFilesDir, "hadith.session.v1.json")

        @OptIn(ExperimentalCoroutinesApi::class)
        private val io = Dispatchers.IO.limitedParallelism(1)
        private var loaded: HadithSession? = null
        private var restored = false
        private var saving: Job? = null
        private val mutex = Mutex()

        private suspend fun session(): HadithSession =
            loaded
                ?: withContext(io) { HadithSession.decode(file.takeIf(File::isFile)?.readText()) }.also { loaded = it }

        /**
         * Once per process: the saved screens below the library, resolved against the installed library, and the
         * library's own search. Empty when nothing was open or the saved sources no longer exist.
         */
        suspend fun restore(): Restored? {
            if (restored) return null
            restored = true
            val session = session()
            val reader = libraries.hadith.reader
            return try {
                val routes = mutableListOf<HadithRoute>()
                val collection = session.request.collectionID
                if (collection != null) {
                    if (reader.catalog().none { it.id == collection }) return null
                    routes += HadithBrowseRoute(collection, query = session.contentsQuery.orEmpty())
                    session.chapter?.let { chapter ->
                        val id = reader.chapterID(chapter) ?: return@let
                        routes += HadithBrowseRoute(collection, id, session.request.query)
                    }
                }
                session.selection?.let { source ->
                    reader.resolve(source)?.let { routes += HadithDetailRoute(it, session.request.query) }
                }
                pendingRows[Level.Contents] = session.contentsRow
                pendingRows[Level.Results] = session.listRow
                pendingOffset = session.detailOffset.toInt()
                Restored(routes, rootQuery = if (collection == null) session.request.query else "")
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Exception) {
                // Keep the saved session for a later launch if the library is temporarily unavailable.
                null
            }
        }

        data class Restored(
            val routes: List<HadithRoute>,
            val rootQuery: String,
        )

        private val pendingRows = mutableMapOf<Level, String?>()
        private var pendingOffset = 0

        /** The restored first visible row for [level], once. */
        fun takeRow(level: Level): String? = pendingRows.remove(level)

        /** The restored narration scroll offset, once. */
        fun takeDetailOffset(): Int = pendingOffset.also { pendingOffset = 0 }

        /** Records the hadith screens open below the library, in stack order. */
        fun save(routes: List<HadithRoute>) {
            val chain = mutableListOf<HadithRoute>()
            for (route in routes) {
                val tracked =
                    when (route) {
                        is HadithBrowseRoute -> route.collectionID != null
                        is HadithDetailRoute -> !route.supplication && route.highlight == null
                        else -> false
                    }
                if (!tracked) break
                chain += route
            }
            saving?.cancel()
            saving =
                scope.launch {
                    val reader = libraries.hadith.reader
                    val contents = chain.filterIsInstance<HadithBrowseRoute>().firstOrNull { it.chapterID == null }
                    val chapter = chain.filterIsInstance<HadithBrowseRoute>().firstOrNull { it.chapterID != null }
                    val detail = chain.filterIsInstance<HadithDetailRoute>().firstOrNull()
                    val sources =
                        try {
                            reader.chapterSource(chapter?.chapterID) to detail?.let { reader.source(it.id) }
                        } catch (cancellation: CancellationException) {
                            throw cancellation
                        } catch (_: Exception) {
                            // Keep the previous complete session if a query fails.
                            return@launch
                        }
                    update { session ->
                        val collection = contents?.collectionID ?: chapter?.collectionID
                        session.copy(
                            active = chain.isNotEmpty(),
                            request =
                                session.request.copy(
                                    collectionID = collection,
                                    chapterID = chapter?.chapterID,
                                    query = chapter?.query ?: if (collection == null) session.request.query else "",
                                ),
                            chapter = sources.first,
                            selection = sources.second,
                            contentsQuery = contents?.query,
                            screen =
                                if (chapter != null) {
                                    "results"
                                } else if (contents != null) {
                                    "contents"
                                } else {
                                    null
                                },
                            listRow = if (chapter != null || collection == null) session.listRow else null,
                            contentsRow = if (contents != null) session.contentsRow else null,
                            detailOffset =
                                if (detail != null &&
                                    sources.second == session.selection
                                ) {
                                    session.detailOffset
                                } else {
                                    0.0
                                },
                        )
                    }
                }
        }

        /** The library's own search, restored when no book is open. */
        fun setRootQuery(query: String) =
            scope.launch {
                update {
                    if (it.request.collectionID ==
                        null
                    ) {
                        it.copy(request = it.request.copy(query = query))
                    } else {
                        it
                    }
                }
            }

        /** The first visible row of a list (Swift `HadithListAnchor`). */
        fun setRow(
            level: Level,
            row: String?,
        ) = scope.launch {
            update {
                when (level) {
                    Level.Contents -> it.copy(contentsRow = row)
                    Level.Results -> it.copy(listRow = row)
                }
            }
        }

        fun setDetailOffset(offset: Int) = scope.launch { update { it.copy(detailOffset = offset.toDouble()) } }

        private suspend fun update(change: (HadithSession) -> HadithSession) =
            mutex.withLock {
                val old = session()
                val new = change(old)
                if (new == old) return@withLock
                loaded = new
                withContext(io) {
                    val temporary = File(file.path + ".tmp")
                    temporary.writeText(new.encode())
                    temporary.renameTo(file)
                }
            }
    }

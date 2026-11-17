package com.aljaroudi.muntathir.core.highlight

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID

/** One stored row. Several installations (restored backups) may hold rows for the same item. */
data class StoredRecord(
    val recordID: String,
    val itemID: String,
    val installationID: String,
    val payload: String,
    /** Epoch milliseconds. */
    val modifiedAt: Long,
    val isTombstone: Boolean,
) {
    val snapshot: RecordSnapshot get() =
        RecordSnapshot(
            recordID,
            itemID,
            payload,
            Instant.ofEpochMilli(modifiedAt),
            isTombstone,
        )
}

/** The highlight and bookmark tables; Room in the app, memory in tests. */
interface UserRecords {
    enum class Table { Highlights, Bookmarks }

    suspend fun all(table: Table): List<StoredRecord>

    /** Inserts or replaces [rows] by record id, all or nothing. */
    suspend fun write(
        table: Table,
        rows: List<StoredRecord>,
    )
}

class QuranUserStoreException(
    val reason: Reason,
    cause: Throwable? = null,
) : Exception(reason.name, cause) {
    enum class Reason { Unavailable, InvalidHighlight, InvalidBookmark }
}

/**
 * Highlights and bookmarks, port of Swift `QuranUserStore`: every item keeps its stable id, the newest row wins
 * (ties go to the larger record id), deletions are tombstones, and this installation only edits its own rows,
 * so data restored from another device merges the same way iOS merges iCloud imports.
 */
class QuranUserStore(
    private val records: UserRecords,
    private val installationID: () -> String,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val mutex = Mutex()
    private val mutableHighlights = MutableStateFlow<List<ReadingHighlight>>(emptyList())
    private val mutableBookmarks = MutableStateFlow<List<ReadingBookmark>>(emptyList())
    private val mutableUnavailable = MutableStateFlow(false)
    private var installation: String? = null

    val highlights: StateFlow<List<ReadingHighlight>> = mutableHighlights.asStateFlow()
    val bookmarks: StateFlow<List<ReadingBookmark>> = mutableBookmarks.asStateFlow()

    /** The store couldn't be opened; [reopen] retries. */
    val unavailable: StateFlow<Boolean> = mutableUnavailable.asStateFlow()

    suspend fun reopen() =
        mutex.withLock {
            try {
                installation = installation ?: installationID()
                receive()
                mutableUnavailable.value = false
            } catch (error: Exception) {
                mutableUnavailable.value = true
            }
        }

    fun highlights(
        source: String,
        isHadith: Boolean = false,
    ): List<ReadingHighlight> = highlights.value.filter { it.source == source && it.isHadith == isHadith }

    fun bookmark(
        source: String,
        isHadith: Boolean = false,
        ruling: RulingID? = null,
    ): ReadingBookmark? =
        bookmarks.value.firstOrNull {
            it.source == source && it.isHadith == isHadith &&
                it.ruling == ruling
        }

    /** Saves a batch together (e.g. one highlight per selected verse); an invalid item rejects the batch. */
    suspend fun save(highlights: List<ReadingHighlight>) {
        if (highlights.isEmpty() ||
            highlights.any { it.source.isEmpty() || (it.block != null && it.ranges.isEmpty()) }
        ) {
            throw QuranUserStoreException(QuranUserStoreException.Reason.InvalidHighlight)
        }
        updateHighlights(highlights, deleted = false)
    }

    suspend fun delete(highlight: ReadingHighlight) = updateHighlights(listOf(highlight), deleted = true)

    suspend fun save(bookmark: ReadingBookmark) {
        val ruling = bookmark.ruling
        if (bookmark.source.isEmpty() ||
            (
                ruling != null &&
                    (ruling.authority.isEmpty() || ruling.language.isEmpty() || ruling.siteID != bookmark.source)
            )
        ) {
            throw QuranUserStoreException(QuranUserStoreException.Reason.InvalidBookmark)
        }
        updateBookmark(bookmark, deleted = false)
    }

    suspend fun delete(bookmark: ReadingBookmark) = updateBookmark(bookmark, deleted = true)

    private suspend fun updateHighlights(
        highlights: List<ReadingHighlight>,
        deleted: Boolean,
    ) = update(UserRecords.Table.Highlights) { rows ->
        highlights.map { highlight ->
            write(rows, highlight.id, deleted) { modifiedAt, _ ->
                val note = if (highlight.note.isBlank()) "" else highlight.note
                json.encodeToString(highlight.copy(modifiedAt = modifiedAt, note = note)) to modifiedAt
            }
        }
    }

    private suspend fun updateBookmark(
        bookmark: ReadingBookmark,
        deleted: Boolean,
    ) = update(UserRecords.Table.Bookmarks) { rows ->
        listOf(
            write(rows, bookmark.id, deleted) { modifiedAt, winner ->
                // Re-adding keeps the original creation date.
                val createdAt =
                    winner
                        ?.takeIf { !it.isTombstone }
                        ?.let { runCatching { ReadingBookmark.decode(it.payload).createdAt }.getOrNull() }
                        ?: bookmark.createdAt
                bookmark.copy(createdAt = createdAt, modifiedAt = modifiedAt).encode() to modifiedAt
            },
        )
    }

    /** This installation's row for [itemID] (reused, or new), stamped after the current winner. */
    private fun write(
        rows: List<StoredRecord>,
        itemID: String,
        deleted: Boolean,
        payload: (modifiedAt: Long, winner: RecordSnapshot?) -> Pair<String, Long>,
    ): StoredRecord {
        val installation = installation ?: throw QuranUserStoreException(QuranUserStoreException.Reason.Unavailable)
        val matching = rows.filter { it.itemID == itemID }
        val winner = RecordSnapshot.winners(matching.map { it.snapshot })[itemID]
        val local = matching.filter { it.installationID == installation }.maxByOrNull { it.recordID }
        val modifiedAt = RecordSnapshot.nextModifiedAt(Instant.ofEpochMilli(now()), winner).toEpochMilli()
        val (encoded, stamp) = payload(modifiedAt, winner)
        return StoredRecord(
            recordID = local?.recordID ?: UUID.randomUUID().toString().uppercase(),
            itemID = itemID,
            installationID = installation,
            payload = encoded,
            modifiedAt = stamp,
            isTombstone = deleted,
        )
    }

    /** Reads current rows (imports may have changed them), writes atomically, then republishes; failures change nothing. */
    private suspend fun update(
        table: UserRecords.Table,
        rows: (List<StoredRecord>) -> List<StoredRecord>,
    ) = mutex.withLock {
        if (installation == null ||
            mutableUnavailable.value
        ) {
            throw QuranUserStoreException(QuranUserStoreException.Reason.Unavailable)
        }
        try {
            records.write(table, rows(records.all(table)))
        } finally {
            runCatching { receive() }
        }
    }

    private suspend fun receive() {
        mutableHighlights.value =
            current(records.all(UserRecords.Table.Highlights)) {
                runCatching { json.decodeFromString<ReadingHighlight>(it) }.getOrNull()
            }.sortedWith(compareByDescending<ReadingHighlight> { it.modifiedAt }.thenByDescending { it.id })
        mutableBookmarks.value =
            current(records.all(UserRecords.Table.Bookmarks)) { runCatching { ReadingBookmark.decode(it) }.getOrNull() }
                .sortedWith(compareByDescending<ReadingBookmark> { it.modifiedAt }.thenByDescending { it.id })
    }

    /** Winning, non-deleted payloads; rows that no longer decode are skipped. */
    private fun <T> current(
        rows: List<StoredRecord>,
        decode: (String) -> T?,
    ): List<T> =
        RecordSnapshot
            .winners(rows.map { it.snapshot })
            .values
            .filter { !it.isTombstone }
            .mapNotNull { decode(it.payload) }

    private companion object {
        val json =
            Json {
                ignoreUnknownKeys = true
                encodeDefaults = true
            }
    }
}

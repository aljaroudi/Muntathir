package com.aljaroudi.muntathir.core.highlight

import java.time.Instant

/**
 * One stored row of a highlight or bookmark: several rows may share an [itemID] (e.g. restored from
 * backup), and the newest wins. Port of Swift `HighlightSnapshot` / `BookmarkSnapshot`.
 */
data class RecordSnapshot(
    val recordID: String,
    val itemID: String,
    /** JSON payload of the item. */
    val payload: String,
    val modifiedAt: Instant,
    val isTombstone: Boolean,
) {
    companion object {
        /** The current row per item: newest [modifiedAt], ties broken by the larger [recordID], independent of order. */
        fun winners(rows: List<RecordSnapshot>): Map<String, RecordSnapshot> {
            val result = mutableMapOf<String, RecordSnapshot>()
            for (row in rows) {
                val old = result[row.itemID]
                if (old != null &&
                    (
                        old.modifiedAt > row.modifiedAt ||
                            (old.modifiedAt == row.modifiedAt && old.recordID > row.recordID)
                    )
                ) {
                    continue
                }
                result[row.itemID] = row
            }
            return result
        }

        /** A local save's timestamp: never earlier than the current winner, so local edits always win. */
        fun nextModifiedAt(
            now: Instant,
            winner: RecordSnapshot?,
        ): Instant {
            val after = winner?.modifiedAt?.plusMillis(1) ?: return now
            return maxOf(now, after)
        }
    }
}

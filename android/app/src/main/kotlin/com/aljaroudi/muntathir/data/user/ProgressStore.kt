package com.aljaroudi.muntathir.data.user

import com.aljaroudi.muntathir.core.progress.ProgressActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

/**
 * Reading and tasbih sessions in Room's `activity` table. Port of Swift `ProgressStore.saveActivity`: a session is
 * saved again as it grows, and a smaller snapshot never replaces a larger one (max, not sum).
 */
class ProgressStore(
    private val dao: UserDao,
    private val scope: CoroutineScope,
) {
    private val mutex = Mutex()

    /** Saves in the background, so a session can flush while its screen goes away. */
    fun record(activity: ProgressActivity) {
        scope.launch { runCatching { save(activity) } }
    }

    suspend fun save(activity: ProgressActivity) =
        mutex.withLock {
            if (!activity.isValid) return@withLock
            val existing = dao.activity(activity.id)?.let { decode(it.payload) }
            if (existing != null && existing.amount >= activity.amount) return@withLock
            dao.upsertActivity(ActivityEntity(activity.id, json.encodeToString(activity)))
        }

    /** Every stored session; undecodable rows are skipped. */
    suspend fun activities(): List<ProgressActivity> = dao.activities().mapNotNull { decode(it.payload) }

    private fun decode(payload: String) = runCatching { json.decodeFromString<ProgressActivity>(payload) }.getOrNull()

    private companion object {
        val json =
            Json {
                ignoreUnknownKeys = true
                encodeDefaults = true
            }
    }
}

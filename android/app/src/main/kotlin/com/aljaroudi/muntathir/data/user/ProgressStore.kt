package com.aljaroudi.muntathir.data.user

import com.aljaroudi.muntathir.core.progress.PrayerCompletion
import com.aljaroudi.muntathir.core.progress.ProgressActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

/**
 * Reading and tasbih sessions in Room's `activity` table, and prayers counted by the Rakaat tracker in
 * `prayer_history`. Port of Swift `ProgressStore`: a session is saved again as it grows, and a smaller snapshot
 * never replaces a larger one (max, not sum); a prayer is saved once.
 */
class ProgressStore(
    private val dao: UserDao,
    private val scope: CoroutineScope,
) {
    private val mutex = Mutex()

    /** Every valid stored session, live; undecodable rows are skipped. */
    val activityFlow: Flow<List<ProgressActivity>> =
        dao.observeActivities().map { rows ->
            rows.mapNotNull { decode<ProgressActivity>(it.payload) }.filter { it.isValid }
        }

    /** Every stored prayer, live. */
    val prayerFlow: Flow<List<PrayerCompletion>> =
        dao.observePrayerHistory().map { rows -> rows.mapNotNull { decode<PrayerCompletion>(it.payload) } }

    /** Saves in the background, so a session can flush while its screen goes away. */
    fun record(activity: ProgressActivity) {
        scope.launch { runCatching { save(activity) } }
    }

    suspend fun save(activity: ProgressActivity) =
        mutex.withLock {
            if (!activity.isValid) return@withLock
            val existing = dao.activity(activity.id)?.let { decode<ProgressActivity>(it.payload) }
            if (existing != null && existing.amount >= activity.amount) return@withLock
            dao.upsertActivity(ActivityEntity(activity.id, json.encodeToString(activity)))
        }

    /** Saves a prayer once; a repeated id is ignored. Throws when the database can't be written. */
    suspend fun save(prayer: PrayerCompletion) {
        dao.insertPrayer(PrayerHistoryEntity(prayer.id, json.encodeToString(prayer)))
    }

    /** Every stored session; undecodable rows are skipped. */
    suspend fun activities(): List<ProgressActivity> = dao.activities().mapNotNull { decode(it.payload) }

    suspend fun prayers(): List<PrayerCompletion> = dao.prayerHistory().mapNotNull { decode(it.payload) }

    private inline fun <reified T> decode(payload: String) =
        runCatching { json.decodeFromString<T>(payload) }.getOrNull()

    private companion object {
        val json =
            Json {
                ignoreUnknownKeys = true
                encodeDefaults = true
            }
    }
}

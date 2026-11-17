package com.aljaroudi.muntathir.data

import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.progress.PrayerProgress
import com.aljaroudi.muntathir.core.progress.ProgressActivity
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.data.user.ProgressStore
import com.aljaroudi.muntathir.data.user.UserDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant

/** Swift `ProgressStore.saveActivity` on Room: snapshots only grow, and totals take each session's largest. */
class ProgressStoreTest {
    private val database = UserDatabase.inMemory(InstrumentationRegistry.getInstrumentation().targetContext)
    private val store = ProgressStore(database.dao(), CoroutineScope(Dispatchers.IO))

    @After
    fun close() = database.close()

    @Test
    fun sessionsGrowAndNeverShrink() =
        runBlocking {
            val session = ProgressActivity(ProgressActivityKind.QuranReading, 10.0, id = "A")
            store.save(session)
            store.save(session.copy(amount = 5.0))
            assertEquals(listOf(10.0), store.activities().map { it.amount })
            store.save(session.copy(amount = 20.0))
            store.save(ProgressActivity(ProgressActivityKind.QuranReading, 30.0, id = "B"))
            store.save(ProgressActivity(ProgressActivityKind.Tasbih, 2.5, id = "C"))
            store.save(ProgressActivity(ProgressActivityKind.HadithReading, 0.0, id = "D"))
            assertEquals(mapOf(ProgressActivityKind.QuranReading to 50.0), ProgressActivity.totals(store.activities()))
        }

    /** Swift `persistenceRetryAndDuplicateSaves`: a prayer saves once, and duplicates count one day. */
    @Test
    fun prayersSaveOnce() =
        runBlocking {
            val mecca = SavedLocation(21.4225, 39.8262, "Mecca", "SA", "Asia/Riyadh")
            val record =
                PrayerProgress.snapshot(
                    PrayerName.Fajr,
                    Instant.ofEpochSecond(1_794_520_800),
                    mecca,
                    PrayerMethod.Jafari,
                )
            store.save(record)
            store.save(record.copy(completedAt = record.completedAt.plusSeconds(60)))
            assertEquals(listOf(record), store.prayers())
            assertEquals(listOf(record), store.prayerFlow.first())
            assertEquals(1, PrayerProgress.days(PrayerName.Fajr, store.prayers() + store.prayers()).size)
        }
}

package com.aljaroudi.muntathir.data

import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.core.progress.ProgressActivity
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.data.user.ProgressStore
import com.aljaroudi.muntathir.data.user.UserDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

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
}

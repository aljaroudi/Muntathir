package com.aljaroudi.muntathir.core.feed

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.CalendarException
import com.aljaroudi.muntathir.core.calendar.CivilDate
import com.aljaroudi.muntathir.core.calendar.DateProvenance
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.core.location.SavedLocation
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `FeedClientTests`. AppModel wiring (stale responses while preferences change, persisting
// confirmations) is P2.7; the pure apply step is covered through `CorrectionsFeed.confirmations`.
class FeedClientTest {
    private val folder: File = Files.createTempDirectory("feed").toFile()
    private val url = "https://example.invalid/feed.json"

    /** Replays queued responses and records each request's `If-None-Match`. */
    private class FakeTransport(
        vararg responses: Pair<Int, String>,
    ) : FeedTransport {
        val queue = ArrayDeque(responses.toList())
        val tags = mutableListOf<String?>()
        var gate: CompletableDeferred<Unit>? = null

        override suspend fun get(
            url: String,
            ifNoneMatch: String?,
        ): FeedResponse {
            tags += ifNoneMatch
            gate?.await()
            val (status, body) = queue.removeFirst()
            return FeedResponse(status, body.encodeToByteArray(), "fixture-v1", url)
        }
    }

    @AfterTest
    fun cleanUp() {
        folder.deleteRecursively()
    }

    private fun client(transport: FeedTransport) = FeedClient(url, folder.resolve("cache.json"), transport)

    @Test
    fun conditionalRefreshAndLastGoodCache() =
        runBlocking<Unit> {
            val good = """{"schemaVersion":1,"announcements":[]}"""
            val transport = FakeTransport(200 to good, 304 to "", 200 to "broken", 503 to "")
            val client = client(transport)
            repeat(4) { assertEquals(1, client.refresh().schemaVersion) }
            assertEquals(listOf(null, "fixture-v1", "fixture-v1", "fixture-v1"), transport.tags)
        }

    @Test
    fun firstFailureWithoutCacheThrowsAndInsecureUrlsAreRejected() =
        runBlocking<Unit> {
            assertFailsWith<FeedException> { client(FakeTransport(503 to "")).refresh() }
            val insecure = FeedClient("http://example.invalid/feed.json", folder.resolve("other.json"), FakeTransport())
            assertFailsWith<FeedException> { insecure.refresh() }
            val redirected =
                FeedClient(
                    url,
                    folder.resolve("third.json"),
                ) { _, _ -> FeedResponse(200, ByteArray(0), null, "http://x") }
            assertFailsWith<FeedException> { redirected.refresh() }
        }

    @Test
    fun concurrentRefreshesShareOneRequest() =
        runBlocking<Unit> {
            val transport =
                FakeTransport(200 to """{"schemaVersion":1,"announcements":[]}""").apply {
                    gate =
                        CompletableDeferred()
                }
            val client = client(transport)
            val results = (0 until 3).map { async { client.refresh() } }
            while (transport.tags.isEmpty()) kotlinx.coroutines.yield()
            transport.gate!!.complete(Unit)
            results.awaitAll()
            assertEquals(1, transport.tags.size)
        }

    @Test
    fun sampleJsonIsCachedAndRestoredIndependentlyOfCoverage() =
        runBlocking<Unit> {
            val body = Fixtures.text("corrections-v1.json")
            val row = CorrectionsFeed.decode(body).announcements.first()
            val transport = FakeTransport(200 to body, 304 to "", 200 to "broken", 503 to "", 304 to "")
            val client = client(transport)
            val covered = SavedLocation(24.0, 46.0, "Asia/Riyadh")
            repeat(4) {
                val confirmations = client.refresh().confirmations(covered, emptyList())
                assertEquals(listOf(row), confirmations)
                val engine = CalendarEngine(covered.zone, confirmed = confirmations.map { it.correction })
                val day = engine.resolve(row.start.toLocalDate()!!)
                assertEquals(row.month, day.month)
                assertEquals(1, day.day)
                assertEquals(DateProvenance.Confirmed, day.provenance)
            }
            assertEquals(listOf(null, "fixture-v1", "fixture-v1", "fixture-v1"), transport.tags)
            // A new client (app relaunch) restores from cache.
            assertEquals(listOf(row), client(FakeTransport()).cachedFeed()!!.confirmations(covered, emptyList()))
            // Following a source is independent of physical coverage.
            val mecca = SavedLocation(21.4225, 39.8262, "Asia/Riyadh")
            assertEquals(listOf(row), client.refresh().confirmations(mecca, emptyList()))
            assertNull(FeedClient(url, folder.resolve("missing.json"), FakeTransport()).cachedFeed())
        }

    @Test
    fun conflictingFeedIsRejectedSoTheCallerKeepsItsCalendar() {
        val london = SavedLocation(51.5, -0.1, "Europe/London")
        val month = HijriMonth(1448, 1)
        val baseline = CalendarEngine(london.zone)
        val coverage = Coverage(listOf("SA"), emptyList())
        val original =
            Announcement(
                "first",
                1,
                SightingMethod.NakedEye,
                CalendarSource.MIDDLE_EAST,
                coverage,
                month,
                CivilDate.of(baseline.start(month)),
            )
        val offsets = listOf(MonthOffset(month, -2))
        assertEquals(listOf(original), CorrectionsFeed(1, listOf(original)).confirmations(london, offsets))
        val next =
            original.copy(
                id = "next",
                month = month.advanced(1),
                start = CivilDate.of(baseline.start(month.advanced(1))),
            )
        assertFailsWith<CalendarException> { CorrectionsFeed(1, listOf(original, next)).confirmations(london, offsets) }
        assertTrue(CorrectionsFeed(1, emptyList()).confirmations(london, offsets).isEmpty())
    }

    @Test
    fun incompatibleAdjustmentIsRejected() {
        val riyadh = SavedLocation(24.0, 46.0, "Asia/Riyadh")
        val base = CalendarEngine(riyadh.zone)
        val month = (1..12).map { HijriMonth(1448, it) }.first { base.baselineLength(it) == 29 }
        val next = month.advanced(1)
        val row =
            Announcement(
                "thirty-day-month",
                1,
                SightingMethod.NakedEye,
                CalendarSource.MIDDLE_EAST,
                Coverage(listOf("SA"), emptyList()),
                next,
                CivilDate.of(base.start(next).plusDays(1)),
            )
        val confirmed = CorrectionsFeed(1, listOf(row)).confirmations(riyadh, emptyList()).map { it.correction }
        val saved = MonthOffset.replacing(MonthOffset.replacing(emptyList(), next, -1), month, -2)
        CalendarEngine.withOffsets(riyadh.zone, saved, confirmed)
        val removed = saved.filter { it.month != next }
        assertFailsWith<CalendarException> { CalendarEngine.withOffsets(riyadh.zone, removed, confirmed) }
    }
}

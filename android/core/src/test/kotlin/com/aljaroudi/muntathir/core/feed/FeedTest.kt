package com.aljaroudi.muntathir.core.feed

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.CalendarException
import com.aljaroudi.muntathir.core.calendar.CivilDate
import com.aljaroudi.muntathir.core.calendar.DateProvenance
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.location.SavedLocation
import kotlinx.serialization.SerializationException
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `FeedTests` and the feed cases of `CalendarTests` (MuntathirTests.swift).
class FeedTest {
    private val riyadh = SavedLocation(24.0, 46.0, "Riyadh", "SA", "Asia/Riyadh")
    private val month = HijriMonth(1448, 1)

    private fun square() =
        Coverage(
            countries = emptyList(),
            polygons =
                listOf(
                    listOf(GeoPoint(20.0, 40.0), GeoPoint(30.0, 40.0), GeoPoint(30.0, 50.0), GeoPoint(20.0, 50.0)),
                ),
        )

    @Test
    fun sharedFixtureDecodes() {
        assertEquals(1, CorrectionsFeed.decode(Fixtures.text("corrections-v1.json")).announcements.size)
    }

    @Test
    fun coverageAndSelectedSource() {
        val polygon = square()
        assertTrue(polygon.contains(riyadh))
        assertFalse(Coverage(listOf("IQ"), emptyList()).contains(riyadh))
        val engine = CalendarEngine(riyadh.zone)
        val row =
            Announcement(
                "example",
                1,
                SightingMethod.NakedEye,
                CalendarSource.MIDDLE_EAST,
                polygon,
                month,
                CivilDate.of(engine.start(month)),
            )
        val feed = CorrectionsFeed.decode(CorrectionsFeed.encode(CorrectionsFeed(1, listOf(row))))
        assertTrue(feed.matching(riyadh, null).isEmpty())
        assertTrue(feed.matching(riyadh, "other").isEmpty())
        assertEquals(1, feed.matching(riyadh, CalendarSource.MIDDLE_EAST).size)
        assertFailsWith<CalendarException> {
            CorrectionsFeed.decode(
                CorrectionsFeed.encode(CorrectionsFeed(2, emptyList())),
            )
        }
        assertFailsWith<CalendarException> {
            CorrectionsFeed.decode(CorrectionsFeed.encode(CorrectionsFeed(1, listOf(row, row))))
        }
    }

    @Test
    fun invalidRowsAndShapesRejectTheWholeFeed() {
        val engine = CalendarEngine(riyadh.zone)
        val row =
            Announcement(
                "a",
                1,
                SightingMethod.NakedEye,
                CalendarSource.MIDDLE_EAST,
                square(),
                month,
                CivilDate.of(engine.start(month)),
            )
        for (bad in listOf(
            row.copy(id = ""),
            row.copy(revision = 0),
            row.copy(method = SightingMethod.Calculation),
            row.copy(coverage = Coverage(listOf("sa"), emptyList())),
            row.copy(coverage = Coverage(emptyList(), emptyList())),
            row.copy(month = HijriMonth(1501, 1)),
            row.copy(start = CivilDate(2026, 2, 30)),
            row.copy(start = CivilDate.of(engine.start(month).plusDays(8))),
        )) {
            assertFailsWith<CalendarException>(bad.toString()) {
                CorrectionsFeed.decode(CorrectionsFeed.encode(CorrectionsFeed(1, listOf(bad))))
            }
        }
        // Like Swift's synthesized Codable: missing keys and unknown enum values fail.
        assertFailsWith<SerializationException> { CorrectionsFeed.decode("""{"schemaVersion":1}""") }
        val unknownMethod = CorrectionsFeed.encode(CorrectionsFeed(1, listOf(row))).replace("nakedEye", "telescope")
        assertFailsWith<SerializationException> { CorrectionsFeed.decode(unknownMethod) }
    }

    @Test
    fun dateLinePolygon() {
        val coverage =
            Coverage(
                emptyList(),
                listOf(
                    listOf(
                        GeoPoint(-10.0, 170.0),
                        GeoPoint(10.0, 170.0),
                        GeoPoint(10.0, -170.0),
                        GeoPoint(-10.0, -170.0),
                    ),
                ),
            )
        assertTrue(coverage.contains(SavedLocation(0.0, 179.0, "Date line", "", "GMT")))
        assertFalse(coverage.contains(SavedLocation(0.0, 0.0, "Greenwich", "", "GMT")))
    }

    @Test
    fun governmentSourceIsSaudiOnly() {
        assertEquals(listOf("SA"), CalendarSource.countries)
        assertEquals(CalendarMethod.Government, CalendarSource.method("government-SA"))
        for (country in listOf(
            "KW",
            "BH",
            "OM",
            "AE",
            "QA",
        )) {
            assertNull(CalendarSource.sightingMethod("government-$country"))
        }
    }

    @Test
    fun productionAnnouncementsResolveConfirmedMonths() {
        val feed = CorrectionsFeed.decode(Fixtures.repository("web/public/calendar/corrections-v1.json").readText())
        val mecca = SavedLocation(21.4, 39.8, "Mecca", "SA", "Asia/Riyadh")
        val october = CivilDate(2026, 10, 13)
        val november = CivilDate(2026, 11, 12)
        for ((source, starts) in listOf(
            CalendarSource.MIDDLE_EAST to listOf(october, november),
            "government-SA" to listOf(october),
        )) {
            val rows = feed.matching(mecca, source)
            assertEquals(starts.size, rows.size)
            val engine = CalendarEngine(ZoneId.of("Asia/Riyadh"), confirmed = rows.map { it.correction })
            starts.forEachIndexed { offset, start ->
                assertEquals(start, CivilDate.of(engine.start(HijriMonth(1448, 5 + offset))))
                assertEquals(DateProvenance.Confirmed, engine.resolve(start.toLocalDate()!!).provenance)
            }
        }
    }

    @Test
    fun knownSourcesApplyWorldwideAndRequireMatchingMethod() {
        val london = SavedLocation(51.5, -0.1, "London", "GB", "Europe/London")
        val coverage = Coverage(listOf("SA"), emptyList())
        val base = CalendarEngine(london.zone)
        for (source in listOf(CalendarSource.MIDDLE_EAST) + CalendarSource.countries.map { "government-$it" }) {
            val method = CalendarSource.sightingMethod(source)!!
            val row = Announcement(source, 1, method, source, coverage, month, CivilDate.of(base.start(month)))
            val wrong = row.copy(id = "$source-wrong", method = SightingMethod.AidedSight)
            val feed = CorrectionsFeed(1, listOf(row, wrong))
            assertEquals(listOf(row), feed.matching(london, source))
            assertTrue(feed.matching(london, null).isEmpty())
            assertTrue(feed.matching(london, "unknown").isEmpty())
        }
    }
}

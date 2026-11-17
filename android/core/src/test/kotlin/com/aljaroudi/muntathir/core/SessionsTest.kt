package com.aljaroudi.muntathir.core

import com.aljaroudi.muntathir.core.highlight.RecordSnapshot
import com.aljaroudi.muntathir.core.progress.ProgressActivity
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.core.progress.ReadingActivityClock
import com.aljaroudi.muntathir.core.rakaat.RakaatDetector
import com.aljaroudi.muntathir.core.rakaat.RakaatPreparation
import com.aljaroudi.muntathir.core.tasbih.TasbihSession
import com.aljaroudi.muntathir.core.text.ReadingTime
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `TasbihSessionTests`, `RakaatDetectorTests`, `RakaatPreparationTests`, `ReadingTimeTests`,
// `ProgressActivityTests` (pure parts) and the winner rules of `QuranUserStoreTests`. Not ported: the RealityKit
// bead scene and SwiftData persistence/migration tests (Room, P3.4/P5.5).
class SessionsTest {
    @Test
    fun tasbihCountsTheThreePhrasesAndStops() {
        var session = TasbihSession()
        var total = 0
        for ((phrase, target) in listOf("الله أكبر" to 34, "الحمد لله" to 33, "سبحان الله" to 33)) {
            for (count in 0 until target) {
                assertEquals(total, session.total)
                assertFalse(session.complete)
                assertEquals(phrase, session.phrase)
                assertEquals(target, session.target)
                assertEquals(count, session.count)
                session = session.advanced()
                total += 1
            }
        }
        assertTrue(session.complete)
        assertEquals(33, session.count)
        assertEquals(100, session.advanced().total)
        assertEquals(TasbihSession(), session.reset())
    }

    @Test
    fun tasbihPulls() {
        for ((dx, dy) in listOf(
            0.0 to 40.0,
            0.0 to -100.0,
            100.0 to 60.0,
            0.0 to 0.0,
        )) {
            assertFalse(TasbihSession.acceptsPull(dx, dy))
        }
        for ((dx, dy) in listOf(0.0 to 41.0, -20.0 to 80.0, 20.0 to 400.0)) {
            assertTrue(TasbihSession.acceptsPull(dx, dy))
            assertTrue(TasbihSession.pullProgress(dx, dy) <= 1)
        }
        assertEquals(0.5f, TasbihSession.pullProgress(0.0, 40.0))
        assertEquals(1f, TasbihSession.pullProgress(0.0, 400.0))
        assertEquals(0f, TasbihSession.pullProgress(0.0, -80.0))
        assertEquals(0f, TasbihSession.pullProgress(90.0, 80.0))
    }

    private class Feeder(
        val detector: RakaatDetector,
    ) {
        var time = 0.0

        fun feed(
            light: Double,
            seconds: Double,
        ) {
            repeat((seconds * 10).toInt()) {
                time += 0.1
                detector.sample(light, time)
            }
        }
    }

    @Test
    fun rakaatCountsPairsAndStopsAtTarget() {
        for (target in 2..4) {
            val feeder = Feeder(RakaatDetector(target))
            feeder.feed(0.8, 2.0)
            assertNotNull(feeder.detector.baseline)
            for (sujood in 1..target * 2) {
                feeder.feed(0.1, 2.0)
                assertEquals(sujood, feeder.detector.sujoodCount)
                assertEquals(sujood / 2, feeder.detector.rakaat)
                feeder.feed(0.8, 1.0)
            }
            assertTrue(feeder.detector.complete)
            feeder.feed(0.1, 3.0)
            assertEquals(target * 2, feeder.detector.sujoodCount)
        }
    }

    @Test
    fun rakaatRejectsBriefShadowsAndRequiresSustainedRecovery() {
        val feeder = Feeder(RakaatDetector(2))
        feeder.feed(0.8, 2.0)
        repeat(5) {
            feeder.feed(0.1, 0.3)
            feeder.feed(0.8, 0.3)
        }
        assertEquals(0, feeder.detector.sujoodCount)
        feeder.feed(0.1, 10.0)
        assertEquals(1, feeder.detector.sujoodCount)
        feeder.feed(0.8, 0.3)
        feeder.feed(0.1, 2.0)
        assertEquals(1, feeder.detector.sujoodCount)
        feeder.feed(0.8, 1.0)
        feeder.feed(0.1, 1.0)
        assertEquals(2, feeder.detector.sujoodCount)
    }

    @Test
    fun rakaatCalibrationNeedsStableUsableLight() {
        val feeder = Feeder(RakaatDetector(2))
        feeder.feed(0.02, 3.0)
        assertNull(feeder.detector.baseline)
        repeat(20) {
            feeder.feed(0.2, 0.1)
            feeder.feed(0.8, 0.1)
        }
        assertNull(feeder.detector.baseline)
        feeder.feed(0.8, 2.0)
        assertNotNull(feeder.detector.baseline)
        assertEquals(0, feeder.detector.sujoodCount)
    }

    @Test
    fun rakaatGapsAndInvalidSamplesCannotCompleteADarkTransition() {
        val feeder = Feeder(RakaatDetector(2))
        feeder.feed(0.8, 2.0)
        feeder.feed(0.1, 0.3)
        feeder.detector.sample(Double.NaN, feeder.time + 0.1)
        feeder.detector.sample(0.1, feeder.time - 1)
        feeder.time += 2
        feeder.feed(0.1, 0.3)
        assertEquals(0, feeder.detector.sujoodCount)
    }

    @Test
    fun rakaatGradualLightDriftDoesNotCount() {
        val feeder = Feeder(RakaatDetector(2))
        feeder.feed(0.8, 2.0)
        for (index in 0 until 200) feeder.feed(0.8 - index * 0.001, 0.1)
        assertEquals(0, feeder.detector.sujoodCount)
        assertTrue((feeder.detector.baseline ?: 1.0) < 0.8)
    }

    @Test
    fun rakaatPreparationDarknessRequiresSustainedSamplesAfterCountdown() {
        val preparation = RakaatPreparation()
        assertNull(preparation.sample(0.01, 4.9))
        for (index in 0 until 10) assertNull(preparation.sample(0.01, 5 + index / 10.0))
        assertEquals(RakaatPreparation.Failure.TooDark, preparation.sample(0.01, 6.0))
    }

    @Test
    fun rakaatPreparationChangingLightAndFrameGapsDoNotReportDarkness() {
        val preparation = RakaatPreparation()
        assertNull(preparation.sample(0.01, 5.0))
        assertNull(preparation.sample(0.01, 7.0))
        assertNull(preparation.sample(0.8, 7.1))
        assertNull(preparation.sample(0.01, 7.2))
        assertNull(preparation.sample(Double.NaN, 8.0))
        assertEquals(RakaatPreparation.Failure.Unstable, preparation.sample(0.8, 10.0))
        assertNull(RakaatPreparation().sample(0.8, 5.0))
    }

    @Test
    fun readingTimeRoundsUp() {
        for ((words, minutes) in listOf(0 to 0, 1 to 1, 200 to 1, 201 to 2, 11800 to 59, 11801 to 60, 12001 to 61)) {
            assertEquals(minutes, ReadingTime.minutes(words), "$words")
        }
    }

    @Test
    fun readingTimeUsesOneUnitAndOmitsEmptyText() {
        assertNull(ReadingTime.duration(0))
        assertEquals(ReadingTime.Duration(59, ReadingTime.Unit.Minutes), ReadingTime.duration(11800))
        assertEquals(ReadingTime.Duration(1, ReadingTime.Unit.Hours), ReadingTime.duration(11801))
        assertEquals(2, ReadingTime.duration(12001)?.value)
    }

    @Test
    fun readingTimePrimaryTextExcludesFormattingAndTranslation() {
        assertEquals(2, ReadingTime.words("نص عربي", "A much longer English translation"))
        assertEquals(2, ReadingTime.words(" \n", "**Two** [words](https://example.com)"))
        assertEquals(3, ReadingTime.words("# عنوان\n\nنص آخر"))
        assertEquals(0, ReadingTime.words("١٢٣ - …"))
        assertEquals(3, ReadingTime.words("", "[two words](https://example.com) ![](https://x.y/z.png) more"))
    }

    @Test
    fun readingClockIdleTimeBackgroundAndRepeatedFlushes() {
        val clock = ReadingActivityClock()
        clock.resume(100.0)
        clock.advance(115.0)
        assertEquals(15.0, clock.drain())
        clock.advance(500.0)
        assertEquals(285.0, clock.drain())
        clock.advance(600.0)
        assertEquals(0.0, clock.drain())
        clock.interact(600.0)
        clock.pause(620.0)
        assertEquals(20.0, clock.drain())
        clock.advance(1000.0)
        assertEquals(0.0, clock.drain())
        clock.resume(1000.0)
        clock.pause(1005.0)
        assertEquals(5.0, clock.drain())
        assertEquals(0.0, clock.drain())
    }

    @Test
    fun readingClockInteractionsExtendReadingWithoutCountingIdleGap() {
        val clock = ReadingActivityClock()
        clock.resume(0.0)
        clock.interact(200.0)
        clock.interact(400.0)
        clock.pause(1000.0)
        assertEquals(700.0, clock.drain())
    }

    @Test
    fun duplicateAndOutOfOrderSyncUsesLargestSessionSnapshot() {
        val old = ProgressActivity(ProgressActivityKind.Tasbih, 10.0, id = "session")
        val latest = old.copy(amount = 20.0)
        val otherSession = ProgressActivity(ProgressActivityKind.Tasbih, 4.0)
        val reading = ProgressActivity(ProgressActivityKind.QuranReading, 90.0)
        for (records in listOf(
            listOf(old, latest, otherSession, reading, latest),
            listOf(latest, old, reading, otherSession),
        )) {
            val totals = ProgressActivity.totals(records)
            assertEquals(24.0, totals[ProgressActivityKind.Tasbih])
            assertEquals(90.0, totals[ProgressActivityKind.QuranReading])
            assertNull(totals[ProgressActivityKind.HadithReading])
        }
        val invalid =
            listOf(
                ProgressActivity(ProgressActivityKind.Tasbih, -1.0),
                ProgressActivity(ProgressActivityKind.Tasbih, 1.5),
                ProgressActivity(ProgressActivityKind.HadithReading, Double.POSITIVE_INFINITY),
            )
        assertTrue(ProgressActivity.totals(invalid).isEmpty())
    }

    @Test
    fun winnersUseStableTieBreakAndLocalEditsBeatImportedState() {
        val at100 = Instant.ofEpochSecond(100)
        val rows = listOf("a", "z").map { RecordSnapshot(it, "item", """{"note":"$it"}""", at100, false) }
        assertEquals("z", RecordSnapshot.winners(rows).getValue("item").recordID)
        assertEquals(RecordSnapshot.winners(rows), RecordSnapshot.winners(rows.reversed()))
        val newer = rows[0].copy(modifiedAt = Instant.ofEpochSecond(101))
        assertEquals("a", RecordSnapshot.winners(rows + newer).getValue("item").recordID)
        // A local save with a clock behind the imported winner still lands after it.
        val winner = RecordSnapshot.winners(rows).getValue("item")
        assertTrue(RecordSnapshot.nextModifiedAt(Instant.ofEpochSecond(50), winner) > at100)
        assertEquals(Instant.ofEpochSecond(500), RecordSnapshot.nextModifiedAt(Instant.ofEpochSecond(500), winner))
        assertEquals(Instant.ofEpochSecond(5), RecordSnapshot.nextModifiedAt(Instant.ofEpochSecond(5), null))
    }
}

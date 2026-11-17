package com.aljaroudi.muntathir.core.calendar

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.time.chrono.HijrahChronology
import java.time.chrono.HijrahDate
import java.time.temporal.ChronoField

/**
 * Umm al-Qura month starts exported from Apple's calendar (`shared/ummalqura.json`), so Android, the JVM
 * and iOS share one baseline. `HijrahChronology` covers dates outside the exported range.
 */
object UmmAlQura {
    @Serializable
    private class Table(
        val first: HijriMonth,
        val start: String,
        val lengths: String,
    )

    private val first: HijriMonth
    private val starts: LongArray

    init {
        val text =
            checkNotNull(UmmAlQura::class.java.getResourceAsStream("/ummalqura.json")) { "Missing ummalqura.json" }
                .use { it.readBytes().decodeToString() }
        val table = Json { ignoreUnknownKeys = true }.decodeFromString<Table>(text)
        first = table.first
        starts = LongArray(table.lengths.length + 1)
        starts[0] = LocalDate.parse(table.start).toEpochDay()
        table.lengths.forEachIndexed { index, length ->
            starts[index + 1] = starts[index] + if (length == '9') 29 else 30
        }
    }

    /** First and last months whose start and length come from the table. */
    val coverage: ClosedRange<HijriMonth> get() = first..first.advanced(starts.size - 2)

    fun start(month: HijriMonth): LocalDate {
        val offset = month.index - first.index
        if (offset in starts.indices) return LocalDate.ofEpochDay(starts[offset])
        return LocalDate.from(HijrahChronology.INSTANCE.date(month.year, month.month, 1))
    }

    fun length(month: HijriMonth): Int = (start(month.advanced(1)).toEpochDay() - start(month).toEpochDay()).toInt()

    fun month(date: LocalDate): HijriMonth {
        val day = date.toEpochDay()
        if (day >= starts.first() && day < starts.last()) {
            val found = starts.binarySearch(day)
            val offset = if (found >= 0) found else -found - 2
            return first.advanced(offset)
        }
        val hijrah = HijrahDate.from(date)
        return HijriMonth(hijrah.get(ChronoField.YEAR), hijrah.get(ChronoField.MONTH_OF_YEAR))
    }
}

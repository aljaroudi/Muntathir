package com.aljaroudi.muntathir.core.calendar

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** A Gregorian calendar day, independent of time zone. Mirrors Swift `CivilDate`. */
@Serializable
data class CivilDate(
    val year: Int,
    val month: Int,
    val day: Int,
) : Comparable<CivilDate> {
    /** The day, or `null` when the components don't form a real date (e.g. February 30). */
    fun toLocalDate(): LocalDate? =
        try {
            LocalDate.of(year, month, day)
        } catch (_: DateTimeException) {
            null
        }

    override fun compareTo(other: CivilDate): Int = compareValuesBy(this, other, { it.year }, { it.month }, { it.day })

    companion object {
        fun of(date: LocalDate) = CivilDate(date.year, date.monthValue, date.dayOfMonth)

        fun of(
            instant: Instant,
            zone: ZoneId,
        ) = of(instant.atZone(zone).toLocalDate())
    }
}

@Serializable
data class HijriMonth(
    val year: Int,
    val month: Int,
) : Comparable<HijriMonth> {
    val index: Int get() = year * 12 + month - 1

    val isValid: Boolean get() = year in 1350..1500 && month in 1..12

    fun advanced(count: Int): HijriMonth {
        val value = index + count
        return HijriMonth(Math.floorDiv(value, 12), Math.floorMod(value, 12) + 1)
    }

    override fun compareTo(other: HijriMonth): Int = index.compareTo(other.index)
}

@Serializable
enum class DateProvenance {
    @SerialName("calculated")
    Calculated,

    @SerialName("confirmed")
    Confirmed,

    @SerialName("manual")
    Manual,
}

@Serializable
data class MonthCorrection(
    val month: HijriMonth,
    val start: CivilDate,
    val provenance: DateProvenance,
    val sourceID: String? = null,
)

/** A user adjustment relative to the source calendar. Positive days start the month earlier. */
@Serializable
data class MonthOffset(
    val month: HijriMonth,
    val days: Int,
) {
    companion object {
        val range = -2..2

        fun isValid(offsets: List<MonthOffset>): Boolean =
            offsets.all { it.month.isValid && it.days in range } &&
                offsets.distinctBy { it.month }.size == offsets.size

        /** The offsets after setting [month] to [days]; zero removes the adjustment. */
        fun replacing(
            offsets: List<MonthOffset>,
            month: HijriMonth,
            days: Int,
        ): List<MonthOffset> =
            offsets.filter { it.month != month } + listOfNotNull(MonthOffset(month, days).takeIf { days != 0 })
    }
}

data class ResolvedDay(
    val month: HijriMonth,
    val day: Int,
    val provenance: DateProvenance,
    val sourceID: String? = null,
)

class CalendarException(
    val kind: Kind,
) : Exception(kind.name) {
    enum class Kind { InvalidDate, ConflictingMonths }
}

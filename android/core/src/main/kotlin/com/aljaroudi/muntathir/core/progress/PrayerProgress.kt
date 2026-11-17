package com.aljaroudi.muntathir.core.progress

import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerCalculator
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerMoment
import com.aljaroudi.muntathir.core.prayer.PrayerName
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/** One prayer counted by the Rakaat tracker. Port of Swift `PrayerCompletion`. */
@Serializable
data class PrayerCompletion(
    val id: String,
    val prayer: PrayerName,
    @Serializable(with = EpochSeconds::class) val startedAt: Instant,
    @Serializable(with = EpochSeconds::class) val completedAt: Instant,
    /** `yyyy-MM-dd` in [timeZoneID]; Maghrib and Isha after midnight belong to the previous evening. */
    val prayerDay: String,
    val timeZoneID: String,
    val location: SavedLocation? = null,
    val method: PrayerMethod,
    @Serializable(with = EpochSeconds::class) val athan: Instant? = null,
    @Serializable(with = EpochSeconds::class) val deadline: Instant? = null,
    val timing: PrayerTiming,
)

/** Titles and icons are app resources. */
@Serializable
enum class PrayerTiming(
    /** Higher wins when one prayer is recorded more than once on a day. */
    val priority: Int,
) {
    @SerialName("onTime")
    OnTime(2),

    @SerialName("outsideTime")
    OutsideTime(1),

    @SerialName("unavailable")
    Unavailable(0),
}

/** Port of Swift `PrayerProgress`. */
object PrayerProgress {
    val prayers =
        listOf(PrayerName.Fajr, PrayerName.Dhuhr, PrayerName.Asr, PrayerName.Maghrib, PrayerName.Isha)

    /** The obligatory prayers with [target] rakaat. */
    fun choices(target: Int): List<PrayerName> =
        when (target) {
            2 -> listOf(PrayerName.Fajr)
            3 -> listOf(PrayerName.Maghrib)
            4 -> listOf(PrayerName.Dhuhr, PrayerName.Asr, PrayerName.Isha)
            else -> emptyList()
        }

    fun dayKey(day: LocalDate): String = "%04d-%02d-%02d".format(day.year, day.monthValue, day.dayOfMonth)

    /**
     * The record for [prayer] performed at [instant]: its prayer day, the window from its athan (Dhuhr for Asr,
     * Maghrib for Isha) to its end (sunrise, sunset or midnight), and whether [instant] fell inside it.
     */
    fun snapshot(
        prayer: PrayerName,
        instant: Instant,
        location: SavedLocation?,
        method: PrayerMethod,
        fallbackZone: ZoneId = ZoneId.systemDefault(),
        calculate: (LocalDate, SavedLocation, PrayerMethod) -> List<PrayerMoment> = { day, place, chosen ->
            PrayerCalculator.times(day, place, chosen)
        },
    ): PrayerCompletion {
        val zone = location?.takeIf { it.hasValidZone }?.zone ?: fallbackZone
        var day = instant.atZone(zone).toLocalDate()
        var moments = emptyList<PrayerMoment>()
        if (location != null && location.isValid) {
            moments = calculate(day, location, method)
            val fajr = moments.firstOrNull { it.name == PrayerName.Fajr }?.time
            if ((prayer == PrayerName.Maghrib || prayer == PrayerName.Isha) && fajr != null && instant < fajr) {
                day = day.minusDays(1)
                moments = calculate(day, location, method)
            }
        }
        val end =
            when (prayer) {
                PrayerName.Fajr -> PrayerName.Sunrise
                PrayerName.Dhuhr, PrayerName.Asr -> PrayerName.Sunset
                else -> PrayerName.Midnight
            }
        val start =
            when (prayer) {
                PrayerName.Asr -> PrayerName.Dhuhr
                PrayerName.Isha -> PrayerName.Maghrib
                else -> prayer
            }
        val athan = moments.firstOrNull { it.name == start }?.time
        val deadline = moments.firstOrNull { it.name == end }?.time
        val timing =
            if (prayer.isPrayer && athan != null && deadline != null && deadline > athan) {
                if (instant >= athan && instant < deadline) PrayerTiming.OnTime else PrayerTiming.OutsideTime
            } else {
                PrayerTiming.Unavailable
            }
        return PrayerCompletion(
            id = UUID.randomUUID().toString().uppercase(),
            prayer = prayer,
            startedAt = instant,
            completedAt = instant,
            prayerDay = dayKey(day),
            timeZoneID = zone.id,
            location = location,
            method = method,
            athan = athan,
            deadline = deadline,
            timing = timing,
        )
    }

    /** The best timing per prayer day for [prayer]; a record id counts once. */
    fun days(
        prayer: PrayerName,
        records: List<PrayerCompletion>,
    ): Map<String, PrayerTiming> {
        val seen = mutableSetOf<String>()
        val days = mutableMapOf<String, PrayerTiming>()
        for (record in records.sortedBy { it.completedAt }) {
            if (record.prayer != prayer || !seen.add(record.id)) continue
            val existing = days[record.prayerDay]
            if (existing != null && existing.priority >= record.timing.priority) continue
            days[record.prayerDay] = record.timing
        }
        return days
    }
}

/**
 * One tracker session's record: the snapshot is taken once calibration succeeds (when the prayer starts), and
 * returned with its completion time exactly once. A failure ends the session without a record.
 */
class PrayerSessionRecording {
    var snapshot: PrayerCompletion? = null
        private set
    private var finished = false

    fun update(
        calibrated: Boolean,
        complete: Boolean,
        failed: Boolean,
        instant: Instant,
        makeSnapshot: () -> PrayerCompletion?,
    ): PrayerCompletion? {
        if (finished) return null
        if (failed) {
            finished = true
            return null
        }
        if (calibrated && snapshot == null) snapshot = makeSnapshot()
        if (!complete) return null
        finished = true
        return snapshot?.copy(completedAt = instant)
    }
}

/** Seconds since 1970 as a JSON number, like [ProgressActivity.date]; millisecond precision. */
internal object EpochSeconds : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("EpochSeconds", PrimitiveKind.DOUBLE)

    override fun serialize(
        encoder: Encoder,
        value: Instant,
    ) = encoder.encodeDouble(value.toEpochMilli() / 1000.0)

    override fun deserialize(decoder: Decoder): Instant =
        Instant.ofEpochMilli(Math.round(decoder.decodeDouble() * 1000))
}

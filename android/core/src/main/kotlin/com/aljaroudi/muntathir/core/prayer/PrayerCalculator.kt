package com.aljaroudi.muntathir.core.prayer

import com.aljaroudi.muntathir.core.calendar.UmmAlQura
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.adhan.CalculationMethod
import com.aljaroudi.muntathir.core.prayer.adhan.Coordinates
import com.aljaroudi.muntathir.core.prayer.adhan.HighLatitudeRule
import com.aljaroudi.muntathir.core.prayer.adhan.Madhab
import com.aljaroudi.muntathir.core.prayer.adhan.PrayerTimes
import com.aljaroudi.muntathir.core.prayer.adhan.Qibla
import com.aljaroudi.muntathir.core.roundedAwayFromZero
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate

/** Titles are app resources. */
@Serializable
enum class PrayerMethod {
    /** Jafari, Qum (PrayTimes convention). */
    @SerialName("jafari")
    Jafari,

    /** Jafari, Tehran (Institute of Geophysics). */
    @SerialName("tehran")
    Tehran,

    @SerialName("ummAlQura")
    UmmAlQura,
}

/** Display order matches Swift `PrayerName.allCases`. */
@Serializable
enum class PrayerName(
    /** Swift raw value, used in stored settings and notification ids. */
    val id: String,
) {
    @SerialName("imsak")
    Imsak("imsak"),

    @SerialName("fajr")
    Fajr("fajr"),

    @SerialName("sunrise")
    Sunrise("sunrise"),

    @SerialName("dhuhr")
    Dhuhr("dhuhr"),

    @SerialName("asr")
    Asr("asr"),

    @SerialName("sunset")
    Sunset("sunset"),

    @SerialName("maghrib")
    Maghrib("maghrib"),

    @SerialName("isha")
    Isha("isha"),

    @SerialName("midnight")
    Midnight("midnight"),
    ;

    val isRequired: Boolean get() = this == Fajr || this == Dhuhr || this == Maghrib

    val isPrayer: Boolean get() = this == Fajr || this == Dhuhr || this == Asr || this == Maghrib || this == Isha

    fun isVisible(hidden: Set<PrayerName>): Boolean = isRequired || this !in hidden

    companion object {
        val optionalTimes: List<PrayerName> get() = entries.filter { !it.isRequired }
        val notifiable: List<PrayerName> get() = entries.filter { it.isPrayer }
    }
}

data class PrayerMoment(
    val name: PrayerName,
    val time: Instant,
)

object PrayerCalculator {
    /**
     * The nine daily times in [PrayerName] order for [date] at [location] (midnight is omitted when the
     * next day can't be calculated). Empty when the sun doesn't reach the method's angles, never invented.
     */
    fun times(
        date: LocalDate,
        location: SavedLocation,
        method: PrayerMethod,
        imsakMinutes: Int = 10,
    ): List<PrayerMoment> {
        // Display metadata must not suppress astronomical calculations for a valid coordinate.
        if (!location.hasValidCoordinates) return emptyList()
        val coordinates = Coordinates(location.latitude, location.longitude)
        val preset = if (method == PrayerMethod.Tehran) CalculationMethod.Tehran else CalculationMethod.Other
        var parameters =
            when (method) {
                PrayerMethod.Tehran -> {
                    preset.params
                }

                PrayerMethod.UmmAlQura -> {
                    CalculationMethod.UmmAlQura.params
                }

                // PrayTimes Jafari/Qum convention: https://praytimes.org/docs/methods
                PrayerMethod.Jafari -> {
                    CalculationMethod.Other.params.copy(
                        fajrAngle = 16.0,
                        maghribAngle = 4.0,
                        ishaAngle = 14.0,
                    )
                }
            }.copy(madhab = Madhab.Shafi, highLatitudeRule = HighLatitudeRule.recommended(coordinates))
        // Use the independent calculated calendar for the preset's Ramadan interval.
        if (method == PrayerMethod.UmmAlQura && UmmAlQura.month(date).month == 9) {
            parameters = parameters.copy(ishaInterval = parameters.ishaInterval + 30)
        }
        val times = PrayerTimes.calculate(coordinates, date, parameters) ?: return emptyList()
        // A neutral preset avoids method-specific Maghrib offsets when obtaining sunset.
        val solarParameters =
            CalculationMethod.Other.params.copy(
                fajrAngle = parameters.fajrAngle,
                ishaAngle = 18.0,
                highLatitudeRule = parameters.highLatitudeRule,
            )
        val solar = PrayerTimes.calculate(coordinates, date, solarParameters) ?: return emptyList()
        if (method == PrayerMethod.Tehran || method == PrayerMethod.Jafari) {
            // Adhan silently falls back to sunset when the Maghrib angle is unreachable; treat that as failure.
            val sunset =
                PrayerTimes.calculate(coordinates, date, parameters.copy(maghribAngle = null)) ?: return emptyList()
            if (times.maghrib <= sunset.maghrib) return emptyList()
        }
        val imsak = imsakMinutes.coerceIn(0, 120).toLong()
        val result =
            mutableListOf(
                PrayerMoment(PrayerName.Imsak, times.fajr.minusSeconds(imsak * 60)),
                PrayerMoment(PrayerName.Fajr, times.fajr),
                PrayerMoment(PrayerName.Sunrise, times.sunrise),
                PrayerMoment(PrayerName.Dhuhr, times.dhuhr),
                PrayerMoment(PrayerName.Asr, times.asr),
                PrayerMoment(PrayerName.Sunset, solar.maghrib),
                PrayerMoment(PrayerName.Maghrib, times.maghrib),
                PrayerMoment(PrayerName.Isha, times.isha),
            )
        PrayerTimes.calculate(coordinates, date.plusDays(1), parameters)?.let { next ->
            val sunset = solar.maghrib.epochSecond.toDouble()
            val midpoint = sunset + (next.fajr.epochSecond - sunset) / 2
            val minute = (midpoint / 60).roundedAwayFromZero().toLong()
            result += PrayerMoment(PrayerName.Midnight, Instant.ofEpochSecond(minute * 60))
        }
        return result
    }

    /** Times for the civil day containing [instant] at the location. */
    fun times(
        instant: Instant,
        location: SavedLocation,
        method: PrayerMethod,
        imsakMinutes: Int = 10,
    ) = times(instant.atZone(location.zone).toLocalDate(), location, method, imsakMinutes)

    /** Great-circle bearing to the Kaaba, in degrees from true north. */
    fun qibla(location: SavedLocation): Double = Qibla.direction(Coordinates(location.latitude, location.longitude))
}

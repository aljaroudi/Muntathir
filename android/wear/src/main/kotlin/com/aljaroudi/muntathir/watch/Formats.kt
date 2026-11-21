package com.aljaroudi.muntathir.watch

import android.content.Context
import android.icu.text.DateFormat
import android.icu.text.DateFormatSymbols
import android.icu.text.DateTimePatternGenerator
import android.icu.text.NumberFormat
import android.icu.text.SimpleDateFormat
import android.icu.util.IslamicCalendar
import android.icu.util.TimeZone
import android.icu.util.ULocale
import androidx.annotation.StringRes
import com.aljaroudi.muntathir.core.prayer.PrayerName
import java.time.Instant
import java.time.ZoneId
import java.util.Date
import java.util.Locale

/** ICU formatting matching the phone's `Formats` (locale digits, Umm al-Qura month names). */
object Formats {
    fun locale(context: Context): Locale = context.resources.configuration.locales[0]

    /** A time of day with the locale's AM/PM, for the list and spoken descriptions. */
    fun time(
        instant: Instant,
        zone: ZoneId,
        locale: Locale,
    ): String =
        DateFormat
            .getInstanceForSkeleton("jmm", locale)
            .apply { timeZone = TimeZone.getTimeZone(zone.id) }
            .format(Date.from(instant))

    /** The locale's clock without AM/PM (Swift `.hour(.defaultDigits(amPM: .omitted))`), for complications. */
    fun clockTime(
        instant: Instant,
        zone: ZoneId,
        locale: Locale,
    ): String {
        val best = DateTimePatternGenerator.getInstance(ULocale.forLocale(locale)).getBestPattern("jmm")
        val pattern = best.filterNot { it == 'a' || it == 'b' || it == 'B' }.trim()
        return SimpleDateFormat(pattern, ULocale.forLocale(locale))
            .apply { timeZone = TimeZone.getTimeZone(zone.id) }
            .format(Date.from(instant))
    }

    fun hijriMonth(
        month: Int,
        locale: Locale,
    ): String =
        DateFormatSymbols(IslamicCalendar(ULocale.forLocale(locale)), ULocale.forLocale(locale)).months[
            month -
                1,
        ]

    fun number(
        value: Int,
        locale: Locale,
    ): String = NumberFormat.getInstance(locale).apply { isGroupingUsed = false }.format(value)
}

@get:StringRes
val PrayerName.title: Int
    get() =
        when (this) {
            PrayerName.Imsak -> R.string.imsak
            PrayerName.Fajr -> R.string.fajr
            PrayerName.Sunrise -> R.string.sunrise
            PrayerName.Dhuhr -> R.string.dhuhr
            PrayerName.Asr -> R.string.asr
            PrayerName.Sunset -> R.string.sunset
            PrayerName.Maghrib -> R.string.maghrib
            PrayerName.Isha -> R.string.isha
            PrayerName.Midnight -> R.string.midnight
        }

package com.aljaroudi.muntathir.ui.components

import android.icu.text.DateFormat
import android.icu.text.DateFormatSymbols
import android.icu.text.DateTimePatternGenerator
import android.icu.text.DisplayContext
import android.icu.text.MeasureFormat
import android.icu.text.NumberFormat
import android.icu.text.RelativeDateTimeFormatter
import android.icu.text.SimpleDateFormat
import android.icu.util.IslamicCalendar
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.icu.util.TimeZone
import android.icu.util.ULocale
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalConfiguration
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.Date
import java.util.Locale
import kotlin.math.ceil

/** The per-app language as Compose sees it (AppCompat updates the activity configuration). */
@Composable
@ReadOnlyComposable
fun currentLocale(): Locale = LocalConfiguration.current.locales[0]

/**
 * ICU formatting, like Foundation's: locale digits (e.g. Arabic-Indic), Umm al-Qura month names and
 * locale-aware date skeletons.
 */
object Formats {
    /** Hijri month names (Swift `DateFormatter` with `.islamicUmmAlQura`, `monthSymbols`). */
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

    /** `+1`, `−2`, `0`: Swift `.sign(strategy: .always(includingZero: false))`. */
    fun signed(
        value: Int,
        locale: Locale,
    ): String {
        // A left-to-right mark keeps the sign in front of the digits in right-to-left text.
        val mark = Char(0x200E)
        return when {
            value > 0 -> "$mark+${number(value, locale)}"
            value < 0 -> "$mark-${number(-value, locale)}"
            else -> number(0, locale)
        }
    }

    /** A civil date with an ICU skeleton, e.g. `EEEdMMM` → "Tue, 17 Nov". */
    fun date(
        date: LocalDate,
        skeleton: String,
        locale: Locale,
    ): String =
        DateFormat
            .getInstanceForSkeleton(skeleton, locale)
            .apply { timeZone = TimeZone.GMT_ZONE }
            .format(Date.from(date.atTime(12, 0).toInstant(ZoneOffset.UTC)))

    /** A time of day in [zone] without AM/PM when the locale uses a 12-hour clock (Swift prayer rows). */
    fun time(
        instant: java.time.Instant,
        zone: ZoneId,
        locale: Locale,
        skeleton: String = "jmm",
    ): String =
        DateFormat
            .getInstanceForSkeleton(skeleton, locale)
            .apply { timeZone = TimeZone.getTimeZone(zone.id) }
            .format(Date.from(instant))

    /** Prayer-row time: the locale's clock without AM/PM (Swift `.hour(.defaultDigits(amPM: .omitted))`). */
    fun clockTime(
        instant: java.time.Instant,
        zone: ZoneId,
        locale: Locale,
    ): String {
        val best = DateTimePatternGenerator.getInstance(ULocale.forLocale(locale)).getBestPattern("jmm")
        val pattern = best.filterNot { it == 'a' || it == 'b' || it == 'B' }.trim()
        return SimpleDateFormat(pattern, ULocale.forLocale(locale))
            .apply { timeZone = TimeZone.getTimeZone(zone.id) }
            .format(Date.from(instant))
    }

    /** "Today", "Tomorrow" (named relative day, sentence case). */
    fun relativeDay(
        days: Int,
        locale: Locale,
    ): String =
        RelativeDateTimeFormatter
            .getInstance(
                ULocale.forLocale(locale),
                null,
                RelativeDateTimeFormatter.Style.LONG,
                DisplayContext.CAPITALIZATION_FOR_BEGINNING_OF_SENTENCE,
            ).format(
                if (days == 0) RelativeDateTimeFormatter.Direction.THIS else RelativeDateTimeFormatter.Direction.NEXT,
                RelativeDateTimeFormatter.AbsoluteUnit.DAY,
            )

    /** "in 3 days" (Swift `RelativeDateTimeFormatter`, numeric, full). */
    fun inDays(
        days: Int,
        locale: Locale,
    ): String =
        RelativeDateTimeFormatter
            .getInstance(ULocale.forLocale(locale))
            .format(
                days.toDouble(),
                RelativeDateTimeFormatter.Direction.NEXT,
                RelativeDateTimeFormatter.RelativeUnit.DAYS,
            )

    /** Swift `ReadingTimeHint`: "12 minutes" below an hour, otherwise whole hours rounded up; `null` without words. */
    fun readingTime(
        words: Int,
        locale: Locale,
    ): String? {
        val duration =
            com.aljaroudi.muntathir.core.text.ReadingTime
                .duration(words) ?: return null
        val unit =
            when (duration.unit) {
                com.aljaroudi.muntathir.core.text.ReadingTime.Unit.Minutes -> MeasureUnit.MINUTE
                com.aljaroudi.muntathir.core.text.ReadingTime.Unit.Hours -> MeasureUnit.HOUR
            }
        return MeasureFormat
            .getInstance(ULocale.forLocale(locale), MeasureFormat.FormatWidth.WIDE)
            .format(Measure(duration.value, unit))
    }

    /** One unit, rounded up: "2 hours", "35 minutes", "3 days" (Swift countdown badges). */
    fun duration(
        duration: Duration,
        locale: Locale,
        allowDays: Boolean = false,
    ): String {
        val minutes = ceil(duration.seconds / 60.0).toLong().coerceAtLeast(0)
        val measure =
            when {
                allowDays && minutes >= 24 * 60 -> Measure(ceil(minutes / 1440.0).toLong(), MeasureUnit.DAY)
                minutes >= 60 -> Measure(minutes / 60, MeasureUnit.HOUR)
                else -> Measure(minutes, MeasureUnit.MINUTE)
            }
        return MeasureFormat.getInstance(ULocale.forLocale(locale), MeasureFormat.FormatWidth.WIDE).format(measure)
    }
}

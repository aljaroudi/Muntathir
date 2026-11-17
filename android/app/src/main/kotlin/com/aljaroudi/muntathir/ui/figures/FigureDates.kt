package com.aljaroudi.muntathir.ui.figures

import android.icu.text.DateFormatSymbols
import android.icu.text.MeasureFormat
import android.icu.util.GregorianCalendar
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.icu.util.ULocale
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.figures.FigureAge
import com.aljaroudi.muntathir.core.figures.FigureDate
import com.aljaroudi.muntathir.ui.components.Formats
import java.util.Locale

/** Swift `FigureDateView`: the claim in its own calendar and era, with its precision. */
@Composable
internal fun FigureDateText(
    date: FigureDate,
    locale: Locale,
    modifier: Modifier = Modifier,
) {
    val start = point(date, date.start, locale)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        val text =
            when (date.precision) {
                FigureDate.Precision.Exact -> {
                    start
                }

                FigureDate.Precision.Approximate -> {
                    stringResource(R.string.about_x, start)
                }

                FigureDate.Precision.Range -> {
                    date.end?.let {
                        stringResource(
                            R.string.from_x_to_x,
                            start,
                            point(date, it, locale),
                        )
                    }
                }
            }
        text?.let { Text(it, style = MaterialTheme.typography.bodyLarge) }
        if (date.calendar != FigureDate.CalendarKind.Hijri) {
            Text(
                stringResource(
                    if (date.calendar ==
                        FigureDate.CalendarKind.Gregorian
                    ) {
                        R.string.gregorian
                    } else {
                        R.string.julian
                    },
                ),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** "15 Ramadan 3 AH": day, month name, ungrouped year and era, each when known. */
@Composable
private fun point(
    date: FigureDate,
    point: FigureDate.Point,
    locale: Locale,
): String {
    val era =
        stringResource(
            when (date.era) {
                FigureDate.Era.AH -> R.string.ah
                FigureDate.Era.BH -> R.string.bh
                FigureDate.Era.CE -> R.string.ce
                FigureDate.Era.BCE -> R.string.bce
            },
        )
    val hijri = date.calendar == FigureDate.CalendarKind.Hijri
    val month = point.month?.let { if (hijri) hijriMonth(it, locale) else gregorianMonth(it, locale) }
    val day = point.day?.let { Formats.number(it, locale) }
    return listOfNotNull(day, month, Formats.number(point.year, locale), era).joinToString(" ")
}

/** Swift `FigureDateView.hijriDay`: "10 Muharram". */
internal fun hijriDay(
    day: Int,
    month: Int,
    locale: Locale,
): String = Formats.number(day, locale) + " " + hijriMonth(month, locale)

private fun hijriMonth(
    month: Int,
    locale: Locale,
): String = if (month in 1..12) Formats.hijriMonth(month, locale) else Formats.number(month, locale)

// Swift uses Gregorian month names for Julian dates too.
private fun gregorianMonth(
    month: Int,
    locale: Locale,
): String {
    val symbols = DateFormatSymbols(GregorianCalendar(ULocale.forLocale(locale)), ULocale.forLocale(locale)).months
    return symbols.getOrNull(month - 1) ?: Formats.number(month, locale)
}

/** Swift `DateComponentsFormatter` (full): "35 years", "1 year, 1 month", "5 months". */
internal fun formattedAge(
    age: FigureAge,
    locale: Locale,
): String {
    val months = age.months ?: 0
    val measures =
        buildList {
            if (age.years > 0 || months == 0) add(Measure(age.years, MeasureUnit.YEAR))
            if (months > 0) add(Measure(months, MeasureUnit.MONTH))
        }
    return MeasureFormat
        .getInstance(ULocale.forLocale(locale), MeasureFormat.FormatWidth.WIDE)
        .formatMeasures(*measures.toTypedArray())
}

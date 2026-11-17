package com.aljaroudi.muntathir.ui.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.calendar.CalendarTargets
import com.aljaroudi.muntathir.core.calendar.CalendarYear
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.ResolvedDay
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.currentLocale
import java.time.format.TextStyle
import java.time.temporal.WeekFields

/** Swift `CalendarScreen.datePicker`: a Hijri month grid aligned to the locale's first weekday. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JumpToDateSheet(
    month: HijriMonth,
    state: CalendarUi,
    onMonth: (HijriMonth) -> Unit,
    onDismiss: () -> Unit,
    onDay: (ResolvedDay) -> Unit,
) {
    val locale = currentLocale()
    val engine = state.engine
    val days = remember(month, engine) { engine.days(month) }
    val firstWeekday = WeekFields.of(locale).firstDayOfWeek
    val blanks = Math.floorMod(days.first().dayOfWeek.value - firstWeekday.value, 7)
    val title = "${Formats.hijriMonth(month.month, locale)} ${Formats.number(month.year, locale)}"
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.jump_to_date), style = MaterialTheme.typography.titleLarge)
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(
                    onClick = { onMonth(month.advanced(-1)) },
                    enabled =
                        month > HijriMonth(CalendarYear.FIRST, 1),
                ) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, stringResource(R.string.previous_month))
                }
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f).testTag("calendar-month-title"),
                )
                IconButton(
                    onClick = { onMonth(month.advanced(1)) },
                    enabled = month < HijriMonth(CalendarYear.LAST, 12),
                ) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, stringResource(R.string.next_month))
                }
            }
            if (CalendarTargets.isExpected(month, state.now, engine, state.confirmations)) {
                Text(
                    stringResource(R.string.future_dates_are_estimates_until_the_month_s_moo),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Row {
                (0 until 7).forEach { index ->
                    Text(
                        firstWeekday.plus(index.toLong()).getDisplayName(TextStyle.SHORT, locale),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            val cells = List(blanks) { null } + days
            cells.chunked(7).forEach { week ->
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    week.forEach { date ->
                        Box(Modifier.weight(1f)) {
                            if (date != null) {
                                val day = engine.resolve(date)
                                val today = date == state.today
                                val hasEvents = state.library.events(day).isNotEmpty()
                                val label = "${Formats.number(day.day, locale)} $title"
                                DayCell(
                                    day.day,
                                    date.dayOfMonth,
                                    today,
                                    hasEvents,
                                    label,
                                    locale,
                                    Modifier.testTag("calendar-day-${day.month.year}-${day.month.month}-${day.day}"),
                                ) { onDay(day) }
                            }
                        }
                    }
                    repeat(7 - week.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            Spacer(Modifier.size(16.dp))
        }
    }
}

@Composable
private fun DayCell(
    hijri: Int,
    civil: Int,
    today: Boolean,
    hasEvents: Boolean,
    label: String,
    locale: java.util.Locale,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val content = if (today) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
    val todayLabel = stringResource(R.string.today)
    Column(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .background(if (today) MaterialTheme.colorScheme.primary else Color.Transparent, RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 3.dp)
            .semantics {
                contentDescription = if (today) "$label, $todayLabel" else label
                selected = today
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(Formats.number(hijri, locale), style = MaterialTheme.typography.bodyLarge, color = content)
        Text(Formats.number(civil, locale), style = MaterialTheme.typography.labelSmall, color = content)
        Box(Modifier.size(4.dp).background(if (hasEvents) content else Color.Transparent, CircleShape))
    }
}

package com.aljaroudi.muntathir.ui.calendar

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.ArrowDropDown
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.EditCalendar
import androidx.compose.material.icons.outlined.Today
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.CalendarEventDay
import com.aljaroudi.muntathir.core.calendar.CalendarMonthSection
import com.aljaroudi.muntathir.core.calendar.CalendarTargets
import com.aljaroudi.muntathir.core.calendar.CalendarYear
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.IslamicEvent
import com.aljaroudi.muntathir.core.calendar.MonthCorrection
import com.aljaroudi.muntathir.core.figures.FigureLibrary
import com.aljaroudi.muntathir.data.FigureStore
import com.aljaroudi.muntathir.data.library
import com.aljaroudi.muntathir.data.minutes
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.FigurePickerRoute
import com.aljaroudi.muntathir.ui.navigation.FigureProfileRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.Locale
import javax.inject.Inject

/** What the calendar screens read. Recomputed when settings, the feed or the minute change. */
data class CalendarUi(
    val now: Instant,
    val engine: CalendarEngine,
    val confirmations: List<MonthCorrection>,
    val library: EventLibrary,
    /** Linked figures for observance rows, once loaded. */
    val figures: FigureLibrary? = null,
) {
    val today: LocalDate get() = engine.localDate(now)
    val currentMonth: HijriMonth get() = engine.resolve(now).month
}

@HiltViewModel
class CalendarViewModel
    @Inject
    constructor(
        model: AppModel,
        library: EventLibrary,
        clock: Clock,
        figures: FigureStore,
    ) : ViewModel() {
        val state: StateFlow<CalendarUi> =
            combine(model.state, clock.minutes(), figures.state) { app, now, load ->
                CalendarUi(now, app.engine, app.confirmations.map { it.correction }, library, load.library)
            }.stateIn(
                viewModelScope,
                SharingStarted.WhileSubscribed(5_000),
                model.state.value.let { app ->
                    CalendarUi(
                        clock.instant(),
                        app.engine,
                        app.confirmations.map { it.correction },
                        library,
                        figures.state.value.library,
                    )
                },
            )
    }

/** Swift `CalendarScreen`: a Hijri year of observances with a jump-to-date month grid. */
@Composable
fun CalendarScreen(
    viewModel: CalendarViewModel,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    open: (Route) -> Unit = {},
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    CalendarContent(state, onBack, modifier, open)
}

@Composable
fun CalendarContent(
    state: CalendarUi,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    open: (Route) -> Unit = {},
) {
    val locale = currentLocale()
    val current = state.currentMonth
    var year by rememberSaveable { mutableIntStateOf(current.year) }
    var pickerMonth by rememberSaveable { mutableStateOf<Int?>(null) } // HijriMonth.index
    var pendingTarget by rememberSaveable { mutableStateOf<String?>(null) }
    var todayRequests by remember { mutableIntStateOf(0) }
    val sections =
        remember(year, state.engine, state.today, state.confirmations) {
            CalendarYear.sections(year, state.now, state.engine, state.library, state.confirmations)
        }
    val nextEvent = remember(state.engine, state.today) { state.library.nextEventDate(state.today, state.engine) }
    val keys = remember(sections) { itemKeys(sections) }

    ScreenScaffold(
        stringResource(R.string.calendar),
        modifier,
        onBack,
        actions = {
            IconButton(onClick = {
                year = current.year
                todayRequests++
            }, Modifier.testTag("calendar-today")) { Icon(Icons.Outlined.Today, stringResource(R.string.today)) }
            IconButton(
                onClick = {
                    pickerMonth = (if (year == current.year) current else HijriMonth(year, 1)).index
                },
                Modifier.testTag(
                    "calendar-jump",
                ),
            ) { Icon(Icons.Outlined.EditCalendar, stringResource(R.string.jump_to_date)) }
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            key(year) {
                val list = rememberLazyListState()
                val scope = rememberCoroutineScope()
                val scrollTo: (String) -> Unit = { id ->
                    keys.indexOf(id).takeIf { it >= 0 }?.let { scope.launch { list.animateScrollToItem(it) } }
                }
                YearBar(
                    year,
                    sections.map { it.month },
                    locale,
                    onYear = { year = it },
                    onMonth = { scrollTo(CalendarTargets.monthID(it)) },
                )
                // Swift scrolls the current year to its next event (or month) on open and on Today.
                LaunchedEffect(todayRequests) {
                    if (pendingTarget == null && year == current.year) {
                        val target = CalendarTargets.initialTarget(year, current, nextEvent?.let(state.engine::resolve))
                        keys.indexOf(target).takeIf { it >= 0 }?.let { list.scrollToItem(it) }
                    }
                }
                // A day picked in the jump sheet.
                LaunchedEffect(pendingTarget) {
                    val target = pendingTarget ?: return@LaunchedEffect
                    keys.indexOf(target).takeIf { it >= 0 }?.let { list.animateScrollToItem(it) }
                    pendingTarget = null
                }
                MonthList(sections, state, nextEvent, list, locale, onMonth = { pickerMonth = it.index }, open = open)
            }
        }
    }

    pickerMonth?.let { index ->
        JumpToDateSheet(
            month = HijriMonth(index / 12, index % 12 + 1),
            state = state,
            onMonth = { pickerMonth = it.index },
            onDismiss = { pickerMonth = null },
            onDay = { day ->
                pickerMonth = null
                year = day.month.year
                val eventDays =
                    state.library.events
                        .filter { it.month == day.month.month }
                        .map { it.day }
                pendingTarget = CalendarTargets.jumpTarget(day, eventDays, state.engine)
            },
        )
    }
}

/** Header and row keys in list order, so scroll targets map to indices. */
private fun itemKeys(sections: List<CalendarMonthSection>): List<String> =
    sections.flatMap { section ->
        listOf(section.id) + section.days.map { it.id }.ifEmpty { listOf("${section.id}-empty") }
    }

@Composable
private fun YearBar(
    year: Int,
    months: List<HijriMonth>,
    locale: Locale,
    onYear: (Int) -> Unit,
    onMonth: (HijriMonth) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    Row(
        Modifier.widthIn(max = 760.dp).fillMaxWidth().padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = { onYear(year - 1) }, enabled = year > CalendarYear.FIRST) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, stringResource(R.string.previous_year))
        }
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.Center) {
            TextButton(onClick = { menu = true }, Modifier.testTag("calendar-year")) {
                Text(
                    stringResource(R.string.x_ah_ef68a7, Formats.number(year, locale)),
                    style = MaterialTheme.typography.titleSmall,
                )
                Icon(Icons.Outlined.ArrowDropDown, contentDescription = null)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                months.forEach { month ->
                    DropdownMenuItem(
                        text = { Text(Formats.hijriMonth(month.month, locale)) },
                        onClick = {
                            menu = false
                            onMonth(month)
                        },
                        modifier = Modifier.testTag("calendar-jump-month-${month.month}"),
                    )
                }
            }
        }
        IconButton(onClick = { onYear(year + 1) }, enabled = year < CalendarYear.LAST) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, stringResource(R.string.next_year))
        }
    }
}

@Composable
private fun MonthList(
    sections: List<CalendarMonthSection>,
    state: CalendarUi,
    nextEvent: LocalDate?,
    list: LazyListState,
    locale: Locale,
    onMonth: (HijriMonth) -> Unit,
    open: (Route) -> Unit,
) {
    LazyColumn(state = list, modifier = Modifier.widthIn(max = 760.dp).fillMaxSize()) {
        sections.forEach { section ->
            stickyHeader(key = section.id) {
                Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clickable { onMonth(section.month) }
                            .padding(horizontal = 20.dp, vertical = 12.dp)
                            .testTag(section.id)
                            .semantics { heading() },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        val secondary = MaterialTheme.colorScheme.onSurfaceVariant
                        Text(
                            Formats.hijriMonth(section.month.month, locale),
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.weight(1f),
                        )
                        if (section.expected) {
                            Text(
                                stringResource(R.string.expected),
                                style = MaterialTheme.typography.labelMedium,
                                color = secondary,
                            )
                        }
                        Icon(Icons.Outlined.CalendarMonth, contentDescription = null, tint = secondary)
                    }
                }
            }
            if (section.days.isEmpty()) {
                item(key = "${section.id}-empty") {
                    Text(
                        stringResource(R.string.no_events),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                    )
                }
            }
            section.days.forEachIndexed { index, day ->
                item(key = day.id) {
                    if (index > 0) HorizontalDivider(Modifier.padding(horizontal = 20.dp))
                    EventDayRow(
                        day,
                        state,
                        isNext = day.date == nextEvent,
                        expected = section.expected,
                        locale = locale,
                        open = open,
                    )
                }
            }
        }
    }
}

@Composable
private fun EventDayRow(
    day: CalendarEventDay,
    state: CalendarUi,
    isNext: Boolean,
    expected: Boolean,
    locale: Locale,
    open: (Route) -> Unit,
) {
    val civil = Formats.date(day.date, "EEEdMMM", locale)
    val colors = MaterialTheme.colorScheme
    val background = if (isNext) colors.primary.copy(alpha = 0.06f) else colors.surface
    Column(
        Modifier
            .fillMaxWidth()
            .background(background)
            .padding(horizontal = 20.dp, vertical = 16.dp)
            .testTag(day.id),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        FlowRow(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            itemVerticalAlignment = Alignment.Bottom,
        ) {
            Text(
                "${Formats.number(day.day.day, locale)} ${Formats.hijriMonth(day.day.month.month, locale)}",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                if (expected) stringResource(R.string.expected_x, civil) else civil,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (isNext) {
            val days = ChronoUnit.DAYS.between(state.today, day.date).toInt()
            val countdown = Formats.inDays(days, locale)
            Text(
                when {
                    days == 0 -> stringResource(R.string.today)
                    expected -> stringResource(R.string.expected_x, countdown)
                    else -> countdown
                },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.testTag("calendar-countdown"),
            )
        }
        day.events.forEach { EventTitle(it, locale, figures = state.figures, open = open) }
    }
}

/**
 * Swift `FigureObservanceRow`: an observance linked to one published figure opens its profile, one linked to
 * several opens a picker, otherwise it's plain text.
 */
@Composable
fun EventTitle(
    event: IslamicEvent,
    locale: Locale,
    modifier: Modifier = Modifier,
    figures: FigureLibrary? = null,
    open: (Route) -> Unit = {},
) {
    val ids =
        remember(event, figures) {
            figures
                ?.let { library ->
                    event.figureIDs.filter { it in library.byID }
                }.orEmpty()
        }
    val target =
        when {
            ids.size == 1 -> FigureProfileRoute(ids.single())
            ids.size > 1 -> FigurePickerRoute(ids)
            else -> null
        }
    val link = target?.let { Modifier.clickable(role = Role.Button) { open(it) } } ?: Modifier
    Column(modifier.then(link).testTag("observance-${event.id}")) {
        Text(event.title(locale), style = MaterialTheme.typography.bodyLarge)
        event.year?.let {
            Text(
                stringResource(R.string.x_ah_ef68a7, Formats.number(it, locale)),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

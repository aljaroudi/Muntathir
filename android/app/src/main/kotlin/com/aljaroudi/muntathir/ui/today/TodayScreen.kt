package com.aljaroudi.muntathir.ui.today

import android.app.Activity
import android.content.ContextWrapper
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.calendar.EventTiming
import com.aljaroudi.muntathir.core.calendar.UpcomingEvent
import com.aljaroudi.muntathir.core.prayer.PrayerMoment
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.components.icon
import com.aljaroudi.muntathir.ui.components.rememberNotificationPermission
import com.aljaroudi.muntathir.ui.components.title
import java.time.Duration
import java.util.Locale

/** Callbacks from Today; the shell routes them. */
class TodayActions(
    val onChooseLocation: () -> Unit = {},
    val onOpenCalendar: () -> Unit = {},
    val onAlert: (PrayerName, Boolean) -> Unit = { _, _ -> },
    val onHide: (PrayerName) -> Unit = {},
    val onShare: (TodayUi) -> Unit = {},
)

@Composable
fun TodayScreen(
    viewModel: TodayViewModel,
    onChooseLocation: () -> Unit,
    onOpenCalendar: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var pending by remember { mutableStateOf<PrayerName?>(null) }
    val requestPermission =
        rememberNotificationPermission { allowed ->
            pending?.let { viewModel.setAlert(it, true, allowed) }
            pending = null
        }
    TodayContent(
        state,
        TodayActions(
            onChooseLocation = onChooseLocation,
            onOpenCalendar = onOpenCalendar,
            onAlert = { prayer, enabled ->
                if (enabled) {
                    pending = prayer
                    requestPermission()
                } else {
                    viewModel.setAlert(prayer, false, true)
                }
            },
            onHide = viewModel::hide,
        ),
        modifier,
    )
}

/** Swift `TodayView`: Hijri title over the sky, prayer times, daily ayah and the next observance. */
@Composable
fun TodayContent(
    state: TodayUi,
    actions: TodayActions,
    modifier: Modifier = Modifier,
) {
    val locale = currentLocale()
    val title = "${Formats.number(state.day.day, locale)} ${Formats.hijriMonth(state.day.month.month, locale)}"
    val sun = state.sun
    LightStatusBarIcons(sun != null)
    Box(modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerLow)) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val compactHeight = maxHeight < 480.dp
            val wide = maxWidth >= 720.dp
            val band = if (compactHeight) 96.dp else 148.dp
            // Large fonts scale non-linearly (a 40 sp line grows less than a 32 sp font), which clipped Arabic
            // descenders, so the title's line height is relative to its font. Its slot grows with it and the
            // sky's horizon follows. At 100% this is the style's 32/40 sp in a 56 dp slot.
            val headline = MaterialTheme.typography.headlineLarge
            val titleStyle = headline.copy(lineHeight = (headline.lineHeight.value / headline.fontSize.value).em)
            val titleLine = with(LocalDensity.current) { headline.fontSize.toDp() } * titleStyle.lineHeight.value
            val titleHeight = maxOf(56.dp, titleLine + 16.dp)
            if (sun != null) {
                val statusBar = with(LocalDensity.current) { WindowInsets.statusBars.getTop(this).toDp() }
                TodaySky(sun, horizonY = statusBar + titleHeight + band - 12.dp)
            }
            Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
                Text(
                    title,
                    style =
                        titleStyle.copy(
                            fontWeight = FontWeight.Bold,
                            shadow =
                                if (sun !=
                                    null
                                ) {
                                    Shadow(Color.Black.copy(alpha = 0.45f), blurRadius = 8f)
                                } else {
                                    null
                                },
                        ),
                    color = if (sun != null) Color.White else MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    modifier =
                        Modifier
                            .height(titleHeight)
                            .padding(horizontal = 16.dp, vertical = 6.dp)
                            .semantics { heading() }
                            .testTag("hijri-date"),
                )
                if (sun != null) {
                    SolarArc(
                        sun,
                        state.moon,
                        state.markers,
                        Modifier
                            .fillMaxWidth()
                            .widthIn(max = 760.dp)
                            .height(band)
                            .align(Alignment.CenterHorizontally),
                    )
                }
                Column(
                    Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    val onSky = sun != null
                    if (wide) {
                        Row(Modifier.widthIn(max = 1120.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                            PrayerCard(state, onSky, locale, actions, Modifier.weight(1f))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                                SecondaryCards(state, onSky, locale, actions)
                            }
                        }
                    } else {
                        Column(Modifier.widthIn(max = 760.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                            PrayerCard(state, onSky, locale, actions)
                            SecondaryCards(state, onSky, locale, actions)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SecondaryCards(
    state: TodayUi,
    onSky: Boolean,
    locale: Locale,
    actions: TodayActions,
) {
    state.ayah?.let { DailyAyahCard(it, state.surahNames, onSky, locale) }
    state.event?.let { EventCard(it, onSky, locale, actions.onOpenCalendar) }
}

/** Light status-bar icons over the sky (Swift `.toolbarColorScheme(.dark)`), restored when Today leaves. */
@Composable
private fun LightStatusBarIcons(enabled: Boolean) {
    val view = LocalView.current
    if (view.isInEditMode || !enabled) return
    DisposableEffect(view) {
        val activity =
            generateSequence(view.context) {
                (it as? ContextWrapper)?.baseContext
            }.filterIsInstance<Activity>().firstOrNull()
        val controller = activity?.let { WindowCompat.getInsetsController(it.window, view) }
        val previous = controller?.isAppearanceLightStatusBars
        controller?.isAppearanceLightStatusBars = false
        onDispose { if (previous != null) controller.isAppearanceLightStatusBars = previous }
    }
}

/** On the sky, cards are the surface at 86% so the sky shows through (Swift `SkyCardSurface`). */
@Composable
fun skyCardColor(onSky: Boolean): Color = MaterialTheme.colorScheme.surface.copy(alpha = if (onSky) 0.86f else 1f)

/** A translucent container can't be matched to a content colour automatically, so set it. */
@Composable
fun skyCardColors(onSky: Boolean) =
    CardDefaults.cardColors(containerColor = skyCardColor(onSky), contentColor = MaterialTheme.colorScheme.onSurface)

@Composable
private fun PrayerCard(
    state: TodayUi,
    onSky: Boolean,
    locale: Locale,
    actions: TodayActions,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = skyCardColors(onSky),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                Formats.date(state.engine.localDate(state.now), "EEEMMMd", locale),
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().semantics { heading() }.testTag("gregorian-date"),
            )
            when {
                state.location == null -> {
                    Unavailable(stringResource(R.string.set_a_location_to_view_prayer_times), actions.onChooseLocation)
                }

                state.prayers.isEmpty() -> {
                    Unavailable(
                        stringResource(R.string.this_location_needs_to_be_updated_to_calculate_p),
                        actions.onChooseLocation,
                    )
                }

                else -> {
                    HorizontalDivider()
                    state.prayers.forEachIndexed { index, prayer ->
                        if (index > 0) HorizontalDivider()
                        PrayerRow(prayer, state, locale, actions)
                    }
                }
            }
        }
    }
}

@Composable
private fun Unavailable(
    message: String,
    onChooseLocation: () -> Unit,
) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Outlined.Schedule, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(stringResource(R.string.prayer_times_unavailable_2f8f47), style = MaterialTheme.typography.titleMedium)
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        FilledTonalButton(onClick = onChooseLocation, Modifier.testTag("choose-location")) {
            Text(stringResource(R.string.choose_a_location))
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PrayerRow(
    prayer: PrayerMoment,
    state: TodayUi,
    locale: Locale,
    actions: TodayActions,
) {
    val isNext = prayer.name == state.next?.name && prayer.time == state.next.time
    val color = if (isNext) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
    val enabled = prayer.name in state.enabledPrayers
    var menu by remember { mutableStateOf(false) }
    val alertLabel = stringResource(if (enabled) R.string.mute else R.string.alert)
    val hideLabel = stringResource(R.string.hide)
    val zone = state.location?.zone ?: state.engine.zone
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .combinedClickable(onClick = {}, onLongClick = { menu = true }, onLongClickLabel = alertLabel)
                .padding(vertical = 5.dp)
                .semantics(mergeDescendants = true) {
                    customActions =
                        listOfNotNull(
                            CustomAccessibilityAction(alertLabel) {
                                actions.onAlert(prayer.name, !enabled)
                                true
                            },
                            if (prayer.name.isRequired) {
                                null
                            } else {
                                CustomAccessibilityAction(hideLabel) {
                                    actions.onHide(prayer.name)
                                    true
                                }
                            },
                        )
                }.testTag("prayer-${prayer.name.id}"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(prayer.name.icon, contentDescription = null, tint = color)
            Text(
                stringResource(prayer.name.title),
                color = color,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f),
            )
            if (isNext) {
                Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)) {
                    Text(
                        Formats.duration(Duration.between(state.now, prayer.time), locale),
                        style = MaterialTheme.typography.labelMedium,
                        color = color,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp).testTag("prayer-countdown"),
                    )
                }
            }
            PrayerTime(Formats.clockTime(prayer.time, zone, locale), color)
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(alertLabel) },
                leadingIcon = {
                    Icon(
                        if (enabled) Icons.Outlined.NotificationsOff else Icons.Outlined.Notifications,
                        null,
                    )
                },
                onClick = {
                    menu = false
                    actions.onAlert(prayer.name, !enabled)
                },
            )
            if (!prayer.name.isRequired) {
                DropdownMenuItem(
                    text = { Text(hideLabel) },
                    leadingIcon = { Icon(Icons.Outlined.VisibilityOff, null) },
                    onClick = {
                        menu = false
                        actions.onHide(prayer.name)
                    },
                    modifier = Modifier.testTag("hide-${prayer.name.id}"),
                )
            }
        }
    }
}

/** Tabular digits; a 3-digit time gets an invisible leading digit so columns align (Swift `prayerTime`). */
@Composable
private fun PrayerTime(
    time: String,
    color: Color,
) {
    val digits = time.filter(Char::isDigit)
    val text =
        buildAnnotatedString {
            if (digits.length == 3) withStyle(SpanStyle(color = Color.Transparent)) { append(digits.first()) }
            append(time)
        }
    Text(
        text,
        color = color,
        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum"),
        // The alignment digit is only visual; TalkBack must read the real time ("4:31", not "44:31").
        modifier = Modifier.clearAndSetSemantics { contentDescription = time },
    )
}

/** Swift `UpcomingEventCard`: the next observance; tapping opens the Calendar. */
@Composable
private fun EventCard(
    event: UpcomingEvent,
    onSky: Boolean,
    locale: Locale,
    onOpen: () -> Unit,
) {
    val timing =
        when (val timing = event.timing) {
            EventTiming.Today -> Formats.relativeDay(0, locale)
            EventTiming.Tonight -> stringResource(R.string.tonight)
            EventTiming.Tomorrow -> Formats.relativeDay(1, locale)
            is EventTiming.Countdown -> Formats.duration(timing.duration, locale, allowDays = true)
        }
    Card(
        onClick = onOpen,
        modifier = Modifier.fillMaxWidth().testTag("upcoming-event"),
        shape = RoundedCornerShape(24.dp),
        colors = skyCardColors(onSky),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Outlined.CalendarMonth, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text(
                    timing,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.testTag("upcoming-event-timing"),
                )
            }
            Text(
                event.events.joinToString("\n") { it.title(locale) },
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 3,
                modifier = Modifier.testTag("upcoming-event-names"),
            )
        }
    }
}

package com.aljaroudi.muntathir.ui.today

import android.app.Activity
import android.content.ContextWrapper
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.animateScrollBy
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ViewList
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.ViewWeek
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
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
import androidx.compose.ui.text.style.TextOverflow
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
import kotlinx.coroutines.flow.first
import java.time.Duration
import java.util.Locale

/** Callbacks from Today; the shell routes them. */
class TodayActions(
    val onChooseLocation: () -> Unit = {},
    val onOpenCalendar: () -> Unit = {},
    val onAlert: (PrayerName, Boolean) -> Unit = { _, _ -> },
    val onHide: (PrayerName) -> Unit = {},
    val onToggleLayout: () -> Unit = {},
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
            onToggleLayout = { viewModel.toggleLayout() },
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
                        mirrored = (state.location?.latitude ?: 0.0) < 0,
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
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    Formats.date(state.engine.localDate(state.now), "EEEMMMd", locale),
                    style = MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center,
                    // Clear of the layout button so the date stays centred in the card.
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 40.dp)
                            .semantics { heading() }
                            .testTag("gregorian-date"),
                )
                if (state.location != null && state.prayers.isNotEmpty()) {
                    IconButton(
                        onClick = actions.onToggleLayout,
                        modifier = Modifier.align(Alignment.CenterEnd).size(40.dp).testTag("prayer-layout"),
                    ) {
                        val horizontal = state.horizontalPrayerTimes
                        Icon(
                            if (horizontal) Icons.AutoMirrored.Outlined.ViewList else Icons.Outlined.ViewWeek,
                            contentDescription =
                                stringResource(
                                    if (horizontal) R.string.vertical_layout else R.string.horizontal_layout,
                                ),
                        )
                    }
                }
            }
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

                state.horizontalPrayerTimes -> {
                    HorizontalDivider()
                    HorizontalPrayerTimes(state, locale, actions)
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

private fun TodayUi.isNext(prayer: PrayerMoment) = prayer.name == next?.name && prayer.time == next.time

@Composable
private fun PrayerRow(
    prayer: PrayerMoment,
    state: TodayUi,
    locale: Locale,
    actions: TodayActions,
) {
    val isNext = state.isNext(prayer)
    val color = if (isNext) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
    val zone = state.location?.zone ?: state.engine.zone
    PrayerActions(prayer, state, actions) { interaction ->
        Row(
            Modifier
                .fillMaxWidth()
                .then(interaction)
                .padding(vertical = 5.dp),
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
    }
}

/** Swift's horizontal layout: equal-width cards in a sideways-scrolling row that keeps the next prayer in view. */
@Composable
private fun HorizontalPrayerTimes(
    state: TodayUi,
    locale: Locale,
    actions: TodayActions,
) {
    val listState = rememberLazyListState()
    val nextIndex = state.prayers.indexOfFirst(state::isNext)
    LaunchedEffect(nextIndex) {
        if (nextIndex < 0) return@LaunchedEffect
        // Wait for the first layout so the visibility check below sees real items.
        val info = snapshotFlow { listState.layoutInfo }.first { it.visibleItemsInfo.isNotEmpty() }
        val item = info.visibleItemsInfo.firstOrNull { it.index == nextIndex }
        when {
            item == null || item.offset < info.viewportStartOffset -> {
                listState.animateScrollToItem(nextIndex)
            }

            // Cut off at the end: scroll only far enough to bring its trailing edge into view.
            item.offset + item.size > info.viewportEndOffset -> {
                listState.animateScrollBy((item.offset + item.size - info.viewportEndOffset).toFloat())
            }
        }
    }
    LazyRow(
        state = listState,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth().testTag("prayer-row"),
    ) {
        items(state.prayers, key = { it.name.id }) { prayer -> PrayerTile(prayer, state, locale, actions) }
    }
}

/** One card in [HorizontalPrayerTimes]; the next prayer gets a solid fill so it's easy to find. */
@Composable
private fun PrayerTile(
    prayer: PrayerMoment,
    state: TodayUi,
    locale: Locale,
    actions: TodayActions,
) {
    val isNext = state.isNext(prayer)
    val colors = MaterialTheme.colorScheme
    val color = if (isNext) colors.onPrimary else colors.onSurface
    val zone = state.location?.zone ?: state.engine.zone
    PrayerActions(prayer, state, actions) { interaction ->
        Column(
            Modifier
                .width(84.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(if (isNext) colors.primary else colors.surfaceVariant)
                .then(interaction)
                .padding(horizontal = 4.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(prayer.name.icon, contentDescription = null, tint = color)
            Text(
                stringResource(prayer.name.title),
                color = color,
                style =
                    MaterialTheme.typography.labelMedium.copy(
                        fontWeight = if (isNext) FontWeight.SemiBold else null,
                    ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            PrayerTime(
                Formats.clockTime(prayer.time, zone, locale),
                color,
                if (isNext) FontWeight.SemiBold else FontWeight.Medium,
                padded = false,
            )
            // Other cards reserve the countdown's height so every card matches.
            Text(
                if (isNext) Formats.duration(Duration.between(state.now, prayer.time), locale) else " ",
                style = MaterialTheme.typography.labelSmall,
                color = color,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier =
                    Modifier
                        .alpha(if (isNext) 1f else 0f)
                        .background(Color.White.copy(alpha = 0.2f), RoundedCornerShape(50))
                        .padding(horizontal = 6.dp, vertical = 3.dp)
                        .then(if (isNext) Modifier.testTag("prayer-countdown") else Modifier.clearAndSetSemantics {}),
            )
        }
    }
}

/**
 * Long-press menu and TalkBack actions (Alert/Mute, Hide) shared by the list rows and cards. [content] applies
 * the given modifier to its container.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PrayerActions(
    prayer: PrayerMoment,
    state: TodayUi,
    actions: TodayActions,
    content: @Composable (Modifier) -> Unit,
) {
    val enabled = prayer.name in state.enabledPrayers
    var menu by remember { mutableStateOf(false) }
    val alertLabel = stringResource(if (enabled) R.string.mute else R.string.alert)
    val hideLabel = stringResource(R.string.hide)
    Box {
        content(
            Modifier
                .combinedClickable(onClick = {}, onLongClick = { menu = true }, onLongClickLabel = alertLabel)
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
        )
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

/**
 * Tabular digits; when [padded], a 3-digit time gets an invisible leading digit so list columns align (Swift
 * `prayerTime`). Centred cards don't need it.
 */
@Composable
private fun PrayerTime(
    time: String,
    color: Color,
    weight: FontWeight = FontWeight.Medium,
    padded: Boolean = true,
) {
    val digits = time.filter(Char::isDigit)
    val text =
        buildAnnotatedString {
            if (padded && digits.length == 3) withStyle(SpanStyle(color = Color.Transparent)) { append(digits.first()) }
            append(time)
        }
    Text(
        text,
        color = color,
        style = MaterialTheme.typography.titleLarge.copy(fontWeight = weight, fontFeatureSettings = "tnum"),
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

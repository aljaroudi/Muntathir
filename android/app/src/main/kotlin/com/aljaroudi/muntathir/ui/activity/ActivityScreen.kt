package com.aljaroudi.muntathir.ui.activity

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.BorderColor
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Toll
import androidx.compose.material.icons.outlined.VolunteerActivism
import androidx.compose.material.icons.outlined.WbTwilight
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.components.plus
import com.aljaroudi.muntathir.ui.components.title
import java.util.Locale
import kotlin.math.roundToInt

/** Swift `ActivityProgressView`: prayers counted by the Rakaat tracker, time in readers and saved items. */
@Composable
fun ActivityScreen(
    onBack: (() -> Unit)?,
    viewModel: ActivityViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val userUnavailable by viewModel.userUnavailable.collectAsStateWithLifecycle()
    ActivityContent(state, userUnavailable, onBack, viewModel::retry, viewModel::reopenUserData)
}

@Composable
fun ActivityContent(
    state: ActivityUiState,
    userUnavailable: Boolean,
    onBack: (() -> Unit)?,
    onRetry: () -> Unit,
    onReopenUserData: () -> Unit,
) {
    val locale = currentLocale()
    // Swift `isAccessibilitySize`: stack cards and list prayers instead of drawing the chart.
    val large = LocalDensity.current.fontScale >= 1.5f
    ScreenScaffold(R.string.activity, Modifier.testTag("progress-screen"), onBack) { padding ->
        Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), contentAlignment = Alignment.TopCenter) {
            Column(
                Modifier.widthIn(max = 700.dp).fillMaxWidth().padding(padding + PaddingValues(16.dp)),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                if (state.failed) {
                    ActivityCard {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Outlined.ErrorOutline, null)
                            Spacer(Modifier.padding(4.dp))
                            Text(stringResource(R.string.unable_to_save_or_load_activity))
                        }
                        TextButton(onClick = onRetry) { Text(stringResource(R.string.try_again)) }
                    }
                }
                PrayerCard(state, large, locale)
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Heading(Icons.Outlined.Schedule, stringResource(R.string.time_in_reader))
                    CardGrid(large, ProgressActivityKind.reading) { kind ->
                        StatCard(
                            stringResource(kind.title),
                            kind.icon,
                            Formats.readDuration(state.reading[kind] ?: 0.0, locale),
                            MaterialTheme.colorScheme.primary,
                            "progress-${kind.id}",
                        )
                    }
                }
                CardGrid(large, listOf(0, 1, 2)) { index ->
                    when (index) {
                        0 -> {
                            StatCard(
                                stringResource(R.string.bookmarks),
                                Icons.Outlined.Bookmark,
                                state.bookmarks?.let { Formats.number(it, locale) } ?: "—",
                                Color(0xFFE8890C),
                                "progress-bookmarks",
                            )
                        }

                        1 -> {
                            StatCard(
                                stringResource(R.string.highlights),
                                Icons.Outlined.BorderColor,
                                state.highlights?.let { Formats.number(it, locale) } ?: "—",
                                Color(0xFF8E5BD0),
                                "progress-highlights",
                            )
                        }

                        else -> {
                            StatCard(
                                stringResource(R.string.beads_counted),
                                Icons.Outlined.Toll,
                                Formats.number(state.beads.roundToInt(), locale),
                                MaterialTheme.colorScheme.primary,
                                "progress-tasbih",
                            )
                        }
                    }
                }
                if (userUnavailable) {
                    TextButton(onClick = onReopenUserData) { Text(stringResource(R.string.try_again)) }
                }
            }
        }
    }
}

@Composable
private fun PrayerCard(
    state: ActivityUiState,
    large: Boolean,
    locale: Locale,
) {
    ActivityCard {
        Heading(Icons.Outlined.WbTwilight, stringResource(R.string.on_time_prayers))
        if (large) {
            state.onTime.forEach { (prayer, count) ->
                Row(
                    Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}.testTag("prayer-total-${prayer.id}"),
                ) {
                    Text(stringResource(prayer.title), Modifier.weight(1f))
                    Text(Formats.number(count, locale), fontWeight = FontWeight.Bold)
                }
            }
        } else {
            PrayerChart(state, locale)
        }
        listOf(
            Triple(state.outsideTime, R.string.recorded_outside_time, Icons.Outlined.RadioButtonUnchecked),
            Triple(state.timingUnavailable, R.string.timing_unavailable, Icons.AutoMirrored.Outlined.HelpOutline),
        ).forEachIndexed { index, (count, label, icon) ->
            if (count > 0) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .semantics(mergeDescendants = true) {}
                        .testTag(if (index == 0) "prayer-outsideTime-count" else "prayer-unavailable-count"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val color = MaterialTheme.colorScheme.onSurfaceVariant
                    Icon(icon, null, Modifier.padding(end = 8.dp), tint = color)
                    Text(
                        stringResource(label),
                        Modifier.weight(1f),
                        style = MaterialTheme.typography.bodySmall,
                        color = color,
                    )
                    Text(Formats.number(count, locale), style = MaterialTheme.typography.bodySmall, color = color)
                }
            }
        }
        if (!state.hasPrayers) {
            Text(
                stringResource(R.string.no_recorded_prayers_yet),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Swift Charts `BarMark`s: one bar per prayer, scaled to the largest count plus one, its value above. */
@Composable
private fun PrayerChart(
    state: ActivityUiState,
    locale: Locale,
) {
    val title = stringResource(R.string.on_time_prayers)
    val names = state.onTime.map { (prayer, _) -> stringResource(prayer.title) }
    val summary =
        state.onTime.zip(names).joinToString(", ") { (total, name) -> "$name: ${Formats.number(total.second, locale)}" }
    val top = maxOf(1, (state.onTime.maxOfOrNull { it.second } ?: 0) + 1)
    Row(
        Modifier
            .fillMaxWidth()
            .height(200.dp)
            .testTag("progress-prayer-chart")
            .clearAndSetSemantics {
                contentDescription = title
                stateDescription = summary
            },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        state.onTime.zip(names).forEach { (total, name) ->
            Column(Modifier.weight(1f).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                Column(
                    Modifier.weight(1f).fillMaxWidth(),
                    verticalArrangement = Arrangement.Bottom,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        Formats.number(total.second, locale),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                    )
                    BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(maxHeight * (total.second.toFloat() / top))
                                .clip(RoundedCornerShape(topStart = 6.dp, topEnd = 6.dp))
                                .background(MaterialTheme.colorScheme.primary),
                        )
                    }
                }
                Text(name, Modifier.padding(top = 4.dp), style = MaterialTheme.typography.labelSmall, maxLines = 1)
            }
        }
    }
}

/** Swift `LazyVGrid(.adaptive(minimum: 150))`, one column at large text sizes. */
@Composable
private fun <T> CardGrid(
    large: Boolean,
    items: List<T>,
    content: @Composable (T) -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val columns = if (large) 1 else maxOf(1, ((maxWidth + 12.dp) / (150.dp + 12.dp)).toInt())
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            items.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { Box(Modifier.weight(1f)) { content(it) } }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun StatCard(
    title: String,
    icon: ImageVector,
    value: String,
    tint: Color,
    tag: String,
) {
    ActivityCard(
        Modifier.testTag(tag).clearAndSetSemantics {
            contentDescription = title
            stateDescription = value
        },
    ) {
        Icon(icon, null, tint = tint)
        Text(value, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Heading(
    icon: ImageVector,
    text: String,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.padding(end = 8.dp))
        Text(text, style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun ActivityCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
    ) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

private val ProgressActivityKind.title: Int
    get() =
        when (this) {
            ProgressActivityKind.QuranReading -> R.string.holy_quran
            ProgressActivityKind.HadithReading -> R.string.hadith
            ProgressActivityKind.SupplicationReading -> R.string.supplications
            ProgressActivityKind.Tasbih -> R.string.tasbih
        }

private val ProgressActivityKind.icon: ImageVector
    get() =
        when (this) {
            ProgressActivityKind.QuranReading -> Icons.AutoMirrored.Outlined.MenuBook
            ProgressActivityKind.HadithReading -> Icons.Outlined.Book
            ProgressActivityKind.SupplicationReading -> Icons.Outlined.VolunteerActivism
            ProgressActivityKind.Tasbih -> Icons.Outlined.Toll
        }

/** Swift raw values, used in test tags. */
private val ProgressActivityKind.id: String
    get() =
        when (this) {
            ProgressActivityKind.QuranReading -> "quranReading"
            ProgressActivityKind.HadithReading -> "hadithReading"
            ProgressActivityKind.SupplicationReading -> "supplicationReading"
            ProgressActivityKind.Tasbih -> "tasbih"
        }

package com.aljaroudi.muntathir.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.ReadingPreferences
import com.aljaroudi.muntathir.core.highlight.HighlightColor
import com.aljaroudi.muntathir.core.highlight.HighlightPalette
import com.aljaroudi.muntathir.core.highlight.serialName
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.reader.HighlightSwatch
import com.aljaroudi.muntathir.ui.reader.title
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ReadingSettingsViewModel
    @Inject
    constructor(
        private val settings: ReadingSettings,
    ) : ViewModel() {
        val state: StateFlow<ReadingPreferences> = settings.state

        fun update(transform: (ReadingPreferences) -> ReadingPreferences) =
            viewModelScope.launch { settings.update(transform) }
    }

/** Settings row for [HighlightPaletteScreen]. */
@Composable
fun HighlightColorsRow(onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(stringResource(R.string.highlight_colors)) },
        leadingContent = { Icon(Icons.Outlined.Palette, null) },
        modifier = Modifier.clickable(onClick = onClick).testTag("settings-highlight-colors"),
    )
}

/**
 * Swift `HighlightPaletteSettings`: how many colors the picker shows (3–12) and their order. Move buttons replace
 * drag to reorder, as in Tabs.
 */
@Composable
fun HighlightPaletteScreen(
    viewModel: ReadingSettingsViewModel,
    onBack: (() -> Unit)?,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val locale = currentLocale()
    val order = HighlightPalette.colors(state.highlightColorOrder)
    val count = state.highlightColorCount.coerceIn(MIN_COLORS, order.size)

    fun move(
        index: Int,
        offset: Int,
    ) {
        val moved = order.toMutableList().apply { add(index + offset, removeAt(index)) }
        viewModel.update { it.copy(highlightColorOrder = HighlightPalette.order(moved)) }
    }
    ScreenScaffold(stringResource(R.string.highlight_colors), onBack = onBack) { padding ->
        LazyColumn(contentPadding = padding) {
            item(key = "count") {
                val value = Formats.number(count, locale)
                val title = stringResource(R.string.colors_shown)
                ListItem(
                    headlineContent = { Text(title) },
                    trailingContent = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            IconButton(
                                onClick = { viewModel.update { it.copy(highlightColorCount = count - 1) } },
                                enabled = count > MIN_COLORS,
                            ) { Icon(Icons.Outlined.Remove, stringResource(R.string.decrease_x, title)) }
                            Text(value)
                            IconButton(
                                onClick = { viewModel.update { it.copy(highlightColorCount = count + 1) } },
                                enabled = count < order.size,
                            ) { Icon(Icons.Outlined.Add, stringResource(R.string.increase_x, title)) }
                        }
                    },
                    modifier = Modifier.semantics { stateDescription = value }.testTag("highlight-color-count"),
                )
            }
            itemsIndexed(order, key = { _, color -> color.serialName }) { index, color ->
                PaletteRow(color, index, order.size, ::move)
            }
        }
    }
}

@Composable
private fun PaletteRow(
    color: HighlightColor,
    index: Int,
    size: Int,
    move: (Int, Int) -> Unit,
) {
    val name = stringResource(color.title)
    ListItem(
        headlineContent = { Text(name) },
        leadingContent = { HighlightSwatch(color, selected = false, size = 32) },
        trailingContent = {
            Row {
                IconButton(onClick = { move(index, -1) }, enabled = index > 0) {
                    Icon(Icons.Outlined.ArrowUpward, stringResource(R.string.move_up))
                }
                IconButton(onClick = { move(index, 1) }, enabled = index < size - 1) {
                    Icon(Icons.Outlined.ArrowDownward, stringResource(R.string.move_down))
                }
            }
        },
        modifier = Modifier.testTag("palette-color-${color.serialName}"),
    )
}

private const val MIN_COLORS = 3

/** Swift `ArabicDiacriticsToggle`: a checkable item in each reader's options menu. */
@Composable
fun ArabicDiacriticsMenuItem(settings: ReadingSettingsViewModel = hiltViewModel()) {
    val preferences by settings.state.collectAsStateWithLifecycle()
    DropdownMenuItem(
        text = { Text(stringResource(R.string.show_arabic_diacritics)) },
        leadingIcon = { Checkbox(checked = preferences.showArabicDiacritics, onCheckedChange = null) },
        onClick = { settings.update { it.copy(showArabicDiacritics = !it.showArabicDiacritics) } },
        modifier =
            Modifier.testTag("reading-diacritics").semantics {
                toggleableState = ToggleableState(preferences.showArabicDiacritics)
            },
    )
}

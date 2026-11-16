package com.aljaroudi.muntathir.ui.shell

import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SectionFooter
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.navigation.TodayRoute
import com.aljaroudi.muntathir.ui.navigation.ToolsRoute
import com.aljaroudi.muntathir.ui.navigation.icon
import com.aljaroudi.muntathir.ui.navigation.tabIcon
import com.aljaroudi.muntathir.ui.navigation.title
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class TabsViewModel
    @Inject
    constructor(
        private val model: AppModel,
    ) : ViewModel() {
        val shortcuts: StateFlow<List<AppTool>> =
            model.state
                .map { it.preferences.tabShortcuts }
                .stateIn(
                    viewModelScope,
                    SharingStarted.WhileSubscribed(5_000),
                    model.state.value.preferences.tabShortcuts,
                )

        private fun change(transform: (List<AppTool>) -> List<AppTool>) {
            viewModelScope.launch { model.update { it.copy(tabShortcuts = transform(it.tabShortcuts)) } }
        }

        fun add(tool: AppTool) = change { it + tool }

        fun remove(tool: AppTool) = change { it - tool }

        fun move(
            tool: AppTool,
            by: Int,
        ) = change { list ->
            val from = list.indexOf(tool)
            val to = (from + by).coerceIn(list.indices)
            list.toMutableList().apply { add(to, removeAt(from)) }
        }
    }

/** Swift `TabsSettingsView`: Today and Tools are fixed; up to three tools sit between them. */
@Composable
fun TabsSettingsScreen(
    viewModel: TabsViewModel,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val shortcuts by viewModel.shortcuts.collectAsStateWithLifecycle()
    TabsSettingsContent(shortcuts, viewModel::add, viewModel::remove, viewModel::move, onBack, modifier)
}

@Composable
fun TabsSettingsContent(
    shortcuts: List<AppTool>,
    onAdd: (AppTool) -> Unit,
    onRemove: (AppTool) -> Unit,
    onMove: (AppTool, Int) -> Unit,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val full = shortcuts.size >= AppTool.MAXIMUM_SHORTCUTS
    ScreenScaffold(R.string.tabs, modifier, onBack) { padding ->
        LazyColumn(contentPadding = padding) {
            item { FixedRow(stringResource(R.string.today), TodayRoute.tabIcon) }
            item { SectionHeader(stringResource(R.string.tabs)) }
            items(shortcuts, key = { "tab-${it.id}" }) { tool ->
                val index = shortcuts.indexOf(tool)
                ListItem(
                    modifier = Modifier.testTag("tab-${tool.testTag}"),
                    headlineContent = { Text(stringResource(tool.title)) },
                    leadingContent = {
                        IconButton(onClick = { onRemove(tool) }) {
                            Icon(
                                Icons.Filled.RemoveCircle,
                                stringResource(R.string.remove_tab_x, stringResource(tool.title)),
                                tint = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                    trailingContent = {
                        androidx.compose.foundation.layout.Row {
                            IconButton(onClick = { onMove(tool, -1) }, enabled = index > 0) {
                                Icon(Icons.Outlined.KeyboardArrowUp, stringResource(R.string.move_up))
                            }
                            IconButton(onClick = { onMove(tool, 1) }, enabled = index < shortcuts.lastIndex) {
                                Icon(Icons.Outlined.KeyboardArrowDown, stringResource(R.string.move_down))
                            }
                        }
                    },
                )
            }
            item { SectionFooter(stringResource(R.string.choose_up_to_three_tabs_everything_else_stays_in)) }
            item { FixedRow(stringResource(R.string.tools), ToolsRoute.tabIcon) }
            val available = AppTool.entries.filter { it !in shortcuts }
            if (available.isNotEmpty()) item { SectionHeader(stringResource(R.string.available_tabs)) }
            items(available, key = { "available-${it.id}" }) { tool ->
                ListItem(
                    modifier = Modifier.testTag("add-${tool.testTag}"),
                    headlineContent = { Text(stringResource(tool.title)) },
                    leadingContent = {
                        IconButton(onClick = { onAdd(tool) }, enabled = !full) {
                            Icon(Icons.Filled.AddCircle, stringResource(R.string.add_tab_x, stringResource(tool.title)))
                        }
                    },
                    trailingContent = { Icon(tool.icon, contentDescription = null) },
                )
            }
        }
    }
}

@Composable
private fun FixedRow(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
) {
    ListItem(headlineContent = { Text(title) }, leadingContent = { Icon(icon, contentDescription = null) })
}

package com.aljaroudi.muntathir.ui.shell

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.plus
import com.aljaroudi.muntathir.ui.navigation.icon
import com.aljaroudi.muntathir.ui.navigation.title

/** Every tool that isn't already a tab, in the iOS groups, then Settings. */
@Composable
fun ToolsScreen(
    shortcuts: List<AppTool>,
    onOpen: (AppTool) -> Unit,
    onSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val groups = AppTool.groups.map { group -> group.filter { it !in shortcuts } }.filter { it.isNotEmpty() }
    ScreenScaffold(R.string.tools, modifier) { padding ->
        LazyVerticalGrid(
            columns = GridCells.Adaptive(160.dp),
            state = rememberLazyGridState(),
            contentPadding = padding + PaddingValues(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            groups.forEachIndexed { index, group ->
                if (index > 0) item(span = { GridItemSpan(maxLineSpan) }) { Spacer() }
                items(group, key = { it.id }) { tool ->
                    ToolTile(stringResource(tool.title), tool.icon, { onOpen(tool) }, Modifier.testTag(tool.testTag))
                }
            }
            item(span = { GridItemSpan(maxLineSpan) }) { Spacer() }
            item(key = "settings") {
                ToolTile(
                    stringResource(R.string.settings),
                    Icons.Outlined.Settings,
                    onSettings,
                    Modifier.testTag("settings"),
                )
            }
        }
    }
}

@Composable
private fun Spacer() =
    androidx.compose.foundation.layout
        .Spacer(Modifier.size(4.dp))

@Composable
private fun ToolTile(
    title: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    ElevatedCard(onClick = onClick, modifier = modifier.fillMaxWidth().heightIn(min = 96.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Text(title, style = MaterialTheme.typography.titleMedium)
        }
    }
}

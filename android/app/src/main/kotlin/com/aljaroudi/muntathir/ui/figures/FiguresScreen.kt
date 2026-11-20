package com.aljaroudi.muntathir.ui.figures

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.figures.FigureLibrary
import com.aljaroudi.muntathir.data.FigureLoad
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.InlineProgress
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SearchField
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.FigurePickerRoute
import com.aljaroudi.muntathir.ui.navigation.FigureProfileRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import com.aljaroudi.muntathir.ui.quran.recentSearches

/** Swift `FigureBrowser` (list pane): a section per browser group, with search and recent searches. */
@Composable
fun FiguresScreen(
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
    viewModel: FiguresViewModel = hiltViewModel(),
) {
    val load by viewModel.library.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val remote by viewModel.remote.collectAsStateWithLifecycle()
    val recent by viewModel.recent.collectAsStateWithLifecycle()
    var focused by remember { mutableStateOf(false) }
    val locale = currentLocale()
    ScreenScaffold(R.string.figures, onBack = onBack) { padding ->
        FigureGate(load, padding) { library ->
            val sections = remote ?: remember(library, query, locale) { library.browserSections(query, locale) }
            LazyColumn(Modifier.fillMaxSize().testTag("figures-list"), contentPadding = padding) {
                item(key = "search") {
                    SearchField(
                        query = query,
                        onQuery = viewModel::search,
                        onSubmit = viewModel::submit,
                        placeholder = stringResource(R.string.search),
                        onFocusChange = { focused = it },
                    )
                }
                if (focused && query.isBlank()) {
                    recentSearches(recent, {
                        viewModel.search(it)
                        viewModel.submit()
                    }, viewModel::removeRecent, viewModel::clearRecent)
                }
                if (sections.isEmpty()) {
                    item(key = "empty") { EmptyState(stringResource(R.string.no_figures_found)) }
                }
                sections.forEachIndexed { index, section ->
                    // Swift sections have no titles; a divider separates the groups.
                    if (index > 0) {
                        item(key = "divider-${section.id}") { HorizontalDivider(Modifier.padding(vertical = 8.dp)) }
                    }
                    items(section.figures, key = { "figure-${it.id}" }) { figure ->
                        ListItem(
                            headlineContent = { Text(figure.title(locale)) },
                            modifier =
                                Modifier
                                    .clickable {
                                        viewModel.record()
                                        open(FigureProfileRoute(figure.id))
                                    }.testTag("figure-${figure.id}"),
                        )
                    }
                }
            }
        }
    }
}

/** Swift `ObservanceFigurePicker` (detail pane): the figures of one observance. */
@Composable
fun FigurePickerScreen(
    route: FigurePickerRoute,
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
    viewModel: FigureLibraryViewModel = hiltViewModel(),
) {
    val load by viewModel.library.collectAsStateWithLifecycle()
    val locale = currentLocale()
    ScreenScaffold(R.string.figures, onBack = onBack) { padding ->
        FigureGate(load, padding) { library ->
            LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                items(route.ids.mapNotNull { library.byID[it] }, key = { it.id }) { figure ->
                    ListItem(
                        headlineContent = { Text(figure.title(locale)) },
                        modifier =
                            Modifier
                                .clickable { open(FigureProfileRoute(figure.id)) }
                                .testTag("figure-${figure.id}"),
                    )
                }
            }
        }
    }
}

/** A spinner while the library loads, "Figures unavailable" when it can't, else [content]. */
@Composable
internal fun FigureGate(
    load: FigureLoad,
    padding: PaddingValues,
    content: @Composable (FigureLibrary) -> Unit,
) {
    when (load) {
        FigureLoad.Loading -> InlineProgress(Modifier.padding(padding))
        FigureLoad.Failed -> FiguresUnavailable(padding)
        is FigureLoad.Loaded -> content(load.library)
    }
}

@Composable
internal fun FiguresUnavailable(padding: PaddingValues) {
    EmptyState(stringResource(R.string.figures_unavailable), Modifier.padding(padding))
}

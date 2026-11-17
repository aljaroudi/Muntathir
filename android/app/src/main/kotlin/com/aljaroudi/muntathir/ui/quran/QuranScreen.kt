package com.aljaroudi.muntathir.ui.quran

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.quran.QuranCatalog
import com.aljaroudi.muntathir.core.quran.QuranSurah
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SearchField
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.QuranReaderRoute
import java.util.Locale

/** Swift `QuranView`: search, then the surahs. */
@Composable
fun QuranScreen(
    viewModel: QuranViewModel,
    onOpen: (QuranReaderRoute) -> Unit,
    onBack: (() -> Unit)?,
) {
    val catalog by viewModel.catalog.collectAsStateWithLifecycle()
    val search = viewModel.search
    val query by search.query.collectAsStateWithLifecycle()
    val submitted by search.submitted.collectAsStateWithLifecycle()
    val results by search.results.collectAsStateWithLifecycle()
    val smart by search.smart.collectAsStateWithLifecycle()
    val recent by search.recent.collectAsStateWithLifecycle()
    var focused by remember { mutableStateOf(false) }
    ScreenScaffold(stringResource(R.string.holy_quran), onBack = onBack) { padding ->
        LazyColumn(Modifier.fillMaxSize().testTag("quran-list"), contentPadding = padding) {
            item(key = "search") {
                SearchField(
                    query = query,
                    onQuery = search::setQuery,
                    onSubmit = search::submit,
                    placeholder = stringResource(R.string.surah_2_255_or_quran_text),
                    onFocusChange = { focused = it },
                )
            }
            if (focused && query.isBlank()) {
                recentSearches(
                    recent,
                    onSelect = search::search,
                    onRemove = search::removeRecent,
                    onClear = search::clearRecent,
                )
            }
            when (val state = catalog) {
                CatalogState.Loading -> {
                    item { LoadingState(stringResource(R.string.loading_quran)) }
                }

                CatalogState.Failed -> {
                    item {
                        EmptyState(
                            stringResource(R.string.unable_to_load_quran),
                            onAction = viewModel::load,
                        )
                    }
                }

                is CatalogState.Loaded -> {
                    val shown =
                        surahs(state.catalog, query) { route ->
                            search.record()
                            onOpen(route)
                        }
                    quranSearchResults(
                        query = query,
                        submitted = submitted,
                        results = results,
                        smart = smart,
                        smartAvailable = search.smartSearchAvailable,
                        hasSurahs = shown,
                        scoped = false,
                        surahNames = state.catalog.surahs.associate { it.id to it.arabic },
                        onOpen = { ayah ->
                            search.record()
                            onOpen(QuranReaderRoute(ayah.surah, ayah.number, query = submitted.trim()))
                        },
                        onLoadMore = search::loadMore,
                        onRetry = search::retry,
                        onSmartSearch = search::smartSearch,
                    )
                }
            }
        }
    }
}

/** Swift "Surahs" section: every surah, or those matching the live query. Returns whether any are shown. */
fun LazyListScope.surahs(
    catalog: QuranCatalog,
    query: String,
    onOpen: (QuranReaderRoute) -> Unit,
): Boolean {
    val trimmed = query.trim()
    val shown = if (trimmed.isEmpty()) catalog.surahs else catalog.surahs.filter { it.matches(trimmed) }
    if (shown.isEmpty()) return false
    item(key = "surahs-header") { SectionHeader(stringResource(R.string.surahs)) }
    items(shown, key = { "surah-${it.id}" }) { surah ->
        SurahRow(
            surah,
            verses = catalog.counts[surah.id] ?: 0,
            words = catalog.readingWords[surah.id] ?: 0,
            showReadingTime = trimmed.isEmpty(),
            onClick = { onOpen(QuranReaderRoute(surah.id)) },
        )
    }
    return true
}

@Composable
private fun SurahRow(
    surah: QuranSurah,
    verses: Int,
    words: Int,
    showReadingTime: Boolean,
    onClick: () -> Unit,
) {
    val locale = currentLocale()
    ListItem(
        headlineContent = { Text("${Formats.number(surah.id, locale)}. ${surah.title(locale.language)}") },
        supportingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(pluralStringResource(R.plurals.x_verses, verses, verses))
                if (showReadingTime) ReadingTimeHint(words, locale)
            }
        },
        trailingContent =
            if (locale.language != "ar") {
                {
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                        Text(surah.arabic, style = MaterialTheme.typography.titleMedium)
                    }
                }
            } else {
                null
            },
        modifier = Modifier.clickable(onClick = onClick).testTag("quran-surah-${surah.id}"),
    )
}

/** Swift `ReadingTimeHint`: a clock and the estimated reading time. */
@Composable
fun ReadingTimeHint(
    words: Int,
    locale: Locale,
    modifier: Modifier = Modifier,
) {
    val time = Formats.readingTime(words, locale) ?: return
    val label = stringResource(R.string.estimated_reading_time_x, time)
    Row(
        modifier.semantics(mergeDescendants = true) { contentDescription = label }.testTag("reading-time"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(Icons.Outlined.Schedule, null, Modifier.size(14.dp))
        Text(time, style = MaterialTheme.typography.bodySmall)
    }
}

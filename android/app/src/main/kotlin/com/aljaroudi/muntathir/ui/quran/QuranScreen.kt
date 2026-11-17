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
    val query by viewModel.query.collectAsStateWithLifecycle()
    ScreenScaffold(stringResource(R.string.holy_quran), onBack = onBack) { padding ->
        LazyColumn(Modifier.fillMaxSize().testTag("quran-list"), contentPadding = padding) {
            item(key = "search") {
                SearchField(
                    query = query,
                    onQuery = { viewModel.query.value = it },
                    onSubmit = {},
                    placeholder = stringResource(R.string.surah_2_255_or_quran_text),
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
                    surahs(state.catalog, query, onOpen)
                }
            }
        }
    }
}

/** Swift "Surahs" section: every surah, or those matching the live query. */
fun LazyListScope.surahs(
    catalog: QuranCatalog,
    query: String,
    onOpen: (QuranReaderRoute) -> Unit,
) {
    val trimmed = query.trim()
    val shown = if (trimmed.isEmpty()) catalog.surahs else catalog.surahs.filter { it.matches(trimmed) }
    if (shown.isEmpty()) return
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

package com.aljaroudi.muntathir.ui.quran

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.History
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.quran.QuranReference
import com.aljaroudi.muntathir.core.quran.QuranTranslation
import com.aljaroudi.muntathir.core.text.SearchMatch
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.reader.toAnnotatedString
import com.aljaroudi.muntathir.ui.search.SmartSearchState
import com.aljaroudi.muntathir.ui.search.smartSearchSection
import com.aljaroudi.muntathir.ui.theme.QuranFont

/** Swift `SearchHistorySuggestions`: recent searches, each removable, and Clear history. */
fun LazyListScope.recentSearches(
    recent: List<String>,
    onSelect: (String) -> Unit,
    onRemove: (String) -> Unit,
    onClear: () -> Unit,
) {
    if (recent.isEmpty()) return
    item(key = "recent-header") { SectionHeader(stringResource(R.string.recent_searches)) }
    items(recent, key = { "recent-$it" }) { query ->
        ListItem(
            headlineContent = { Text(query, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            leadingContent = { Icon(Icons.Outlined.History, null) },
            trailingContent = {
                IconButton(onClick = { onRemove(query) }, Modifier.testTag("search-history-remove-$query")) {
                    Icon(Icons.Outlined.Close, stringResource(R.string.remove_search))
                }
            },
            modifier = Modifier.clickable { onSelect(query) }.testTag("search-history-$query"),
        )
    }
    item(key = "recent-clear") {
        TextButton(onClick = onClear, Modifier.padding(horizontal = 8.dp).testTag("search-history-clear")) {
            Text(stringResource(R.string.clear_history), color = MaterialTheme.colorScheme.error)
        }
    }
}

/**
 * Swift `QuranSearchContent` below the surahs: verse matches for the submitted query with Load more, then the
 * loading, failure, invalid-reference, smart-search and no-results states.
 */
fun LazyListScope.quranSearchResults(
    query: String,
    submitted: String,
    results: VerseResults,
    smart: SmartSearchState<Ayah>,
    smartAvailable: Boolean,
    hasSurahs: Boolean,
    scoped: Boolean,
    surahNames: Map<Int, String>,
    onOpen: (Ayah) -> Unit,
    onLoadMore: () -> Unit,
    onRetry: () -> Unit,
    onSmartSearch: () -> Unit,
) {
    val live = query.trim()
    val request = submitted.trim()
    val current = live == request && request.isNotEmpty() && results.query == request
    if (results.verses.isNotEmpty() && live == request) {
        verseSection("verses", R.string.verses, results.verses, results.translation, request, surahNames, onOpen)
        if (results.hasMore) {
            item(key = "load-more") {
                TextButton(
                    onClick = onLoadMore,
                    enabled = !results.loading,
                    modifier = Modifier.padding(horizontal = 8.dp).testTag("load-more"),
                ) {
                    Text(stringResource(R.string.load_more))
                }
            }
        }
    }
    when {
        results.loading -> {
            item(key = "loading") { LoadingState(stringResource(R.string.loading_quran)) }
        }

        results.failed -> {
            item(key = "failed") {
                EmptyState(
                    stringResource(R.string.unable_to_load_quran),
                    message = stringResource(R.string.please_try_again),
                    onAction = onRetry,
                )
            }
        }

        results.invalidReference -> {
            item(key = "invalid") {
                EmptyState(
                    stringResource(R.string.invalid_verse_reference),
                    message =
                        stringResource(
                            if (scoped) {
                                R.string.enter_a_valid_verse_number_in_this_chapter
                            } else {
                                R.string.enter_a_chapter_and_verse_such_as_2_255
                            },
                        ),
                )
            }
        }

        current && QuranSearchModel.isMeaningQuery(request) -> {
            val local = results.verses.map { it.id }.toSet()
            smartSearchSection(
                smart,
                smartAvailable,
                results.verses.isNotEmpty() || hasSurahs,
                onSmartSearch,
            ) { found ->
                val verses = found.filter { it.id !in local }
                if (verses.isNotEmpty()) {
                    verseSection(
                        "smart",
                        R.string.smart_search,
                        verses,
                        results.translation,
                        request,
                        surahNames,
                        onOpen,
                    )
                }
            }
        }

        current && results.verses.isEmpty() && !hasSurahs -> {
            item(key = "empty") { NoResults() }
        }
    }
}

private fun LazyListScope.verseSection(
    key: String,
    title: Int,
    verses: List<Ayah>,
    translation: String?,
    query: String,
    surahNames: Map<Int, String>,
    onOpen: (Ayah) -> Unit,
) {
    item(key = "$key-header") { SectionHeader(stringResource(title)) }
    items(verses, key = { "$key-${it.id}" }) { ayah ->
        QuranResultRow(ayah, translation, query, surahNames, onClick = { onOpen(ayah) })
    }
}

@Composable
private fun NoResults() {
    EmptyState(stringResource(R.string.no_results), Modifier.testTag("local-search-empty"))
}

/** Swift `QuranVerseRow` in preview mode: the matching blocks, two lines each, with matches underlined. */
@Composable
private fun QuranResultRow(
    ayah: Ayah,
    translation: String?,
    query: String,
    surahNames: Map<Int, String>,
    onClick: () -> Unit,
) {
    val locale = currentLocale()
    val reference = QuranReference.display(ayah.id, locale.language, surahNames)
    val translated = translation?.let { ayah.translations[it] }
    val blocks =
        listOf(
            SearchMatch.text(ayah.text, query),
            translated?.let { SearchMatch.text(it, query) } ?: StyledText(""),
        )
    val visible = SearchMatch.visibleBlocks(blocks, preferred = if (locale.language == "ar") 0 else 1)
    val label = stringResource(R.string.verse_x, reference)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .widthIn(max = 640.dp)
                .fillMaxWidth()
                .clickable(onClick = onClick)
                .semantics { contentDescription = label }
                .padding(horizontal = 20.dp, vertical = 12.dp)
                .testTag("quran-result-${ayah.id}"),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    reference,
                    style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.weight(1f))
                VerseActions(ayah, translated, reference, Modifier.testTag("verse-actions-${ayah.id}"))
            }
            if (0 in visible) {
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    Text(
                        SearchMatch.preview(blocks[0], compact = true).toAnnotatedString(),
                        fontFamily = QuranFont,
                        fontSize = 22.sp,
                        lineHeight = 38.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Start,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            if (1 in visible && translation != null) {
                val rtl = QuranTranslation.of(translation)?.isRightToLeft == true
                CompositionLocalProvider(
                    LocalLayoutDirection provides if (rtl) LayoutDirection.Rtl else LayoutDirection.Ltr,
                ) {
                    Text(
                        SearchMatch.preview(blocks[1], compact = true).toAnnotatedString(),
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
    }
}

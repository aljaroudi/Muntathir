package com.aljaroudi.muntathir.ui.hadith

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.hadith.Hadith
import com.aljaroudi.muntathir.core.hadith.HadithBookGroup
import com.aljaroudi.muntathir.core.hadith.HadithChapter
import com.aljaroudi.muntathir.core.hadith.HadithCollection
import com.aljaroudi.muntathir.core.hadith.HadithContentsGroup
import com.aljaroudi.muntathir.core.hadith.HadithIntroduction
import com.aljaroudi.muntathir.core.hadith.HadithSearch
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.SearchRelevance
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SearchField
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.HadithBrowseRoute
import com.aljaroudi.muntathir.ui.navigation.HadithDetailRoute
import com.aljaroudi.muntathir.ui.navigation.HadithIntroductionRoute
import com.aljaroudi.muntathir.ui.navigation.HadithRoute
import com.aljaroudi.muntathir.ui.navigation.HadithSavedRoute
import com.aljaroudi.muntathir.ui.quran.recentSearches
import com.aljaroudi.muntathir.ui.search.smartSearchSection
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import java.text.Collator
import kotlin.time.Duration.Companion.milliseconds

/** One list row; keys are Swift's row ids so scroll positions restore across launches. */
private sealed interface BrowseRow {
    val key: String

    data object Saved : BrowseRow {
        override val key = "saved"
    }

    data class Header(
        val title: String,
        override val key: String,
    ) : BrowseRow

    data class Book(
        val book: HadithCollection,
    ) : BrowseRow {
        override val key = "book:${book.id}"
    }

    data class Introduction(
        val introduction: HadithIntroduction,
    ) : BrowseRow {
        override val key = "introduction:${introduction.id}"
    }

    data class Chapter(
        val chapter: HadithChapter,
    ) : BrowseRow {
        override val key = "chapter:${chapter.bookID}:${chapter.index}"
    }

    data class Narration(
        val narration: Hadith,
    ) : BrowseRow {
        override val key = "hadith:" + (narration.source?.key ?: narration.id.toString())
    }
}

/** Swift `HadithView`: the library's books, a book's contents, or narrations, with search. */
@OptIn(FlowPreview::class)
@Composable
fun HadithBrowseScreen(
    viewModel: HadithBrowseViewModel,
    onOpen: (HadithRoute) -> Unit,
    onRestore: (List<HadithRoute>) -> Unit,
    onBack: (() -> Unit)?,
) {
    val route = viewModel.route
    val state by viewModel.state.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val submitted by viewModel.submitted.collectAsStateWithLifecycle()
    val recent by viewModel.recent.collectAsStateWithLifecycle()
    val reading by viewModel.reading.collectAsStateWithLifecycle()
    val restore by viewModel.restore.collectAsStateWithLifecycle()
    val restoredRow by viewModel.restoredRow.collectAsStateWithLifecycle()
    val smart by viewModel.smart.state.collectAsStateWithLifecycle()
    val locale = currentLocale()
    val showEnglish = reading.showsHadithEnglish(listOf(locale))
    var focused by remember { mutableStateOf(false) }
    LaunchedEffect(restore) {
        restore?.let {
            viewModel.restored()
            onRestore(it)
        }
    }
    val chapter = state.chapters.firstOrNull { it.id == route.chapterID }
    val book = state.catalog.firstOrNull { it.id == route.collectionID }
    val title =
        chapter?.chapterTitle(locale)?.takeIf { it.isNotEmpty() } ?: book?.title(locale)
            ?: stringResource(R.string.hadith)
    ScreenScaffold(
        title,
        onBack = onBack,
        actions = { HadithTranslationMenu(showEnglish, viewModel::setEnglish) },
    ) { padding ->
        LibraryGate(viewModel.library, supplications = false, padding = padding) {
            val open: (HadithRoute) -> Unit = { next ->
                viewModel.record()
                onOpen(next)
            }
            val rows = rows(viewModel, state, query, submitted, locale)
            val list = rememberLazyListState()
            // Swift `HadithListAnchor`: save the first visible row once scrolling settles.
            // Rows that settle while loading or restoring aren't the reader's position.
            val saving by rememberUpdatedState(!state.loading && restoredRow == null)
            LaunchedEffect(list) {
                snapshotFlow {
                    list.layoutInfo.visibleItemsInfo
                        .firstOrNull()
                        ?.key as? String
                }.distinctUntilChanged()
                    .debounce(200.milliseconds)
                    .collect { key -> if (saving && key != null) viewModel.saveRow(key) }
            }
            LaunchedEffect(restoredRow, rows, state.loading) {
                val row = restoredRow ?: return@LaunchedEffect
                if (state.loading) return@LaunchedEffect
                rows.indexOfFirst { it.key == row }.takeIf { it >= 0 }?.let { list.scrollToItem(it + 1) }
                viewModel.rowRestored()
            }
            val end by remember {
                derivedStateOf {
                    list.layoutInfo.visibleItemsInfo
                        .lastOrNull()
                        ?.index
                }
            }
            LaunchedEffect(end, state.hasMore) {
                if (state.hasMore && (end ?: 0) >= list.layoutInfo.totalItemsCount - 5) viewModel.loadMore()
            }
            val local = remember(rows) { rows.filterIsInstance<BrowseRow.Narration>().map { it.narration.id }.toSet() }
            LazyColumn(Modifier.fillMaxSize().testTag("hadith-list"), state = list, contentPadding = padding) {
                item(key = "search") {
                    SearchField(
                        query = query,
                        onQuery = viewModel::setQuery,
                        onSubmit = viewModel::submit,
                        placeholder = stringResource(R.string.search_hadith),
                        onFocusChange = { focused = it },
                    )
                }
                if (focused && query.isBlank()) {
                    recentSearches(recent, viewModel::search, viewModel::removeRecent, viewModel::clearRecent)
                }
                items(rows, key = { it.key }) { row ->
                    when (row) {
                        BrowseRow.Saved -> {
                            ListItem(
                                headlineContent = { Text(stringResource(R.string.saved)) },
                                leadingContent = { Icon(Icons.Outlined.BookmarkBorder, null) },
                                modifier = Modifier.clickable { onOpen(HadithSavedRoute()) }.testTag("hadith-saved"),
                            )
                        }

                        is BrowseRow.Header -> {
                            SectionHeader(row.title)
                        }

                        is BrowseRow.Book -> {
                            BookRow(row.book) { open(HadithBrowseRoute(row.book.id)) }
                        }

                        is BrowseRow.Introduction -> {
                            ListItem(
                                headlineContent = {
                                    Text(
                                        stringResource(R.string.introduction),
                                        style = MaterialTheme.typography.titleMedium,
                                    )
                                },
                                modifier =
                                    Modifier
                                        .clickable { onOpen(HadithIntroductionRoute(row.introduction.id)) }
                                        .testTag("hadith-introduction-${row.introduction.id}"),
                            )
                        }

                        is BrowseRow.Chapter -> {
                            ChapterRow(row.chapter) {
                                if (route.chapterID == row.chapter.id) {
                                    viewModel.setQuery("")
                                } else {
                                    open(HadithBrowseRoute(row.chapter.collectionID, row.chapter.id))
                                }
                            }
                        }

                        is BrowseRow.Narration -> {
                            HadithPreviewRow(
                                row.narration,
                                searching = submitted.isNotBlank(),
                                showEnglish = showEnglish,
                                onClick = { open(HadithDetailRoute(row.narration.id, submitted.trim())) },
                                modifier = Modifier.testTag("hadith-result-${row.narration.id}"),
                            )
                        }
                    }
                }
                val settled = query.trim() == submitted.trim() && state.completed == submitted && !state.loading
                if (settled && !state.failed && viewModel.offersSmartSearch(submitted)) {
                    smartSearchSection(
                        smart,
                        viewModel.smart.available,
                        hasLocalResults = rows.any { it !is BrowseRow.Saved },
                        onSearch = viewModel::smartSearch,
                    ) { found ->
                        val narrations = found.filter { it.id !in local }
                        if (narrations.isNotEmpty()) {
                            item(key = "smart-header") { SectionHeader(stringResource(R.string.smart_search)) }
                        }
                        items(narrations, key = { "smart-${it.id}" }) { narration ->
                            HadithPreviewRow(
                                narration,
                                searching = true,
                                showEnglish = showEnglish,
                                onClick = { open(HadithDetailRoute(narration.id, submitted.trim())) },
                                modifier = Modifier.testTag("hadith-smart-${narration.id}"),
                            )
                        }
                    }
                }
                item(key = "status") {
                    Status(viewModel, state, query, submitted, rows.any { it !is BrowseRow.Saved }) {
                        open(HadithBrowseRoute(query = submitted.trim()))
                    }
                }
            }
        }
    }
}

@Composable
private fun rows(
    viewModel: HadithBrowseViewModel,
    state: HadithBrowseState,
    query: String,
    submitted: String,
    locale: java.util.Locale,
): List<BrowseRow> {
    val route = viewModel.route
    val four = stringResource(R.string.the_four)
    val six = stringResource(R.string.the_six)
    val other = stringResource(R.string.other_books)
    val introduction = stringResource(R.string.introduction)
    val hadith = stringResource(R.string.hadith)
    return remember(state, query, submitted, locale, four) {
        val live = query.trim()
        buildList {
            if (route.collectionID == null && route.chapterID == null && submitted.isBlank()) add(BrowseRow.Saved)
            // Books: in the library, filtered by the live query unless it's a number or chapter lookup.
            if (route.collectionID == null && HadithSearch.number(live) == null && HadithSearch.chapter(live) == null) {
                val terms = QuranSearchText.terms(live)
                val books =
                    state.catalog
                        .filter { live.isEmpty() || it.matches(live) }
                        .sortedWith(
                            compareBy<HadithCollection> {
                                if (live.isEmpty()) null else SearchRelevance.score("${it.arabic} ${it.english}", terms)
                            }.thenBy { it.id },
                        )
                val collator = Collator.getInstance(locale)
                for (group in HadithBookGroup.entries) {
                    val shown =
                        books.filter { it.group == group }.sortedWith {
                            a,
                            b,
                            ->
                            collator.compare(a.title(locale), b.title(locale))
                        }
                    if (shown.isEmpty()) continue
                    val name =
                        when (group) {
                            HadithBookGroup.Four -> four
                            HadithBookGroup.Six -> six
                            HadithBookGroup.Other -> other
                        }
                    add(BrowseRow.Header(name, "group:$group"))
                    shown.forEach { add(BrowseRow.Book(it)) }
                }
            }
            if (live.isEmpty() && state.introductions.isNotEmpty()) {
                add(BrowseRow.Header(introduction, "header:introduction"))
                state.introductions.forEach { add(BrowseRow.Introduction(it)) }
            }
            // Chapters: a chN lookup, or those matching the live query (a book's contents show them all).
            val chapters =
                when {
                    HadithSearch.number(live) != null -> {
                        emptyList()
                    }

                    HadithSearch.chapter(live) != null -> {
                        val number = HadithSearch.chapter(live)!!
                        state.chapters.filter {
                            it.index == number - 1 && (route.chapterID == null || it.id == route.chapterID)
                        }
                    }

                    live.isEmpty() && (route.collectionID == null || route.chapterID != null) -> {
                        emptyList()
                    }

                    else -> {
                        state.chapters.filter {
                            (route.chapterID == null || it.id == route.chapterID) &&
                                it.matches(live)
                        }
                    }
                }
            val volumes =
                route.collectionID == null || state.chapters
                    .map { it.bookID }
                    .toSet()
                    .size > 1
            for (group in HadithContentsGroup.groups(chapters)) {
                if (volumes) add(BrowseRow.Header(group.chapters[0].bookTitle(locale), "volume:${group.id}"))
                group.chapters.forEach { add(BrowseRow.Chapter(it)) }
            }
            if (viewModel.showsNarrations(submitted) && live == submitted.trim() && state.narrations.isNotEmpty()) {
                if (submitted.isNotBlank()) add(BrowseRow.Header(hadith, "header:narrations"))
                state.narrations.forEach { add(BrowseRow.Narration(it)) }
            }
        }.distinctBy { it.key }
    }
}

/** Loading, the end of the list, failure, no results, and "Search all books". */
@Composable
private fun Status(
    viewModel: HadithBrowseViewModel,
    state: HadithBrowseState,
    query: String,
    submitted: String,
    hasRows: Boolean,
    onSearchAll: () -> Unit,
) {
    val searched = submitted.trim()
    val settled = query.trim() == searched && state.completed == submitted
    Column(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        when {
            state.loading -> {
                Box(Modifier.padding(top = 48.dp)) { LoadingState(stringResource(R.string.loading_hadith)) }
            }

            state.failed -> {
                EmptyState(stringResource(R.string.unable_to_load_hadith), onAction = viewModel::retry)
            }

            state.loadingMore -> {
                CircularProgressIndicator(Modifier.padding(16.dp))
            }

            // Otherwise the smart-search section says so.
            settled && searched.isNotEmpty() && !hasRows && !viewModel.offersSmartSearch(submitted) -> {
                EmptyState(stringResource(R.string.no_results), Modifier.testTag("hadith-empty-results"))
            }
        }
        if (settled && searched.isNotEmpty() && viewModel.route.collectionID != null &&
            HadithSearch.number(searched) == null && HadithSearch.chapter(searched) == null && !state.loading
        ) {
            OutlinedButton(onClick = onSearchAll, Modifier.testTag("hadith-search-all")) {
                Text(stringResource(R.string.search_all_books))
            }
        }
    }
}

/** Swift `.number`: grouped locale digits. */
private fun grouped(
    value: Int,
    locale: java.util.Locale,
) = android.icu.text.NumberFormat
    .getInstance(locale)
    .format(value)

@Composable
private fun BookRow(
    book: HadithCollection,
    onClick: () -> Unit,
) {
    val locale = currentLocale()
    ListItem(
        headlineContent = { Text(book.title(locale), style = MaterialTheme.typography.titleMedium) },
        supportingContent = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (locale.language != "ar") {
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                        Text(book.arabic, Modifier.fillMaxWidth())
                    }
                }
                Text(
                    stringResource(R.string.x_narrations, grouped(book.count, locale)),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        },
        modifier = Modifier.clickable(onClick = onClick).testTag("hadith-book-${book.id}"),
    )
}

@Composable
private fun ChapterRow(
    chapter: HadithChapter,
    onClick: () -> Unit,
) {
    val locale = currentLocale()
    ListItem(
        headlineContent = { Text(chapter.chapterTitle(locale).ifEmpty { chapter.bookTitle(locale) }) },
        supportingContent = {
            Text(
                stringResource(R.string.x_narrations, grouped(chapter.count, locale)),
                style = MaterialTheme.typography.bodySmall,
            )
        },
        modifier = Modifier.clickable(onClick = onClick).testTag("hadith-chapter-${chapter.id}"),
    )
}

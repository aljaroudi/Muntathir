package com.aljaroudi.muntathir.ui.hadith

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkRemove
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.hadith.Hadith
import com.aljaroudi.muntathir.core.hadith.HadithSource
import com.aljaroudi.muntathir.core.hadith.LibraryStatus
import com.aljaroudi.muntathir.core.hadith.highlightBlocks
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.highlight.ReadingBookmark
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.highlight.SavedEntry
import com.aljaroudi.muntathir.core.text.HadithText
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.data.library.ContentLibraries
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SearchField
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.HadithDetailRoute
import com.aljaroudi.muntathir.ui.navigation.HadithSavedRoute
import com.aljaroudi.muntathir.ui.reader.HighlightDraft
import com.aljaroudi.muntathir.ui.reader.HighlightEditorSheet
import com.aljaroudi.muntathir.ui.reader.highlightSwatch
import com.aljaroudi.muntathir.ui.reader.readingDisplay
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.launch
import java.time.ZoneId

/** Saved sources resolved in the current library: the row each opens, and the highlights that still apply. */
sealed interface SavedNarrations {
    data object Loading : SavedNarrations

    data object Failed : SavedNarrations

    data class Loaded(
        val ids: Map<String, Int>,
        val available: Set<String>,
    ) : SavedNarrations
}

/** Swift `HadithSavedView`: saved hadith, or saved supplications. */
@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel(assistedFactory = HadithSavedViewModel.Factory::class)
class HadithSavedViewModel
    @AssistedInject
    constructor(
        @Assisted val route: HadithSavedRoute,
        libraries: ContentLibraries,
        val user: QuranUserStore,
        settings: ReadingSettings,
        private val history: SearchHistoryStore,
    ) : ViewModel() {
        @AssistedFactory
        interface Factory {
            fun create(route: HadithSavedRoute): HadithSavedViewModel
        }

        val library = if (route.supplications) libraries.supplications else libraries.hadith
        private val reader = library.reader
        val reading = settings.state

        private fun belongs(source: String) =
            !source.startsWith("sermon/") &&
                (HadithSource.fromKey(source)?.book in Hadith.SUPPLICATION_COLLECTION_IDS) == route.supplications

        val highlights: StateFlow<List<ReadingHighlight>> =
            user.highlights
                .map { all -> all.filter { it.isHadith && belongs(it.source) } }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val bookmarks: StateFlow<List<ReadingBookmark>> =
            user.bookmarks
                .map { all -> all.filter { it.kind == ReadingBookmark.Kind.Hadith && belongs(it.source) } }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val unavailable: StateFlow<Boolean> = user.unavailable
        val query = MutableStateFlow("")
        val showingBookmarks = MutableStateFlow(false)
        private val retry = MutableStateFlow(0)

        val narrations: StateFlow<SavedNarrations> =
            combine(
                highlights,
                bookmarks,
                library.state.map { it.revision to it.status }.distinctUntilChanged(),
                retry,
            ) { h, b, (_, status), _ -> Triple(h, b, status) }
                .transformLatest { (highlights, bookmarks, status) ->
                    if (status != LibraryStatus.Ready) return@transformLatest
                    emit(SavedNarrations.Loading)
                    emit(
                        try {
                            resolve(highlights, bookmarks)
                        } catch (cancellation: CancellationException) {
                            throw cancellation
                        } catch (_: Exception) {
                            library.invalidateValidation()
                            SavedNarrations.Failed
                        },
                    )
                }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SavedNarrations.Loading)

        /** Each saved source's row, and the highlights whose text still matches. */
        private suspend fun resolve(
            highlights: List<ReadingHighlight>,
            bookmarks: List<ReadingBookmark>,
        ): SavedNarrations.Loaded {
            val ids = mutableMapOf<String, Int>()
            val available = mutableSetOf<String>()
            val highlighted = highlights.groupBy { it.source }
            for (key in (highlights.map { it.source } + bookmarks.map { it.source }).distinct()) {
                val source = HadithSource.fromKey(key) ?: continue
                val id = reader.resolve(source) ?: continue
                ids[key] = id
                // Only highlights need the text, to check they still match it.
                val saved = highlighted[key] ?: continue
                val detail = reader.detail(id)
                val blocks = detail.highlightBlocks.toMutableMap()
                if (detail.narration.isSupplication) {
                    for (translation in reader.translations(id)) {
                        blocks[translation.block] = HadithText.canonical(HadithText.markdown(translation.text)).text
                    }
                }
                saved.filter { it.isAvailable(blocks) }.forEach { available += it.id }
            }
            return SavedNarrations.Loaded(ids, available)
        }

        private val mutableEditing = MutableStateFlow<HighlightDraft?>(null)
        val editing: StateFlow<HighlightDraft?> = mutableEditing

        fun record() = history.record(query.value, SearchArea.Saved)

        fun edit(highlight: ReadingHighlight) {
            mutableEditing.value = HighlightDraft(listOf(highlight), existing = true)
        }

        fun closeEditor() {
            mutableEditing.value = null
        }

        suspend fun save(highlights: List<ReadingHighlight>) = user.save(highlights)

        suspend fun delete(highlight: ReadingHighlight) = user.delete(highlight)

        fun remove(bookmark: ReadingBookmark) = viewModelScope.launch { runCatching { user.delete(bookmark) } }

        fun retry() {
            viewModelScope.launch { user.reopen() }
            library.refresh()
            retry.value++
        }
    }

@Composable
fun HadithSavedScreen(
    viewModel: HadithSavedViewModel,
    onOpen: (HadithDetailRoute) -> Unit,
    onBack: (() -> Unit)?,
) {
    val highlights by viewModel.highlights.collectAsStateWithLifecycle()
    val bookmarks by viewModel.bookmarks.collectAsStateWithLifecycle()
    val narrations by viewModel.narrations.collectAsStateWithLifecycle()
    val unavailable by viewModel.unavailable.collectAsStateWithLifecycle()
    val reading by viewModel.reading.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val showingBookmarks by viewModel.showingBookmarks.collectAsStateWithLifecycle()
    val editing by viewModel.editing.collectAsStateWithLifecycle()
    val locale = currentLocale()
    val supplications = viewModel.route.supplications
    val failure = if (supplications) R.string.unable_to_load_supplications else R.string.unable_to_load_hadith
    val searchHint = if (showingBookmarks) R.string.search_bookmarks else R.string.search_highlights
    val empty = if (showingBookmarks) R.string.no_bookmarks_yet else R.string.no_highlights_yet
    ScreenScaffold(stringResource(R.string.saved), onBack = onBack) { padding ->
        LibraryGate(viewModel.library, supplications, padding) {
            when {
                unavailable -> {
                    EmptyState(
                        stringResource(R.string.saved_unavailable),
                        Modifier.padding(padding),
                        message = stringResource(R.string.your_saved_data_could_not_be_opened_please_try_a),
                        onAction = viewModel::retry,
                    )
                }

                narrations == SavedNarrations.Loading -> {
                    LoadingState(stringResource(R.string.loading_hadith), Modifier.padding(padding))
                }

                narrations == SavedNarrations.Failed -> {
                    EmptyState(
                        stringResource(failure),
                        Modifier.padding(padding),
                        onAction = viewModel::retry,
                    )
                }

                else -> {
                    val loaded = narrations as SavedNarrations.Loaded
                    val entries = savedEntries(showingBookmarks, highlights, bookmarks)
                    val byDate = reading.savedGroupByDate
                    val sections =
                        remember(entries, byDate, query, locale) {
                            SavedEntry.sections(
                                entries,
                                byDate,
                                query,
                                ZoneId.systemDefault(),
                                locale.language,
                                emptyMap(),
                            )
                        }
                    LazyColumn(Modifier.fillMaxSize().testTag("saved-list"), contentPadding = padding) {
                        item(key = "kind") {
                            SingleChoiceSegmentedButtonRow(
                                Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("saved-kind"),
                            ) {
                                for ((index, label) in listOf(R.string.highlights, R.string.bookmarks).withIndex()) {
                                    SegmentedButton(
                                        selected = showingBookmarks == (index == 1),
                                        onClick = { viewModel.showingBookmarks.value = index == 1 },
                                        shape = SegmentedButtonDefaults.itemShape(index, 2),
                                    ) { Text(stringResource(label)) }
                                }
                            }
                        }
                        item(key = "search") {
                            SearchField(
                                query = query,
                                onQuery = { viewModel.query.value = it },
                                onSubmit = viewModel::record,
                                placeholder = stringResource(searchHint),
                            )
                        }
                        when {
                            entries.isEmpty() -> {
                                item(key = "empty") {
                                    EmptyState(
                                        stringResource(empty),
                                        message =
                                            stringResource(
                                                if (showingBookmarks) {
                                                    R.string.use_bookmark_in_a_verse_or_narration_s_actions_t
                                                } else {
                                                    R.string.select_text_to_highlight_it
                                                },
                                            ),
                                    )
                                }
                            }

                            sections.isEmpty() -> {
                                item(key = "no-matches") { EmptyState(stringResource(R.string.no_results)) }
                            }

                            else -> {
                                for (section in sections) {
                                    if (byDate || query.isNotBlank()) {
                                        item(key = "header-${section.id}") {
                                            SectionHeader(
                                                if (query.isNotBlank()) {
                                                    val related = section.id == "related"
                                                    stringResource(
                                                        if (related) R.string.related_matches else R.string.matches,
                                                    )
                                                } else {
                                                    Formats.date(section.date!!, "yMMMMd", locale)
                                                },
                                            )
                                        }
                                    }
                                    items(section.entries, key = { it.id }) { entry ->
                                        val id = loaded.ids[entry.source]
                                        SavedNarrationRow(
                                            entry = entry,
                                            available =
                                                id != null &&
                                                    entry.highlight.let { it == null || it.id in loaded.available },
                                            onOpen = {
                                                viewModel.record()
                                                if (id != null) {
                                                    onOpen(
                                                        HadithDetailRoute(
                                                            id,
                                                            highlight = entry.highlight?.id,
                                                            supplication = supplications,
                                                        ),
                                                    )
                                                } else {
                                                    entry.highlight?.let(viewModel::edit)
                                                }
                                            },
                                            onEdit = { entry.highlight?.let(viewModel::edit) },
                                            onRemove = { entry.bookmark?.let(viewModel::remove) },
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    editing?.let { draft ->
        key(draft) {
            HighlightEditorSheet(
                draft,
                reading.highlightColors,
                viewModel::save,
                viewModel::delete,
                viewModel::closeEditor,
            )
        }
    }
}

private fun savedEntries(
    bookmarked: Boolean,
    highlights: List<ReadingHighlight>,
    bookmarks: List<ReadingBookmark>,
) = if (bookmarked) bookmarks.map(::SavedEntry) else highlights.map(::SavedEntry)

@Composable
private fun SavedNarrationRow(
    entry: SavedEntry,
    available: Boolean,
    onOpen: () -> Unit,
    onEdit: () -> Unit,
    onRemove: () -> Unit,
) {
    val highlight = entry.highlight
    Row(
        Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clickable(onClick = onOpen)
            .padding(start = 16.dp, top = 8.dp, bottom = 8.dp)
            .testTag("saved-hadith-${entry.id}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (highlight != null) {
            Box(
                Modifier
                    .width(4.dp)
                    .fillMaxHeight()
                    .background(Color(highlightSwatch(highlight.color)), RoundedCornerShape(2.dp)),
            )
        }
        Column(Modifier.weight(1f).padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                entry.reference,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                entry.excerpt.readingDisplay(),
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyLarge,
            )
            if (entry.note.isNotEmpty()) {
                Text(
                    entry.note,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!available) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Outlined.WarningAmber, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        stringResource(
                            if (highlight !=
                                null
                            ) {
                                R.string.highlighted_passage_unavailable
                            } else {
                                R.string.saved_passage_unavailable
                            },
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        var open by remember { mutableStateOf(false) }
        Box {
            val label = stringResource(if (highlight != null) R.string.edit_highlight else R.string.remove_bookmark)
            IconButton(onClick = { open = true }) { Icon(Icons.Outlined.MoreVert, label) }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                if (highlight != null) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.edit_highlight)) },
                        leadingIcon = { Icon(Icons.Outlined.Edit, null) },
                        onClick = {
                            open = false
                            onEdit()
                        },
                    )
                } else {
                    DropdownMenuItem(
                        text = {
                            Text(
                                stringResource(R.string.remove_bookmark),
                                color = MaterialTheme.colorScheme.error,
                            )
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Outlined.BookmarkRemove,
                                null,
                                tint = MaterialTheme.colorScheme.error,
                            )
                        },
                        onClick = {
                            open = false
                            onRemove()
                        },
                    )
                }
            }
        }
    }
}

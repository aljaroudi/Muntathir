package com.aljaroudi.muntathir.ui.quran

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
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material.icons.outlined.BookmarkRemove
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.highlight.SavedEntry
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.SearchMatch
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SearchField
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.QuranReaderRoute
import com.aljaroudi.muntathir.ui.reader.BookmarkFailedDialog
import com.aljaroudi.muntathir.ui.reader.HighlightEditorSheet
import com.aljaroudi.muntathir.ui.reader.highlightSwatch
import com.aljaroudi.muntathir.ui.reader.readingDisplay
import com.aljaroudi.muntathir.ui.reader.title
import com.aljaroudi.muntathir.ui.reader.toAnnotatedString
import com.aljaroudi.muntathir.ui.theme.QuranFont
import java.time.LocalDate
import java.time.ZoneId

/** Swift `QuranSavedVersesView` around `SavedList`: highlights or bookmarks, grouped by source or day, searchable. */
@Composable
fun QuranSavedScreen(
    viewModel: QuranSavedViewModel,
    onOpen: (QuranReaderRoute) -> Unit,
    onBack: (() -> Unit)?,
) {
    val highlights by viewModel.highlights.collectAsStateWithLifecycle()
    val bookmarks by viewModel.bookmarks.collectAsStateWithLifecycle()
    val verses by viewModel.verses.collectAsStateWithLifecycle()
    val unavailable by viewModel.unavailable.collectAsStateWithLifecycle()
    val reading by viewModel.reading.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val showingBookmarks by viewModel.showingBookmarks.collectAsStateWithLifecycle()
    val editing by viewModel.editing.collectAsStateWithLifecycle()
    val bookmarkFailed by viewModel.bookmarkFailed.collectAsStateWithLifecycle()
    val locale = currentLocale()
    val byDate = reading.savedGroupByDate
    val loaded = (verses as? SavedVerses.Loaded)?.verses.orEmpty()
    val names by viewModel.surahNames.collectAsStateWithLifecycle()
    ScreenScaffold(
        stringResource(R.string.saved),
        onBack = onBack,
        actions = { GroupingMenu(byDate, viewModel::setGroupByDate) },
    ) { padding ->
        when {
            unavailable -> {
                EmptyState(
                    stringResource(R.string.saved_unavailable),
                    Modifier.padding(padding),
                    message = stringResource(R.string.your_saved_data_could_not_be_opened_please_try_a),
                    onAction = viewModel::retry,
                )
            }

            verses == SavedVerses.Loading -> {
                LoadingState(stringResource(R.string.loading_quran), Modifier.padding(padding))
            }

            verses == SavedVerses.Failed -> {
                EmptyState(
                    stringResource(R.string.unable_to_load_quran),
                    Modifier.padding(padding),
                    onAction = viewModel::retry,
                )
            }

            else -> {
                val entries = if (showingBookmarks) bookmarks.map(::SavedEntry) else highlights.map(::SavedEntry)
                val sections =
                    remember(entries, byDate, query, locale) {
                        SavedEntry.sections(entries, byDate, query, ZoneId.systemDefault(), locale.language, names)
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
                            placeholder =
                                stringResource(
                                    if (showingBookmarks) R.string.search_bookmarks else R.string.search_highlights,
                                ),
                        )
                    }
                    when {
                        entries.isEmpty() -> {
                            item(key = "empty") {
                                if (showingBookmarks) {
                                    EmptyState(
                                        stringResource(R.string.no_bookmarks_yet),
                                        message = stringResource(R.string.use_bookmark_to_save_a_passage),
                                    )
                                } else {
                                    EmptyState(
                                        stringResource(R.string.no_highlights_yet),
                                        message = stringResource(R.string.select_text_to_highlight_it),
                                    )
                                }
                            }
                        }

                        sections.isEmpty() -> {
                            item(key = "no-matches") { EmptyState(stringResource(R.string.no_results)) }
                        }

                        else -> {
                            for (section in sections) {
                                item(key = "header-${section.id}") {
                                    SectionHeader(sectionTitle(section, query, locale.language, names))
                                }
                                items(section.entries, key = { it.id }) { entry ->
                                    val verse = loaded[entry.source]
                                    SavedRow(
                                        entry = entry,
                                        verse = verse,
                                        query = query,
                                        showReference = byDate,
                                        names = names,
                                        onOpen = {
                                            viewModel.record()
                                            if (verse != null) {
                                                onOpen(
                                                    QuranReaderRoute(
                                                        verse.surah,
                                                        verse.number,
                                                        highlight = entry.highlight?.id,
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
    if (bookmarkFailed) BookmarkFailedDialog(viewModel::dismissBookmarkFailure)
}

@Composable
private fun sectionTitle(
    section: SavedEntry.Section,
    query: String,
    language: String,
    names: Map<Int, String>,
): String {
    val locale = currentLocale()
    val date = section.date
    return when {
        query.isNotBlank() -> {
            stringResource(
                if (section.id ==
                    "related"
                ) {
                    R.string.related_matches
                } else {
                    R.string.matches
                },
            )
        }

        date == LocalDate.now() -> {
            stringResource(R.string.today)
        }

        date == LocalDate.now().minusDays(1) -> {
            stringResource(R.string.yesterday)
        }

        date != null -> {
            Formats.date(date, "yMMMMd", locale)
        }

        else -> {
            section.entries[0].title(language, names)
        }
    }
}

/** Swift `SavedList` "Grouping" menu. */
@Composable
private fun GroupingMenu(
    byDate: Boolean,
    onChange: (Boolean) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, Modifier.testTag("saved-grouping")) {
            Icon(Icons.AutoMirrored.Outlined.Sort, stringResource(R.string.grouping))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for ((value, label) in listOf(false to R.string.group_by_source, true to R.string.group_by_date)) {
                DropdownMenuItem(
                    text = { Text(stringResource(label)) },
                    leadingIcon = { if (value == byDate) Icon(Icons.Outlined.Check, null) },
                    onClick = {
                        open = false
                        onChange(value)
                    },
                )
            }
        }
    }
}

/** Swift `HighlightSummary` and the bookmark row, with Edit or Remove in a menu (Swift swipe/context actions). */
@Composable
private fun SavedRow(
    entry: SavedEntry,
    verse: Ayah?,
    query: String,
    showReference: Boolean,
    names: Map<Int, String>,
    onOpen: () -> Unit,
    onEdit: () -> Unit,
    onRemove: () -> Unit,
) {
    val locale = currentLocale()
    val highlight = entry.highlight
    val available = highlight == null || (verse != null && highlight.isAvailable(blocks(verse)))
    // Bookmarks keep the Arabic verse; highlights quote whichever block they were made in.
    val excerptFont = if (highlight == null || highlight.block == ARABIC_BLOCK) QuranFont else null
    val tag = "saved-verse-${entry.source}"
    Row(
        Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clickable(onClick = onOpen)
            .padding(start = 16.dp, top = 8.dp, bottom = 8.dp)
            .testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (highlight != null) {
            val colorName = stringResource(highlight.color.title)
            Box(
                Modifier
                    .width(4.dp)
                    .fillMaxHeight()
                    .background(Color(highlightSwatch(highlight.color)), RoundedCornerShape(2.dp))
                    .semantics { contentDescription = colorName },
            )
        }
        Column(Modifier.weight(1f).padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (showReference) {
                Text(
                    entry.title(locale.language, names),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (query.isBlank()) {
                Text(
                    entry.excerpt.readingDisplay(),
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyLarge,
                    fontFamily = excerptFont,
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
            } else {
                for (text in listOf(entry.excerpt, entry.note).filter { it.isNotEmpty() }) {
                    val match = SearchMatch.text(text, query)
                    if (text == entry.excerpt || match.spans.isNotEmpty() || QuranSearchText.queryTerms(query).isEmpty()) {
                        Text(
                            SearchMatch.preview(match, compact = true).toAnnotatedString(),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            fontFamily = if (text == entry.excerpt) excerptFont else null,
                        )
                    }
                }
            }
            if (!available || verse == null) {
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
        RowMenu(highlight, onEdit, onRemove)
    }
}

@Composable
private fun RowMenu(
    highlight: ReadingHighlight?,
    onEdit: () -> Unit,
    onRemove: () -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        // The menu holds one action, which names the button.
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
                    text = { Text(stringResource(R.string.remove_bookmark), color = MaterialTheme.colorScheme.error) },
                    leadingIcon = { Icon(Icons.Outlined.BookmarkRemove, null, tint = MaterialTheme.colorScheme.error) },
                    onClick = {
                        open = false
                        onRemove()
                    },
                )
            }
        }
    }
}

/** A verse's texts by block, for checking that a highlight still applies. */
private fun blocks(verse: Ayah): Map<String, String> = mapOf(ARABIC_BLOCK to verse.text) + verse.translations

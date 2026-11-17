package com.aljaroudi.muntathir.ui.quran

import android.icu.text.NumberFormat
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.FormatSize
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.QuranReadingMode
import com.aljaroudi.muntathir.core.app.ReadingPreferences
import com.aljaroudi.muntathir.core.highlight.HighlightColor
import com.aljaroudi.muntathir.core.highlight.ReadingBookmark
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.quran.QuranReference
import com.aljaroudi.muntathir.core.quran.QuranTranslation
import com.aljaroudi.muntathir.core.text.SearchMatch
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SearchField
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.components.plus
import com.aljaroudi.muntathir.ui.navigation.QuranReaderRoute
import com.aljaroudi.muntathir.ui.reader.HighlightEditorSheet
import com.aljaroudi.muntathir.ui.reader.HighlightSwatch
import com.aljaroudi.muntathir.ui.reader.ReaderText
import com.aljaroudi.muntathir.ui.reader.ReadingTextStyle
import com.aljaroudi.muntathir.ui.reader.quranTypeface
import java.util.Locale

/** Swift `QuranReadingView`: one surah as verses, or the mushaf, keeping the position across modes. */
@Composable
fun QuranReaderScreen(
    viewModel: QuranReaderViewModel,
    onOpen: (QuranReaderRoute) -> Unit,
    onBack: (() -> Unit)?,
) {
    val search by viewModel.search.collectAsStateWithLifecycle()
    val reading by viewModel.reading.collectAsStateWithLifecycle()
    val catalog by viewModel.catalog.collectAsStateWithLifecycle()
    val chapter by viewModel.chapter.collectAsStateWithLifecycle()
    val position by viewModel.position.collectAsStateWithLifecycle()
    val locale = currentLocale()
    var juz by remember { mutableIntStateOf(0) }
    var sizing by rememberSaveable { mutableStateOf(false) }
    var picking by rememberSaveable { mutableStateOf(false) }
    TranslationPickerHost(viewModel.translations, picking) { picking = false }
    val surahs = catalog?.surahs.orEmpty()
    val surahTitle = surahs.getOrNull(position.surah - 1)?.title(locale.language).orEmpty()
    val mode = reading.quranReadingMode
    val title =
        if (mode == QuranReadingMode.Mushaf &&
            juz > 0
        ) {
            "$surahTitle · ${stringResource(R.string.juz_x, juz)}"
        } else {
            surahTitle
        }
    ScreenScaffold(
        title = title,
        onBack = onBack,
        actions = {
            IconButton(
                onClick = { if (search == null) viewModel.openSearch() else viewModel.closeSearch() },
                modifier = Modifier.testTag("quran-reader-search"),
            ) {
                if (search == null) {
                    Icon(Icons.Outlined.Search, stringResource(R.string.search))
                } else {
                    Icon(Icons.Outlined.Close, stringResource(R.string.close_search))
                }
            }
            ReaderMenu(
                mode = mode,
                onMode = { viewModel.setMode(it) },
                onTranslation = { picking = true },
                onTextSize = { sizing = true }.takeIf { mode == QuranReadingMode.Verses },
            )
        },
    ) { padding ->
        val model = search
        val covered =
            model
                ?.query
                ?.collectAsStateWithLifecycle()
                ?.value
                ?.isNotBlank() == true
        // Search results cover the reader without rebuilding it, so its place and layout survive.
        Box(
            Modifier.fillMaxSize().then(
                if (covered) Modifier.alpha(0f).clearAndSetSemantics {} else Modifier,
            ),
        ) {
            ReaderContent(viewModel, mode, chapter, position, reading.readingSizePercent, surahs, padding) { juz = it }
        }
        if (model != null) {
            ReaderSearch(
                model = model,
                surahNames = surahs.associate { it.id to it.arabic },
                padding = padding,
                onOpen = { route ->
                    viewModel.closeSearch()
                    onOpen(route)
                },
            )
        }
    }
    if (sizing) {
        ReadingSizeSheet(reading.readingSizePercent, locale, viewModel::setSize) { sizing = false }
    }
    HighlightDialogs(viewModel, reading.highlightColors)
}

/** The editor, the chooser for overlapping highlights, and the bookmark failure alert. */
@Composable
private fun HighlightDialogs(
    viewModel: QuranReaderViewModel,
    colors: List<HighlightColor>,
) {
    val editing by viewModel.editing.collectAsStateWithLifecycle()
    val choosing by viewModel.choosing.collectAsStateWithLifecycle()
    val bookmarkFailed by viewModel.bookmarkFailed.collectAsStateWithLifecycle()
    editing?.let { draft ->
        key(draft) {
            HighlightEditorSheet(draft, colors, viewModel::save, viewModel::delete, viewModel::closeEditor)
        }
    }
    if (choosing.isNotEmpty()) {
        AlertDialog(
            onDismissRequest = viewModel::closeEditor,
            title = { Text(stringResource(R.string.highlights)) },
            text = {
                Column {
                    for (highlight in choosing) {
                        ListItem(
                            headlineContent = { Text(highlight.note.ifBlank { highlight.excerpt }.take(60)) },
                            leadingContent = { HighlightSwatch(highlight.color, selected = false, size = 20) },
                            modifier = Modifier.clickable { viewModel.edit(highlight) },
                        )
                    }
                }
            },
            confirmButton = { TextButton(onClick = viewModel::closeEditor) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (bookmarkFailed) {
        AlertDialog(
            onDismissRequest = viewModel::dismissBookmarkFailure,
            title = { Text(stringResource(R.string.unable_to_save_bookmark)) },
            text = { Text(stringResource(R.string.please_try_again)) },
            confirmButton = {
                TextButton(
                    onClick = viewModel::dismissBookmarkFailure,
                ) { Text(stringResource(R.string.ok)) }
            },
        )
    }
}

/** Swift `BookmarkButton` as a verse-menu item. */
@Composable
fun BookmarkItem(
    bookmarked: Boolean,
    onToggle: () -> Unit,
    close: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(stringResource(if (bookmarked) R.string.remove_bookmark else R.string.bookmark)) },
        leadingIcon = { Icon(if (bookmarked) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder, null) },
        onClick = {
            close()
            onToggle()
        },
        modifier = Modifier.testTag("verse-bookmark"),
    )
}

@Composable
private fun ReaderContent(
    viewModel: QuranReaderViewModel,
    mode: QuranReadingMode,
    chapter: ChapterState,
    position: ReaderPosition,
    sizePercent: Int,
    surahs: List<com.aljaroudi.muntathir.core.quran.QuranSurah>,
    padding: PaddingValues,
    onJuz: (Int) -> Unit,
) {
    run {
        // Switching modes rebuilds the reader at the current position.
        key(mode) {
            when (mode) {
                QuranReadingMode.Verses -> {
                    val highlights by viewModel.highlights.collectAsStateWithLifecycle()
                    val bookmarks by viewModel.bookmarks.collectAsStateWithLifecycle()
                    VersesReader(
                        chapter = chapter,
                        initialVerse = position.verse,
                        query = viewModel.route.query,
                        sizePercent = sizePercent,
                        surahNames = surahs.associate { it.id to it.arabic },
                        padding = padding,
                        onPosition = viewModel::setPosition,
                        onRetry = viewModel::retry,
                        highlights = highlights,
                        onSelect = viewModel::select,
                        onOpenHighlights = viewModel::open,
                        actions = { ayah ->
                            val bookmarked =
                                bookmarks.any {
                                    it.kind == ReadingBookmark.Kind.Quran &&
                                        it.source == ayah.id
                                }
                            val item: @Composable (() -> Unit) -> Unit = { close ->
                                BookmarkItem(bookmarked, { viewModel.toggleBookmark(ayah) }, close)
                            }
                            item
                        },
                    )
                }

                QuranReadingMode.Mushaf -> {
                    if (surahs.isEmpty()) {
                        LoadingState(stringResource(R.string.loading_quran), Modifier.padding(padding))
                    } else {
                        val highlights by viewModel.highlights.collectAsStateWithLifecycle()
                        MushafReader(
                            viewModel,
                            position,
                            surahs,
                            padding,
                            onPage = { onJuz(it.juz) },
                            onPosition = viewModel::setPosition,
                            highlights =
                                remember(highlights) {
                                    MushafHighlights(
                                        highlights = { page -> highlights.filter { it.source in page.verses } },
                                        onSelect = { page, selection -> viewModel.select(page.highlights(selection)) },
                                        onOpen = viewModel::open,
                                    )
                                },
                        )
                    }
                }
            }
        }
    }
}

/** Swift in-reader `.searchable`: verse number or text within the surah, over the reader. */
@Composable
private fun ReaderSearch(
    model: QuranSearchModel,
    surahNames: Map<Int, String>,
    padding: PaddingValues,
    onOpen: (QuranReaderRoute) -> Unit,
) {
    val query by model.query.collectAsStateWithLifecycle()
    val submitted by model.submitted.collectAsStateWithLifecycle()
    val results by model.results.collectAsStateWithLifecycle()
    val smart by model.smart.collectAsStateWithLifecycle()
    val recent by model.recent.collectAsStateWithLifecycle()
    val focus = remember { FocusRequester() }
    LaunchedEffect(model) { focus.requestFocus() }
    val showsList = query.isNotBlank() || recent.isNotEmpty()
    LazyColumn(
        Modifier
            .fillMaxWidth()
            .then(if (query.isNotBlank()) Modifier.fillMaxSize() else Modifier)
            .background(MaterialTheme.colorScheme.surface)
            .testTag("quran-reader-search-results"),
        contentPadding =
            PaddingValues(
                top = padding.calculateTopPadding(),
                bottom = if (showsList) padding.calculateBottomPadding() else 0.dp,
            ),
    ) {
        item(key = "search") {
            SearchField(
                query = query,
                onQuery = model::setQuery,
                onSubmit = model::submit,
                placeholder = stringResource(R.string.verse_number_or_quran_text),
                focusRequester = focus,
            )
        }
        if (query.isBlank()) {
            recentSearches(
                recent,
                onSelect = model::search,
                onRemove = model::removeRecent,
                onClear = model::clearRecent,
            )
        } else {
            quranSearchResults(
                query = query,
                submitted = submitted,
                results = results,
                smart = smart,
                smartAvailable = model.smartSearchAvailable,
                hasSurahs = false,
                scoped = true,
                surahNames = surahNames,
                onOpen = { ayah ->
                    model.record()
                    onOpen(QuranReaderRoute(ayah.surah, ayah.number, query = submitted.trim()))
                },
                onLoadMore = model::loadMore,
                onRetry = model::retry,
                onSmartSearch = model::smartSearch,
            )
        }
    }
}

/** Swift `QuranChapterView`: the surah's verses, opened at [initialVerse]; reports the topmost visible verse. */
@Composable
private fun VersesReader(
    chapter: ChapterState,
    initialVerse: Int,
    query: String?,
    sizePercent: Int,
    surahNames: Map<Int, String>,
    padding: PaddingValues,
    onPosition: (ReaderPosition) -> Unit,
    onRetry: () -> Unit,
    highlights: List<ReadingHighlight>,
    onSelect: (Ayah, String, String, List<TextRange>) -> Unit,
    onOpenHighlights: (List<ReadingHighlight>) -> Unit,
    actions: (Ayah) -> (@Composable (close: () -> Unit) -> Unit),
) {
    val bySource = remember(highlights) { highlights.groupBy { it.source } }
    when (chapter) {
        ChapterState.Loading -> {
            LoadingState(stringResource(R.string.loading_quran), Modifier.padding(padding))
        }

        ChapterState.Failed -> {
            EmptyState(stringResource(R.string.unable_to_load_quran), Modifier.padding(padding), onAction = onRetry)
        }

        is ChapterState.Loaded -> {
            key(chapter.surah) {
                val start = chapter.verses.indexOfFirst { it.number == initialVerse }.coerceAtLeast(0)
                val list = rememberLazyListState(initialFirstVisibleItemIndex = start)
                val report by rememberUpdatedState(onPosition)
                LaunchedEffect(list, chapter) {
                    snapshotFlow { list.firstVisibleItemIndex }.collect { index ->
                        chapter.verses.getOrNull(index)?.let { report(ReaderPosition(it.surah, it.number)) }
                    }
                }
                LazyColumn(
                    state = list,
                    contentPadding = padding + PaddingValues(bottom = 24.dp),
                    modifier = Modifier.fillMaxSize().testTag("quran-verses"),
                ) {
                    items(chapter.verses, key = { it.id }) { ayah ->
                        QuranVerseRow(
                            ayah = ayah,
                            translation = chapter.translation,
                            query = query,
                            sizePercent = sizePercent,
                            surahNames = surahNames,
                            actions = actions(ayah),
                            highlights = bySource[ayah.id].orEmpty(),
                            onSelect = { block, text, ranges -> onSelect(ayah, block, text, ranges) },
                            onOpenHighlights = onOpenHighlights,
                        )
                        HorizontalDivider(Modifier.padding(horizontal = 20.dp))
                    }
                }
            }
        }
    }
}

/** Swift `QuranVerseRow` (full mode): reference and actions, Arabic, then the translation. */
@Composable
fun QuranVerseRow(
    ayah: Ayah,
    translation: String?,
    query: String?,
    sizePercent: Int,
    surahNames: Map<Int, String>,
    modifier: Modifier = Modifier,
    actions: (@Composable (close: () -> Unit) -> Unit)? = null,
    highlights: List<ReadingHighlight> = emptyList(),
    onSelect: ((block: String, text: String, ranges: List<TextRange>) -> Unit)? = null,
    onOpenHighlights: (List<ReadingHighlight>) -> Unit = {},
) {
    val locale = currentLocale()
    val reference = QuranReference.display(ayah.id, locale.language, surahNames)
    val translated = translation?.let { ayah.translations[it] }
    val verseLabel = stringResource(R.string.verse_x, reference)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            modifier
                .widthIn(
                    max = 640.dp,
                ).fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp)
                .testTag("quran-verse-${ayah.id}"),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    reference,
                    style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.semantics { contentDescription = verseLabel },
                )
                Spacer(Modifier.weight(1f))
                VerseActions(ayah, translated, reference, Modifier.testTag("verse-actions-${ayah.id}"), actions)
            }
            ReaderText(
                text = SearchMatch.text(ayah.text, query.orEmpty()),
                block = ARABIC_BLOCK,
                sizeSp = ReadingTextStyle.arabicSize(sizePercent),
                typeface = quranTypeface(),
                rightToLeft = true,
                modifier = Modifier.fillMaxWidth().testTag("quran-arabic-${ayah.id}"),
                highlights = highlights,
                onHighlight = { onSelect?.invoke(ARABIC_BLOCK, ayah.text, it) },
                canHighlight = { onSelect != null },
                onOpenHighlights = onOpenHighlights,
            )
            if (translation != null && translated != null) {
                ReaderText(
                    text = SearchMatch.text(translated, query.orEmpty()),
                    block = translation,
                    sizeSp = ReadingTextStyle.bodySize(sizePercent),
                    rightToLeft = QuranTranslation.of(translation)?.isRightToLeft == true,
                    modifier = Modifier.fillMaxWidth().testTag("quran-translation-${ayah.id}"),
                    highlights = highlights,
                    onHighlight = { onSelect?.invoke(translation, translated, it) },
                    canHighlight = { onSelect != null },
                    onOpenHighlights = onOpenHighlights,
                )
            }
        }
    }
}

const val ARABIC_BLOCK = "arabic"

/** Reading mode and text size. */
@Composable
private fun ReaderMenu(
    mode: QuranReadingMode,
    onMode: (QuranReadingMode) -> Unit,
    onTranslation: () -> Unit,
    onTextSize: (() -> Unit)?,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, Modifier.testTag("quran-reading-options")) {
            Icon(Icons.Outlined.MoreVert, stringResource(R.string.reading_options))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            Text(
                stringResource(R.string.reading_mode),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            )
            for ((option, label) in listOf(
                QuranReadingMode.Verses to R.string.verses,
                QuranReadingMode.Mushaf to R.string.mushaf,
            )) {
                DropdownMenuItem(
                    text = { Text(stringResource(label)) },
                    leadingIcon = {
                        if (option ==
                            mode
                        ) {
                            Icon(Icons.Outlined.Check, null)
                        } else {
                            Spacer(Modifier.padding(12.dp))
                        }
                    },
                    onClick = {
                        open = false
                        onMode(option)
                    },
                    modifier = Modifier.testTag("reading-mode-${option.id}"),
                )
            }
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(stringResource(R.string.translation)) },
                leadingIcon = { Icon(Icons.Outlined.Translate, null) },
                onClick = {
                    open = false
                    onTranslation()
                },
                modifier = Modifier.testTag("quran-translation-picker-open"),
            )
            if (onTextSize != null) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.text_size)) },
                    leadingIcon = { Icon(Icons.Outlined.FormatSize, null) },
                    onClick = {
                        open = false
                        onTextSize()
                    },
                    modifier = Modifier.testTag("reading-size"),
                )
            }
        }
    }
}

/** Swift `ReadingSizeMenu`: smaller/larger in 10% steps (80–160%) and Reset. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadingSizeSheet(
    percent: Int,
    locale: Locale,
    onChange: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val sizes = ReadingPreferences.SIZES
    val step = ReadingPreferences.SIZE_STEP
    val value = remember(percent, locale) { NumberFormat.getPercentInstance(locale).format(percent / 100.0) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.text_size), style = MaterialTheme.typography.titleMedium)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                val decrease = stringResource(R.string.decrease_text_size)
                val increase = stringResource(R.string.increase_text_size)
                OutlinedIconButton(
                    onClick = { onChange((percent - step).coerceIn(sizes)) },
                    enabled = percent > sizes.first,
                    modifier =
                        Modifier.testTag("reading-size-decrease").semantics {
                            contentDescription = decrease
                            stateDescription = value
                        },
                ) { Text("A", fontSize = 18.sp) }
                Text(value, style = MaterialTheme.typography.titleLarge.copy(fontFeatureSettings = "tnum"))
                OutlinedIconButton(
                    onClick = { onChange((percent + step).coerceIn(sizes)) },
                    enabled = percent < sizes.last,
                    modifier =
                        Modifier.testTag("reading-size-increase").semantics {
                            contentDescription = increase
                            stateDescription = value
                        },
                ) { Text("A", fontSize = 30.sp) }
            }
            TextButton(
                onClick = { onChange(ReadingPreferences.DEFAULT_SIZE) },
                enabled = percent != ReadingPreferences.DEFAULT_SIZE,
                modifier = Modifier.testTag("reading-size-reset"),
            ) { Text(stringResource(R.string.reset)) }
        }
    }
}

package com.aljaroudi.muntathir.ui.rulings

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.BookmarkRemove
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FormatSize
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.highlight.ReadingBookmark
import com.aljaroudi.muntathir.core.rulings.Ruling
import com.aljaroudi.muntathir.core.rulings.RulingsLanguage
import com.aljaroudi.muntathir.core.rulings.RulingsState
import com.aljaroudi.muntathir.core.rulings.RulingsStatus
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.data.library.RulingsLibrary
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.InlineProgress
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SearchField
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.downloads.AssetDownloadButton
import com.aljaroudi.muntathir.ui.downloads.AssetDownloadProgress
import com.aljaroudi.muntathir.ui.downloads.formatBytes
import com.aljaroudi.muntathir.ui.navigation.Route
import com.aljaroudi.muntathir.ui.navigation.RulingDetailRoute
import com.aljaroudi.muntathir.ui.navigation.RulingSectionRoute
import com.aljaroudi.muntathir.ui.navigation.RulingsSavedRoute
import com.aljaroudi.muntathir.ui.quran.ConfirmationPrompt
import com.aljaroudi.muntathir.ui.quran.ReadingSizeSheet
import com.aljaroudi.muntathir.ui.quran.recentSearches
import com.aljaroudi.muntathir.ui.reader.BookmarkFailedDialog
import com.aljaroudi.muntathir.ui.reader.ReaderText
import com.aljaroudi.muntathir.ui.reader.ReadingTextStyle
import com.aljaroudi.muntathir.ui.reader.readingDisplay
import com.aljaroudi.muntathir.ui.theme.HadithFont
import com.aljaroudi.muntathir.ui.theme.ReaderBodyFont

/** Swift `RulingsIntroSection`: the disclaimer and the Saved link. */
private fun LazyListScope.intro(onSaved: () -> Unit) {
    item(key = "notice") {
        ListItem(
            headlineContent = {
                Text(
                    stringResource(R.string.this_app_is_not_a_source_of_religious_rulings_re),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            },
            leadingContent = { Icon(Icons.Outlined.WarningAmber, null) },
            modifier = Modifier.testTag("rulings-notice"),
        )
    }
    item(key = "saved") {
        ListItem(
            headlineContent = { Text(stringResource(R.string.saved)) },
            leadingContent = { Icon(Icons.Outlined.BookmarkBorder, null) },
            modifier = Modifier.clickable(onClick = onSaved).testTag("rulings-saved"),
        )
    }
}

/** Swift `RulingsDownloadSection`: progress, the size with Remove, or Download. */
fun LazyListScope.rulingsDownload(
    library: RulingsLibrary,
    state: RulingsState,
) {
    item(key = "rulings-download") {
        val activity = LocalActivity.current
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when {
                state.status == RulingsStatus.Downloading -> {
                    AssetDownloadProgress(state.progress, installing = false, preparing = state.progress == null)
                    ConfirmationPrompt(state.needsConfirmation) { activity?.let(library::confirm) }
                }

                state.busy || state.status == RulingsStatus.Checking -> {
                    CircularProgressIndicator()
                }

                state.status == RulingsStatus.Ready -> {
                    val locale = currentLocale()
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.total_size)) },
                        trailingContent = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(formatBytes(state.installedBytes, locale))
                                IconButton(onClick = library::remove, Modifier.testTag("downloads-remove-rulings")) {
                                    Icon(Icons.Outlined.Delete, stringResource(R.string.remove_download))
                                }
                            }
                        },
                        modifier = Modifier.testTag("downloads-size-rulings"),
                    )
                }

                else -> {
                    if (state.status == RulingsStatus.Incompatible) {
                        Text(stringResource(R.string.this_download_needs_an_update))
                    } else if (state.status == RulingsStatus.Failed) {
                        Text(stringResource(R.string.unable_to_download_please_try_again))
                    }
                    AssetDownloadButton(
                        pack = "rulings",
                        retry = state.status == RulingsStatus.Failed || state.status == RulingsStatus.Incompatible,
                        onClick = library::download,
                        modifier = Modifier.testTag("downloads-get-rulings"),
                    )
                }
            }
        }
    }
}

@Composable
private fun StorageErrorDialog(
    library: RulingsLibrary,
    state: RulingsState,
) {
    if (!state.storageError) return
    AlertDialog(
        onDismissRequest = library::clearStorageError,
        title = { Text(stringResource(R.string.unable_to_finish_storage_cleanup)) },
        text = { Text(stringResource(R.string.some_files_remain_on_this_device_please_try_agai)) },
        confirmButton = {
            TextButton(onClick = {
                library.clearStorageError()
                library.remove()
            }) { Text(stringResource(R.string.try_again)) }
        },
        dismissButton = { TextButton(onClick = library::clearStorageError) { Text(stringResource(R.string.cancel)) } },
    )
}

/** Swift `RulingsView`: the download, or the browser. */
@Composable
fun RulingsScreen(
    viewModel: RulingsViewModel,
    onOpen: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    val library by viewModel.library.state.collectAsStateWithLifecycle()
    val scope by viewModel.scope.collectAsStateWithLifecycle()
    val questions by viewModel.questions.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val recent by viewModel.recent.collectAsStateWithLifecycle()
    var focused by remember { mutableStateOf(false) }
    val locale = currentLocale()
    ScreenScaffold(stringResource(R.string.rulings), onBack = onBack) { padding ->
        LazyColumn(Modifier.fillMaxSize().testTag("rulings-list"), contentPadding = padding) {
            if (library.status != RulingsStatus.Ready) {
                intro { onOpen(RulingsSavedRoute) }
                rulingsDownload(viewModel.library, library)
                return@LazyColumn
            }
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
            intro { onOpen(RulingsSavedRoute) }
            when (val current = scope) {
                Loadable.Loading -> {
                    item(key = "loading") { InlineProgress() }
                }

                Loadable.Failed -> {
                    item(key = "failed") { EmptyState(stringResource(R.string.try_again), onAction = viewModel::retry) }
                }

                is Loadable.Loaded -> {
                    val value = current.value
                    item(key = "authority") {
                        Picker(
                            label = stringResource(R.string.religious_authority),
                            selected = value.authorityName(locale),
                            options = value.authorities.map { it.id to it.name(locale) },
                            onSelect = viewModel::setAuthority,
                            tag = "rulings-authority",
                        )
                    }
                    item(key = "language") {
                        Picker(
                            label = stringResource(R.string.language),
                            selected = value.language?.name ?: stringResource(R.string.choose_a_language),
                            options = value.languages.map { it.id to it.name },
                            onSelect = viewModel::setLanguage,
                            tag = "rulings-language",
                        )
                    }
                    val language = value.language
                    if (language == null) {
                        item(key = "choose") { EmptyState(stringResource(R.string.choose_a_language)) }
                    } else {
                        val open: (Ruling) -> Unit = { ruling ->
                            viewModel.record()
                            onOpen(RulingDetailRoute(ruling.id.authority, ruling.id.language, ruling.id.siteID))
                        }
                        rulingRows(questions, language, true, viewModel::retry, open)
                    }
                }
            }
        }
    }
    StorageErrorDialog(viewModel.library, library)
}

/** Questions as rows, laid out in their language's direction. */
private fun LazyListScope.rulingRows(
    questions: Loadable<List<Ruling>>,
    language: RulingsLanguage,
    emptyMessage: Boolean,
    onRetry: () -> Unit,
    onOpen: (Ruling) -> Unit,
) {
    when (questions) {
        Loadable.Loading -> {
            item(key = "questions-loading") { InlineProgress() }
        }

        Loadable.Failed -> {
            item(key = "questions-failed") { EmptyState(stringResource(R.string.please_try_again), onAction = onRetry) }
        }

        is Loadable.Loaded -> {
            if (questions.value.isEmpty() && emptyMessage) {
                item(key = "questions-empty") { EmptyState(stringResource(R.string.no_results)) }
            }
            rulingItems(questions.value, language, "rulings-question", onOpen)
        }
    }
}

/** One row per ruling; [tag] prefixes each row's key and test tag. */
private fun LazyListScope.rulingItems(
    rulings: List<Ruling>,
    language: RulingsLanguage,
    tag: String,
    onOpen: (Ruling) -> Unit,
) {
    val direction = if (language.rightToLeft) LayoutDirection.Rtl else LayoutDirection.Ltr
    items(rulings, key = { "$tag-${it.id.siteID}" }) { ruling ->
        CompositionLocalProvider(LocalLayoutDirection provides direction) {
            ListItem(
                headlineContent = {
                    Text(ruling.question.readingDisplay(), style = MaterialTheme.typography.titleMedium, maxLines = 3)
                },
                modifier = Modifier.clickable { onOpen(ruling) }.testTag("$tag-${ruling.id.siteID}"),
            )
        }
    }
}

/** A labeled choice with a menu, like a SwiftUI `Picker` in a form. */
@Composable
private fun Picker(
    label: String,
    selected: String,
    options: List<Pair<String, String>>,
    onSelect: (String) -> Unit,
    tag: String,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        ListItem(
            headlineContent = { Text(label) },
            trailingContent = { Text(selected, color = MaterialTheme.colorScheme.primary) },
            modifier = Modifier.clickable { open = true }.testTag(tag),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.testTag("$tag-menu")) {
            for ((id, name) in options) {
                DropdownMenuItem(
                    text = { Text(name) },
                    onClick = {
                        open = false
                        onSelect(id)
                    },
                    modifier = Modifier.testTag("$tag-$id"),
                )
            }
        }
    }
}

/** Swift `RulingsDetailView`: the question and answer, authority, source and sections. */
@Composable
fun RulingDetailScreen(
    viewModel: RulingDetailViewModel,
    onOpen: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    val library by viewModel.library.state.collectAsStateWithLifecycle()
    val detail by viewModel.detail.collectAsStateWithLifecycle()
    val bookmark by viewModel.bookmark.collectAsStateWithLifecycle()
    val bookmarkFailed by viewModel.bookmarkFailed.collectAsStateWithLifecycle()
    val reading by viewModel.reading.collectAsStateWithLifecycle()
    var sizing by rememberSaveable { mutableStateOf(false) }
    val locale = currentLocale()
    val loaded = (detail as? Loadable.Loaded)?.value
    ScreenScaffold(
        stringResource(R.string.rulings),
        onBack = onBack,
        actions = {
            IconButton(onClick = { sizing = true }, Modifier.testTag("reading-size")) {
                Icon(Icons.Outlined.FormatSize, stringResource(R.string.text_size))
            }
            if (loaded != null) {
                IconButton(onClick = { viewModel.toggleBookmark(loaded) }, Modifier.testTag("rulings-bookmark")) {
                    Icon(
                        if (bookmark != null) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                        stringResource(if (bookmark != null) R.string.remove_bookmark else R.string.bookmark),
                    )
                }
            }
        },
    ) { padding ->
        if (library.status != RulingsStatus.Ready) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) { rulingsDownload(viewModel.library, library) }
            return@ScreenScaffold
        }
        when (val current = detail) {
            Loadable.Loading -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }

            Loadable.Failed -> {
                EmptyState(
                    stringResource(R.string.saved_passage_unavailable),
                    Modifier.padding(padding),
                    onAction = viewModel::retry,
                )
            }

            is Loadable.Loaded -> {
                val value = current.value
                if (value == null) {
                    EmptyState(
                        stringResource(R.string.saved_passage_unavailable),
                        Modifier.padding(padding),
                        onAction = viewModel::retry,
                    )
                } else {
                    RulingContent(value, reading.readingSizePercent, padding, onOpen)
                }
            }
        }
    }
    if (sizing) ReadingSizeSheet(reading.readingSizePercent, locale, viewModel::setSize) { sizing = false }
    if (bookmarkFailed) BookmarkFailedDialog(viewModel::dismissBookmarkFailure)
}

@Composable
private fun RulingContent(
    detail: RulingDetail,
    sizePercent: Int,
    padding: PaddingValues,
    onOpen: (Route) -> Unit,
) {
    val uri = LocalUriHandler.current
    val arabic = detail.ruling.id.language == "ar"
    val rightToLeft = detail.language?.rightToLeft ?: arabic
    val direction = if (rightToLeft) LayoutDirection.Rtl else LayoutDirection.Ltr
    val size = if (arabic) ReadingTextStyle.arabicSize(sizePercent) * 0.8f else ReadingTextStyle.bodySize(sizePercent)
    Box(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CompositionLocalProvider(LocalLayoutDirection provides direction) {
                Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text(
                        detail.ruling.question.readingDisplay(),
                        style =
                            MaterialTheme.typography.titleLarge.copy(
                                fontFamily = if (arabic) HadithFont else ReaderBodyFont,
                                fontSize = (size * 1.15f).sp,
                                lineHeight = (size * 1.6f).sp,
                                fontWeight = FontWeight.SemiBold,
                            ),
                        modifier = Modifier.fillMaxWidth().semantics { heading() }.testTag("rulings-question"),
                    )
                    if (detail.ruling.answer.isNotEmpty()) {
                        ReaderText(
                            StyledText(detail.ruling.answer),
                            block = "answer",
                            sizeSp = size,
                            rightToLeft = rightToLeft,
                            modifier = Modifier.fillMaxWidth().testTag("rulings-answer"),
                        )
                    }
                }
            }
            HorizontalDivider()
            ListItem(
                headlineContent = { Text(stringResource(R.string.religious_authority)) },
                trailingContent = { Text(detail.authorityName) },
            )
            detail.ruling.source?.let { source ->
                ListItem(
                    headlineContent = { Text(stringResource(R.string.source)) },
                    trailingContent = { Icon(Icons.AutoMirrored.Outlined.OpenInNew, null) },
                    modifier = Modifier.clickable { runCatching { uri.openUri(source) } }.testTag("rulings-source"),
                )
            }
            for (section in detail.sections) {
                CompositionLocalProvider(LocalLayoutDirection provides direction) {
                    ListItem(
                        headlineContent = { Text(section.title) },
                        leadingContent = { Icon(Icons.AutoMirrored.Outlined.Label, null) },
                        modifier =
                            Modifier
                                .clickable {
                                    onOpen(
                                        RulingSectionRoute(
                                            detail.ruling.id.authority,
                                            detail.ruling.id.language,
                                            section.id,
                                            section.title,
                                        ),
                                    )
                                }.testTag("rulings-section-${section.id}"),
                    )
                }
            }
        }
    }
}

/** Swift `RulingsSectionView`. */
@Composable
fun RulingSectionScreen(
    viewModel: RulingSectionViewModel,
    onOpen: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    val questions by viewModel.questions.collectAsStateWithLifecycle()
    ScreenScaffold(viewModel.route.title, onBack = onBack) { padding ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            val current = questions
            val language =
                (current as? Loadable.Loaded)?.value?.second
                    ?: RulingsLanguage(viewModel.route.language, "", viewModel.route.language == "ar")
            val rows =
                when (current) {
                    Loadable.Loading -> Loadable.Loading
                    Loadable.Failed -> Loadable.Failed
                    is Loadable.Loaded -> Loadable.Loaded(current.value.first)
                }
            rulingRows(rows, language, emptyMessage = false, viewModel::retry) { ruling ->
                onOpen(RulingDetailRoute(ruling.id.authority, ruling.id.language, ruling.id.siteID))
            }
        }
    }
}

/** Swift `RulingsSavedView`: bookmarked rulings, newest first. */
@Composable
fun RulingsSavedScreen(
    viewModel: RulingsSavedViewModel,
    onOpen: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    val bookmarks by viewModel.bookmarks.collectAsStateWithLifecycle()
    val unavailable by viewModel.unavailable.collectAsStateWithLifecycle()
    ScreenScaffold(stringResource(R.string.saved), onBack = onBack) { padding ->
        when {
            unavailable -> {
                EmptyState(
                    stringResource(R.string.saved_unavailable),
                    Modifier.padding(padding),
                    message = stringResource(R.string.your_saved_data_could_not_be_opened_please_try_a),
                    onAction = { viewModel.retry() },
                )
            }

            bookmarks.isEmpty() -> {
                EmptyState(
                    stringResource(R.string.no_bookmarks_yet),
                    Modifier.padding(padding),
                    message = stringResource(R.string.bookmark_a_ruling_to_find_it_again_in_saved),
                )
            }

            else -> {
                LazyColumn(Modifier.fillMaxSize().testTag("saved-list"), contentPadding = padding) {
                    items(bookmarks.sortedByDescending(ReadingBookmark::modifiedAt), key = { it.id }) { bookmark ->
                        val ruling = bookmark.ruling ?: return@items
                        ListItem(
                            overlineContent = { Text(bookmark.reference) },
                            headlineContent = { Text(bookmark.excerpt.readingDisplay(), maxLines = 4) },
                            trailingContent = {
                                IconButton(onClick = { viewModel.remove(bookmark) }) {
                                    Icon(Icons.Outlined.BookmarkRemove, stringResource(R.string.remove_bookmark))
                                }
                            },
                            modifier =
                                Modifier
                                    .clickable {
                                        onOpen(
                                            RulingDetailRoute(ruling.authority, ruling.language, ruling.siteID),
                                        )
                                    }.testTag("saved-ruling-${ruling.siteID}"),
                        )
                    }
                }
            }
        }
    }
}

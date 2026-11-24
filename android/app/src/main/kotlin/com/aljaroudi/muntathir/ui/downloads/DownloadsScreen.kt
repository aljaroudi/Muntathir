package com.aljaroudi.muntathir.ui.downloads

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.hadith.LibraryState
import com.aljaroudi.muntathir.core.hadith.LibraryStatus
import com.aljaroudi.muntathir.core.quran.DownloadState
import com.aljaroudi.muntathir.core.quran.QuranTranslation
import com.aljaroudi.muntathir.core.quran.TranslationState
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.library.ContentLibraries
import com.aljaroudi.muntathir.data.library.ContentLibrary
import com.aljaroudi.muntathir.data.library.RulingsLibrary
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.quran.ConfirmationPrompt
import com.aljaroudi.muntathir.ui.quran.languageName
import com.aljaroudi.muntathir.ui.rulings.rulingsDownload
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class DownloadsViewModel
    @Inject
    constructor(
        val translations: QuranTranslations,
        val libraries: ContentLibraries,
        val rulings: RulingsLibrary,
        val dictionary: com.aljaroudi.muntathir.ui.dictionary.DictionaryLibrary,
    ) : ViewModel()

/** Swift `DownloadsSettingsView`: Hadith (with its books), Supplications and Quran translations. */
@Composable
fun DownloadsScreen(
    viewModel: DownloadsViewModel,
    onBack: (() -> Unit)?,
) {
    val translations = viewModel.translations
    val state by translations.state.collectAsStateWithLifecycle()
    var requested by rememberSaveable { mutableStateOf<String?>(null) }
    var previous by remember { mutableStateOf(state.downloadState) }
    val activity = LocalActivity.current
    LaunchedEffect(Unit) { translations.refresh() }
    LaunchedEffect(state.downloadState) {
        if (state.downloadState != previous && state.downloadState == DownloadState.Idle) requested = null
        previous = state.downloadState
    }
    val hadith = viewModel.libraries.hadith
    val supplications = viewModel.libraries.supplications
    val hadithState by hadith.state.collectAsStateWithLifecycle()
    val supplicationsState by supplications.state.collectAsStateWithLifecycle()
    val rulingsState by viewModel.rulings.state.collectAsStateWithLifecycle()
    var booksExpanded by rememberSaveable { mutableStateOf(false) }
    var requestedBook by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(hadithState.status) {
        if (hadithState.status == LibraryStatus.Ready ||
            hadithState.status == LibraryStatus.Missing
        ) {
            requestedBook = null
        }
    }
    ScreenScaffold(stringResource(R.string.downloads), onBack = onBack) { padding ->
        LazyColumn(Modifier.fillMaxSize().testTag("downloads"), contentPadding = padding) {
            item {
                com.aljaroudi.muntathir.ui.dictionary
                    .DictionaryPack(viewModel.dictionary, manage = true)
            }
            libraryPack(
                library = hadith,
                state = hadithState,
                title = R.string.hadith,
                booksExpanded = booksExpanded,
                onExpand = { booksExpanded = !booksExpanded },
                requestedBook = requestedBook,
                onRestoreBook = { book ->
                    requestedBook = book
                    hadith.download(book)
                },
                onConfirm = { activity?.let(hadith::confirm) },
            )
            libraryPack(
                library = supplications,
                state = supplicationsState,
                title = R.string.supplications,
                booksExpanded = false,
                onExpand = null,
                requestedBook = null,
                onRestoreBook = {},
                onConfirm = { activity?.let(supplications::confirm) },
            )
            item(key = "rulings-header") { SectionHeader(stringResource(R.string.rulings)) }
            rulingsDownload(viewModel.rulings, rulingsState)
            quranTranslations(
                state = state,
                requested = requested,
                onDownload = { id ->
                    requested = id
                    translations.download(id)
                },
                onRemove = translations::remove,
                onConfirm = { activity?.let(translations::confirm) },
            )
        }
    }
    if (state.storageError) {
        AlertDialog(
            onDismissRequest = translations::clearStorageError,
            title = { Text(stringResource(R.string.unable_to_finish_storage_cleanup)) },
            text = { Text(stringResource(R.string.some_files_remain_on_this_device_please_try_agai)) },
            confirmButton = {
                TextButton(onClick = {
                    translations.clearStorageError()
                    translations.refresh()
                }) { Text(stringResource(R.string.try_again)) }
            },
            dismissButton = {
                TextButton(
                    onClick = translations::clearStorageError,
                ) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

/** Swift `HadithDownloadsSection`: the whole pack, then (for Hadith) each book with remove and restore. */
private fun LazyListScope.libraryPack(
    library: ContentLibrary,
    state: LibraryState,
    @androidx.annotation.StringRes title: Int,
    booksExpanded: Boolean,
    onExpand: (() -> Unit)?,
    requestedBook: String?,
    onRestoreBook: (String) -> Unit,
    onConfirm: () -> Unit,
) {
    val pack = library.pack.packName
    val idle = !state.busy && !state.isDownloading
    val failed = state.status == LibraryStatus.Failed || state.status == LibraryStatus.Incompatible
    item(key = "$pack-header") { SectionHeader(stringResource(title)) }
    if (!booksExpanded || requestedBook == null) item(key = "$pack-status") { LibraryStatusRow(state, onConfirm) }
    if (state.hasLocalAsset) {
        item(key = "$pack-size") {
            val locale = currentLocale()
            ListItem(
                headlineContent = { Text(stringResource(R.string.total_size)) },
                trailingContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(formatBytes(state.installedBytes, locale))
                        IconButton(
                            onClick = library::removeAll,
                            enabled = idle,
                            modifier = Modifier.testTag("downloads-remove-$pack"),
                        ) { Icon(Icons.Outlined.Delete, stringResource(R.string.remove_download)) }
                    }
                },
                modifier = Modifier.testTag("downloads-size-$pack"),
            )
        }
    }
    item(key = "$pack-action") {
        when {
            !state.isDownloading && (state.status == LibraryStatus.Checking || state.busy) -> {
                Box(
                    Modifier.fillMaxWidth().padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }
            }

            requestedBook == null && failed -> {
                Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                    AssetDownloadButton(pack, retry = true, onClick = { library.download() })
                }
            }

            !state.isDownloading && !state.hasLocalAsset -> {
                Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                    AssetDownloadButton(
                        pack,
                        retry = false,
                        onClick = { library.download() },
                        modifier = Modifier.testTag("downloads-get-$pack"),
                    )
                }
            }
        }
    }
    if (onExpand == null || state.books.isEmpty()) return
    item(key = "$pack-books") {
        ListItem(
            headlineContent = { Text(stringResource(R.string.books)) },
            trailingContent = {
                Icon(if (booksExpanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null)
            },
            modifier = Modifier.clickable(onClick = onExpand).testTag("downloads-books-$pack"),
        )
    }
    if (!booksExpanded) return
    items(state.books, key = { "$pack-book-${it.id}" }) { book ->
        val locale = currentLocale()
        val requested = requestedBook == book.id
        Column {
            ListItem(
                headlineContent = { Text(book.title(locale)) },
                trailingContent = {
                    when {
                        book.installed -> {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                book.estimatedBytes?.let {
                                    Text(
                                        "≈ " + formatBytes(it, locale),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                IconButton(
                                    onClick = { library.remove(book.id) },
                                    enabled = idle,
                                    modifier = Modifier.testTag("downloads-remove-book-${book.id}"),
                                ) { Icon(Icons.Outlined.Delete, stringResource(R.string.remove_download)) }
                            }
                        }

                        requested && state.isDownloading -> {}

                        else -> {
                            val retry = requested && failed
                            IconButton(
                                onClick = { onRestoreBook(book.id) },
                                enabled = idle,
                                modifier = Modifier.testTag("downloads-get-book-${book.id}"),
                            ) {
                                Icon(
                                    if (retry) Icons.Outlined.Refresh else Icons.Outlined.Download,
                                    if (retry) {
                                        stringResource(
                                            R.string.try_again,
                                        )
                                    } else {
                                        stringResource(R.string.download_x, book.title(locale))
                                    },
                                )
                            }
                        }
                    }
                },
            )
            if (requested) LibraryStatusRow(state, onConfirm)
        }
    }
    if (state.books.any { !it.installed }) {
        item(key = "$pack-restore-note") {
            Text(
                stringResource(R.string.restoring_a_book_downloads_the_full_library_temp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun LibraryStatusRow(
    state: LibraryState,
    onConfirm: () -> Unit,
) {
    when {
        state.isDownloading -> {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                AssetDownloadProgress(state.progress, state.status == LibraryStatus.Installing, state.preparingDownload)
                ConfirmationPrompt(state.needsConfirmation, onConfirm)
            }
        }

        state.status == LibraryStatus.Failed || state.status == LibraryStatus.Incompatible -> {
            Text(
                stringResource(R.string.unable_to_download_please_try_again),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}

private fun LazyListScope.quranTranslations(
    state: TranslationState,
    requested: String?,
    onDownload: (String) -> Unit,
    onRemove: (List<String>) -> Unit,
    onConfirm: () -> Unit,
) {
    val idle = !state.busy && !state.isDownloading
    item(key = "translations-header") { SectionHeader(stringResource(R.string.quran_translations)) }
    if (requested == null) item(key = "translations-status") { Status(state, onConfirm) }
    if (state.installedSizes.isNotEmpty()) {
        item(key = "translations-size") {
            val locale = currentLocale()
            ListItem(
                headlineContent = { Text(stringResource(R.string.total_size)) },
                trailingContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(formatBytes(state.installedSizes.values.sum(), locale))
                        IconButton(
                            onClick = { onRemove(QuranTranslation.downloadable.map { it.id }) },
                            enabled = idle,
                            modifier = Modifier.testTag("downloads-remove-translations"),
                        ) { Icon(Icons.Outlined.Delete, stringResource(R.string.remove_all_translations)) }
                    }
                },
                modifier = Modifier.testTag("downloads-size-translations"),
            )
        }
    }
    item(key = "translations-en") {
        ListItem(
            headlineContent = { Text(stringResource(R.string.english)) },
            trailingContent = { Text(stringResource(R.string.included)) },
            modifier = Modifier.testTag("downloads-bundled-en"),
        )
    }
    items(QuranTranslation.downloadable, key = { "translation-${it.id}" }) { translation ->
        Column {
            TranslationRow(translation, state, requested, idle, onDownload, onRemove)
            if (requested == translation.id) Status(state, onConfirm)
        }
    }
}

@Composable
private fun TranslationRow(
    translation: QuranTranslation,
    state: TranslationState,
    requested: String?,
    idle: Boolean,
    onDownload: (String) -> Unit,
    onRemove: (List<String>) -> Unit,
) {
    val locale: Locale = currentLocale()
    val size = state.installedSizes[translation.id]
    ListItem(
        headlineContent = { Text(translation.languageName(locale)) },
        supportingContent = { Text(translation.translator) },
        trailingContent = {
            when {
                size != null -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(formatBytes(size, locale), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        IconButton(
                            onClick = { onRemove(listOf(translation.id)) },
                            enabled = idle,
                            modifier = Modifier.testTag("downloads-remove-${translation.id}"),
                        ) { Icon(Icons.Outlined.Delete, stringResource(R.string.remove_download)) }
                    }
                }

                // The status row below shows this download's progress.
                requested == translation.id && state.isDownloading -> {}

                else -> {
                    val failed = state.downloadState == DownloadState.Failed
                    IconButton(
                        onClick = { onDownload(translation.id) },
                        enabled = idle,
                        modifier = Modifier.testTag("downloads-get-${translation.id}"),
                    ) {
                        Icon(
                            if (failed) Icons.Outlined.Refresh else Icons.Outlined.Download,
                            stringResource(if (failed) R.string.try_again else R.string.download),
                        )
                    }
                }
            }
        },
    )
}

/** Progress while downloading, or the failure message. */
@Composable
private fun Status(
    state: TranslationState,
    onConfirm: () -> Unit,
) {
    when {
        state.isDownloading -> {
            Column(
                Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                AssetDownloadProgress(state.progress, state.downloadState == DownloadState.Installing, state.preparing)
                ConfirmationPrompt(state.needsConfirmation, onConfirm)
            }
        }

        state.downloadState == DownloadState.Failed -> {
            Text(
                stringResource(R.string.unable_to_download_please_try_again),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}

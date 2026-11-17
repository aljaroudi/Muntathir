package com.aljaroudi.muntathir.ui.hadith

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.hadith.LibraryState
import com.aljaroudi.muntathir.core.hadith.LibraryStatus
import com.aljaroudi.muntathir.data.library.ContentLibrary
import com.aljaroudi.muntathir.ui.downloads.AssetDownloadButton
import com.aljaroudi.muntathir.ui.downloads.AssetDownloadProgress
import com.aljaroudi.muntathir.ui.quran.ConfirmationPrompt

/**
 * Swift `HadithLibraryView`: [content] once the library is ready (rebuilt when it changes), otherwise its
 * download, progress or failure.
 */
@Composable
fun LibraryGate(
    library: ContentLibrary,
    supplications: Boolean,
    padding: PaddingValues,
    content: @Composable (revision: Int) -> Unit,
) {
    val state by library.state.collectAsStateWithLifecycle()
    if (state.status == LibraryStatus.Ready) {
        content(state.revision)
    } else {
        LibraryUnavailable(state, supplications, library, Modifier.padding(padding))
    }
    if (state.storageError) {
        AlertDialog(
            onDismissRequest = library::clearStorageError,
            title = { Text(stringResource(R.string.unable_to_finish_storage_cleanup)) },
            text = {
                Text(
                    state.storageErrorMessage.ifBlank {
                        stringResource(R.string.some_files_remain_on_this_device_please_try_agai)
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = library::clearStorageError) { Text(stringResource(R.string.ok)) }
            },
        )
    }
}

@Composable
private fun LibraryUnavailable(
    state: LibraryState,
    supplications: Boolean,
    library: ContentLibrary,
    modifier: Modifier,
) {
    val activity = LocalActivity.current
    val message =
        when (state.status) {
            LibraryStatus.Checking -> {
                if (supplications) R.string.checking_supplications_download else R.string.checking_hadith_download
            }

            LibraryStatus.Downloading, LibraryStatus.Installing -> {
                null
            }

            LibraryStatus.Failed -> {
                if (supplications) {
                    R.string.unable_to_download_supplications_check_your_conn
                } else {
                    R.string.unable_to_download_hadith_check_your_connection
                }
            }

            LibraryStatus.Incompatible -> {
                R.string.this_download_needs_an_update
            }

            else -> {
                if (supplications) {
                    R.string.read_and_search_supplications_offline
                } else {
                    R.string.read_and_search_hadith_offline
                }
            }
        }
    Column(
        modifier.fillMaxSize().padding(24.dp).testTag(if (supplications) "supplications-gate" else "hadith-gate"),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            stringResource(if (supplications) R.string.supplications else R.string.hadith),
            style = MaterialTheme.typography.titleLarge,
        )
        message?.let {
            Text(
                stringResource(it),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.widthIn(max = 400.dp),
            )
        }
        when {
            state.isDownloading -> {
                AssetDownloadProgress(state.progress, state.status == LibraryStatus.Installing, state.preparingDownload)
                ConfirmationPrompt(state.needsConfirmation) { activity?.let(library::confirm) }
            }

            state.status == LibraryStatus.Checking -> {
                CircularProgressIndicator()
            }

            else -> {
                AssetDownloadButton(
                    pack = library.pack.packName,
                    retry = state.status != LibraryStatus.Missing,
                    onClick = { library.download() },
                    enabled = !state.busy,
                    modifier = Modifier.testTag(if (supplications) "supplications-download" else "hadith-download"),
                )
            }
        }
    }
}

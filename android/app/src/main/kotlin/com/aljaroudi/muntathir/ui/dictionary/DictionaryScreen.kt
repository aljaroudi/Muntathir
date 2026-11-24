package com.aljaroudi.muntathir.ui.dictionary

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.rulings.RulingsStatus
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.downloads.AssetDownloadButton
import com.aljaroudi.muntathir.ui.downloads.AssetDownloadProgress
import com.aljaroudi.muntathir.ui.quran.ConfirmationPrompt
import com.aljaroudi.muntathir.ui.reader.ReaderText
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import dagger.hilt.android.AndroidEntryPoint
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import javax.inject.Inject

@HiltViewModel
class DictionaryViewModel
    @Inject
    constructor(
        val library: DictionaryLibrary,
    ) : ViewModel()

@AndroidEntryPoint
class DictionaryActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val selected = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString().orEmpty()
        setContent { MuntathirTheme { DictionaryScreen(initial = selected, onBack = ::finish) } }
    }
}

@Composable
fun DictionaryPack(
    library: DictionaryLibrary,
    manage: Boolean = false,
) {
    val state by library.state.collectAsStateWithLifecycle()
    val activity = LocalActivity.current
    Column(Modifier.padding(12.dp)) {
        if (manage) Text(stringResource(R.string.arabic_dictionary), style = MaterialTheme.typography.titleMedium)
        when (state.status) {
            RulingsStatus.Ready -> {
                if (manage) {
                    TextButton(onClick = library::remove) { Text(stringResource(R.string.remove_download)) }
                } else {
                    Unit
                }
            }

            RulingsStatus.Downloading -> {
                AssetDownloadProgress(state.progress, installing = false, preparing = state.progress == null)
                ConfirmationPrompt(state.needsConfirmation) { activity?.let(library::confirm) }
            }

            RulingsStatus.Checking -> {
                CircularProgressIndicator()
            }

            else -> {
                AssetDownloadButton(
                    "lexicon",
                    state.status != RulingsStatus.Missing,
                    library::download,
                    enabled = !state.busy,
                )
            }
        }
        if (state.storageError) Text(stringResource(R.string.unable_to_finish_storage_cleanup))
    }
}

private val sources =
    listOf(
        "القاموس المحيط",
        "الفائق في غريب الحديث",
        "الصحاح",
        "النهاية في غريب الحديث والأثر",
        "لسان العرب",
        "تهذيب اللغة",
    )

@Composable
fun DictionaryScreen(
    initial: String = "",
    onBack: (() -> Unit)?,
    model: DictionaryViewModel = hiltViewModel(),
) {
    val library = model.library
    val state by library.state.collectAsStateWithLifecycle()
    val history by library.history.collectAsStateWithLifecycle()
    val bookmarks by library.bookmarks.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var query by rememberSaveable { mutableStateOf(initial) }
    var submitted by rememberSaveable { mutableStateOf(initial) }
    var source by rememberSaveable { mutableStateOf<Int?>(null) }
    var root by rememberSaveable { mutableStateOf<String?>(null) }
    var recorded by rememberSaveable { mutableStateOf(false) }
    var matches by remember { mutableStateOf(DictionaryReader.Matches()) }
    var definitions by remember { mutableStateOf(emptyList<Pair<Int, String>>()) }
    var failed by remember { mutableStateOf(false) }

    fun visit(
        value: String,
        entry: Boolean,
        matchSource: Int? = null,
    ) {
        source = matchSource
        if (value.isBlank()) return
        library.visit(DictionaryRecord(value, entry))
        if (entry) {
            root = value
        } else {
            root = null
            query = value
            submitted = value
            tab = 0
        }
    }
    LaunchedEffect(Unit) {
        if (!recorded && initial.isNotBlank()) library.visit(DictionaryRecord(initial, false))
        recorded = true
        library.refresh()
    }
    LaunchedEffect(submitted, root, state.status, state.revision) {
        matches = DictionaryReader.Matches()
        definitions = emptyList()
        failed = false
        if (state.status == RulingsStatus.Ready) {
            try {
                val selected = root
                if (selected != null) {
                    definitions = library.reader.entry(selected)
                } else if (submitted.isNotBlank()) {
                    matches = library.reader.search(submitted)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                failed = true
            }
        }
    }
    BackHandler(root != null) { root = null }
    ScreenScaffold(
        root ?: stringResource(R.string.arabic_dictionary),
        onBack =
            if (root ==
                null
            ) {
                onBack
            } else {
                ({ root = null })
            },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp)) {
            val selected = root
            if (selected != null) {
                item {
                    TextButton(onClick = { library.bookmark(selected) }) {
                        Text(stringResource(if (selected in bookmarks) R.string.remove_bookmark else R.string.bookmark))
                    }
                }
                items(definitions.sortedBy { if (it.first == source) -1 else it.first }) { (source, body) ->
                    Text(sources[source], style = MaterialTheme.typography.titleMedium)
                    ReaderText(StyledText(body), "", 20f, rightToLeft = true)
                }
            } else {
                item {
                    Row {
                        listOf(R.string.search, R.string.dictionary_history, R.string.bookmarks).forEachIndexed {
                            index,
                            label,
                            ->
                            FilterChip(
                                selected = tab == index,
                                onClick = { tab = index },
                                label = { Text(stringResource(label)) },
                            )
                        }
                    }
                }
                when (tab) {
                    1 -> {
                        items(history) { row ->
                            Row {
                                TextButton(onClick = { visit(row.value, row.entry) }, modifier = Modifier.weight(1f)) {
                                    Text(
                                        stringResource(if (row.entry) R.string.dictionary_entry else R.string.search) +
                                            " · " +
                                            row.value,
                                    )
                                }
                                TextButton(
                                    onClick = { library.setHistory(history - row) },
                                ) { Text(stringResource(R.string.dictionary_delete)) }
                            }
                        }
                        if (history.isNotEmpty()) {
                            item {
                                TextButton(
                                    onClick = { library.setHistory(emptyList()) },
                                ) { Text(stringResource(R.string.clear_history)) }
                            }
                        }
                    }

                    2 -> {
                        items(bookmarks) { word -> TextButton(onClick = { visit(word, true) }) { Text(word) } }
                    }

                    else -> {
                        item {
                            OutlinedTextField(
                                query,
                                { query = it },
                                label = { Text(stringResource(R.string.word_or_phrase)) },
                                singleLine = true,
                            )
                            Button(onClick = { visit(query, false) }) { Text(stringResource(R.string.search)) }
                        }
                        if (submitted.isNotBlank() && state.status == RulingsStatus.Ready) {
                            item { Text(submitted, style = MaterialTheme.typography.titleMedium) }
                            if (matches.roots.isEmpty()) item { Text(stringResource(R.string.no_root_found)) }
                            items(matches.roots) { word -> TextButton(onClick = { visit(word, true) }) { Text(word) } }
                            val words = submitted.trim().split(Regex("\\s+"))
                            if (words.size >
                                1
                            ) {
                                items(words) { word -> TextButton(onClick = { visit(word, false) }) { Text(word) } }
                            }
                            item {
                                Text(
                                    stringResource(R.string.dictionary_passages),
                                    style = MaterialTheme.typography.titleMedium,
                                )
                            }
                            items(matches.passages) { match ->
                                TextButton(onClick = { visit(match.root, true, match.source) }) {
                                    Column {
                                        Text(match.root + " · " + sources[match.source])
                                        Text(match.preview, maxLines = 2)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (failed) item { Text(stringResource(R.string.dictionary_read_error)) }
            if (state.status != RulingsStatus.Ready) item { DictionaryPack(library) }
        }
    }
}

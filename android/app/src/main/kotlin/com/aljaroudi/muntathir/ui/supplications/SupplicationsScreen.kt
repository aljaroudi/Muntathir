package com.aljaroudi.muntathir.ui.supplications

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.hadith.Hadith
import com.aljaroudi.muntathir.core.hadith.HadithDatabaseException
import com.aljaroudi.muntathir.core.hadith.LibraryStatus
import com.aljaroudi.muntathir.core.search.SemanticSearchResult
import com.aljaroudi.muntathir.core.text.HadithText
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.core.text.SearchMatch
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.data.library.ContentLibraries
import com.aljaroudi.muntathir.search.SmartSearch
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SearchField
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.hadith.LibraryGate
import com.aljaroudi.muntathir.ui.hadith.SupplicationTranslationDialog
import com.aljaroudi.muntathir.ui.hadith.hadithArabicStyle
import com.aljaroudi.muntathir.ui.navigation.HadithDetailRoute
import com.aljaroudi.muntathir.ui.navigation.HadithRoute
import com.aljaroudi.muntathir.ui.navigation.HadithSavedRoute
import com.aljaroudi.muntathir.ui.quran.ReadingTimeHint
import com.aljaroudi.muntathir.ui.quran.recentSearches
import com.aljaroudi.muntathir.ui.reader.toAnnotatedString
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlin.time.Duration.Companion.milliseconds

sealed interface SupplicationsState {
    data object Loading : SupplicationsState

    data object Failed : SupplicationsState

    /** The download is too old for this app (Swift "This download needs an update"). */
    data object NeedsUpdate : SupplicationsState

    data class Loaded(
        val prayers: List<Hadith>,
        val languages: List<String>,
    ) : SupplicationsState
}

/** Swift `SupplicationsView`: every supplication by collection, searched by title, text or translation. */
@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class SupplicationsViewModel
    @Inject
    constructor(
        libraries: ContentLibraries,
        private val settings: ReadingSettings,
        private val history: SearchHistoryStore,
        private val smartSearch: SmartSearch,
    ) : ViewModel() {
        val library = libraries.supplications
        private val reader = library.reader
        val reading = settings.state

        val query = MutableStateFlow("")
        val submitted = MutableStateFlow("")
        private val retry = MutableStateFlow(0)

        val recent: StateFlow<List<String>> =
            history.state
                .map { it.queries(SearchArea.Supplications) }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val state: StateFlow<SupplicationsState> =
            combine(
                combine(query, submitted) { text, sent -> text to (text == sent) },
                settings.state.map { it.supplicationTranslation }.distinctUntilChanged(),
                library.state.map { it.revision to it.status }.distinctUntilChanged(),
                retry,
            ) { query, translation, (_, status), _ -> Triple(query, translation, status) }
                .transformLatest { (search, translation, status) ->
                    val (query, online) = search
                    if (status != LibraryStatus.Ready) return@transformLatest
                    // Swift debounces typing by 150 ms.
                    if (query.isNotEmpty()) delay(150.milliseconds)
                    emit(
                        try {
                            val languages = reader.translationLanguages()
                            SupplicationsState.Loaded(
                                searchPrayers(query, translation, online),
                                languages,
                            )
                        } catch (cancellation: CancellationException) {
                            throw cancellation
                        } catch (_: HadithDatabaseException.Incompatible) {
                            SupplicationsState.NeedsUpdate
                        } catch (_: Exception) {
                            library.invalidateValidation()
                            SupplicationsState.Failed
                        },
                    )
                }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SupplicationsState.Loading)

        private suspend fun searchPrayers(
            query: String,
            translation: String,
            online: Boolean,
        ): List<Hadith> {
            val languages = QuranTranslations.preferredLanguages()
            if (online && query.isNotEmpty()) {
                val remote =
                    smartSearch.results(query, "dua") { hits ->
                        if (hits.isEmpty()) return@results emptyList()
                        val locators =
                            hits.mapNotNull {
                                (it.reference as? SemanticSearchResult.Reference.Dua)?.locator
                            }
                        reader.supplications(query, translation, languages, locators)
                    }
                if (remote != null) return remote
            }
            return reader.supplications(query, translation, languages)
        }

        fun submit() {
            submitted.value = query.value
            record()
        }

        fun search(value: String) {
            if (submitted.value != value) submitted.value = ""
            query.value = value
        }

        fun record() = history.record(query.value, SearchArea.Supplications)

        fun removeRecent(value: String) = history.remove(value, SearchArea.Supplications)

        fun clearRecent() = history.clear(SearchArea.Supplications)

        fun setTranslation(value: String) =
            viewModelScope.launch { settings.update { it.copy(supplicationTranslation = value) } }

        fun retry() {
            library.refresh()
            retry.value++
        }
    }

@Composable
fun SupplicationsScreen(
    viewModel: SupplicationsViewModel,
    onOpen: (HadithRoute) -> Unit,
    onBack: (() -> Unit)?,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val query by viewModel.query.collectAsStateWithLifecycle()
    val submitted by viewModel.submitted.collectAsStateWithLifecycle()
    val recent by viewModel.recent.collectAsStateWithLifecycle()
    val reading by viewModel.reading.collectAsStateWithLifecycle()
    var focused by remember { mutableStateOf(false) }
    var picking by rememberSaveable { mutableStateOf(false) }
    val locale = currentLocale()
    ScreenScaffold(
        stringResource(R.string.supplications),
        onBack = onBack,
        actions = {
            IconButton(onClick = { picking = true }, Modifier.testTag("supplication-reading-options")) {
                Icon(Icons.Outlined.Translate, stringResource(R.string.translation))
            }
        },
    ) { padding ->
        LibraryGate(viewModel.library, supplications = true, padding = padding) {
            LazyColumn(Modifier.fillMaxSize().testTag("supplications-list"), contentPadding = padding) {
                item(key = "search") {
                    SearchField(
                        query = query,
                        onQuery = viewModel::search,
                        onSubmit = viewModel::submit,
                        placeholder = stringResource(R.string.search_supplications),
                        onFocusChange = { focused = it },
                    )
                }
                if (focused && query.isBlank()) {
                    recentSearches(recent, {
                        viewModel.search(it)
                        viewModel.submit()
                    }, viewModel::removeRecent, viewModel::clearRecent)
                }
                if (query.isBlank()) {
                    item(key = "saved") {
                        ListItem(
                            headlineContent = { Text(stringResource(R.string.saved)) },
                            leadingContent = { Icon(Icons.Outlined.BookmarkBorder, null) },
                            modifier =
                                Modifier
                                    .clickable { onOpen(HadithSavedRoute(supplications = true)) }
                                    .testTag("supplication-saved"),
                        )
                    }
                }
                when (val current = state) {
                    SupplicationsState.Loading -> {
                        item(key = "loading") { LoadingState(stringResource(R.string.loading_hadith)) }
                    }

                    SupplicationsState.NeedsUpdate -> {
                        item(key = "update") { EmptyState(stringResource(R.string.this_download_needs_an_update)) }
                    }

                    SupplicationsState.Failed -> {
                        item(key = "failed") {
                            EmptyState(
                                stringResource(R.string.unable_to_load_supplications),
                                onAction = viewModel::retry,
                            )
                        }
                    }

                    is SupplicationsState.Loaded -> {
                        if (current.prayers.isEmpty()) {
                            item(key = "empty") {
                                EmptyState(
                                    stringResource(R.string.no_supplications_found),
                                    Modifier.testTag("supplications-empty"),
                                )
                            }
                        }
                        for (collection in if (submitted.isEmpty()) {
                            Hadith.SUPPLICATION_COLLECTION_IDS
                        } else {
                            listOf(
                                "results",
                            )
                        }) {
                            val prayers =
                                if (submitted.isEmpty()) {
                                    current.prayers.filter {
                                        it.collectionID ==
                                            collection
                                    }
                                } else {
                                    current.prayers
                                }
                            if (prayers.isEmpty()) continue
                            if (submitted.isEmpty()) {
                                item(
                                    key = "header-$collection",
                                ) { SectionHeader(prayers.first().chapter.bookTitle(locale)) }
                            }
                            items(prayers, key = { "prayer-${it.id}" }) { prayer ->
                                SupplicationRow(prayer, query) {
                                    viewModel.record()
                                    onOpen(HadithDetailRoute(prayer.id, query.trim(), supplication = true))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    val languages = (state as? SupplicationsState.Loaded)?.languages
    if (picking && languages != null) {
        SupplicationTranslationDialog(
            languages = languages,
            selection = reading.supplicationTranslation,
            onSelect = {
                viewModel.setTranslation(it)
                picking = false
            },
            onDismiss = { picking = false },
        )
    }
}

@Composable
private fun SupplicationRow(
    prayer: Hadith,
    query: String,
    onClick: () -> Unit,
) {
    val locale = currentLocale()
    val searching = query.isNotBlank()
    val tag =
        if (prayer.collectionID == Hadith.SUPPLICATION_COLLECTION_ID) {
            "supplication-${prayer.number - 1}"
        } else {
            "supplication-${prayer.source?.key ?: prayer.id}"
        }
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .testTag(tag),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(prayer.chapter.chapterTitle(locale), style = MaterialTheme.typography.titleMedium)
        if (!searching) {
            ReadingTimeHint(prayer.readingWords, locale)
        } else {
            val translated =
                prayer.translation?.let {
                    HadithText.flattened(HadithText.highlighted(it.text, QuranSearchText.queryTerms(query)))
                } ?: StyledText("")
            val blocks = listOf(prayer.arabicPreview ?: StyledText(prayer.arabic), translated)
            for (index in SearchMatch.visibleBlocks(blocks, preferred = if (locale.language == "ar") 0 else 1)) {
                val rightToLeft = index == 0 || prayer.translation?.isRightToLeft == true
                CompositionLocalProvider(
                    LocalLayoutDirection provides if (rightToLeft) LayoutDirection.Rtl else LayoutDirection.Ltr,
                ) {
                    Text(
                        SearchMatch.preview(blocks[index], compact = true).toAnnotatedString(),
                        style = if (index == 0) hadithArabicStyle() else MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
    }
}

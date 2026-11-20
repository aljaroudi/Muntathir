package com.aljaroudi.muntathir.ui.rulings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.hadith.HadithDatabaseException
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.highlight.ReadingBookmark
import com.aljaroudi.muntathir.core.highlight.RulingID
import com.aljaroudi.muntathir.core.rulings.Ruling
import com.aljaroudi.muntathir.core.rulings.RulingsAuthority
import com.aljaroudi.muntathir.core.rulings.RulingsLanguage
import com.aljaroudi.muntathir.core.rulings.RulingsReader
import com.aljaroudi.muntathir.core.rulings.RulingsSection
import com.aljaroudi.muntathir.core.rulings.RulingsStatus
import com.aljaroudi.muntathir.core.search.SemanticSearchResult
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.data.library.RulingsLibrary
import com.aljaroudi.muntathir.search.SmartSearch
import com.aljaroudi.muntathir.ui.navigation.RulingDetailRoute
import com.aljaroudi.muntathir.ui.navigation.RulingSectionRoute
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.launch
import java.util.Locale
import javax.inject.Inject
import kotlin.time.Duration.Companion.milliseconds

/** Loading, failed, or loaded [T]. */
sealed interface Loadable<out T> {
    data object Loading : Loadable<Nothing>

    data object Failed : Loadable<Nothing>

    data class Loaded<T>(
        val value: T,
    ) : Loadable<T>
}

/** The pickers' choices: every authority, and the chosen authority's languages and language. */
data class RulingsScope(
    val authorities: List<RulingsAuthority>,
    val authority: String,
    val languages: List<RulingsLanguage>,
    val language: RulingsLanguage?,
) {
    fun authorityName(locale: Locale) = authorities.firstOrNull { it.id == authority }?.name(locale) ?: authority
}

/** Runs [load] while the pack is ready, again on each [retry] and revision; failures become [Loadable.Failed]. */
@OptIn(ExperimentalCoroutinesApi::class)
private fun <K, T> Flow<K>.loading(
    library: RulingsLibrary,
    retry: Flow<Int>,
    delayFor: (K) -> Long = { 0 },
    load: suspend (K) -> T,
): Flow<Loadable<T>> =
    combine(this, library.state.map { it.revision to it.status }.distinctUntilChanged(), retry) { key, (_, status), _ ->
        key to status
    }.filter { it.second == RulingsStatus.Ready }
        .transformLatest { (key, _) ->
            emit(Loadable.Loading)
            delay(delayFor(key).milliseconds)
            emit(
                try {
                    Loadable.Loaded(load(key))
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Exception) {
                    Loadable.Failed
                },
            )
        }

/** Swift `RulingsBrowser`: authority and language pickers, then questions (a random sample, or search results). */
@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class RulingsViewModel
    @Inject
    constructor(
        val library: RulingsLibrary,
        private val settings: ReadingSettings,
        private val history: SearchHistoryStore,
        private val smartSearch: SmartSearch,
    ) : ViewModel() {
        private val reader: RulingsReader get() = library.reader
        val query = MutableStateFlow("")

        private val submitted = MutableStateFlow("")
        private val retry = MutableStateFlow(0)

        val recent: StateFlow<List<String>> =
            history.state
                .map { it.queries(SearchArea.Rulings) }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val scope: StateFlow<Loadable<RulingsScope>> =
            settings.state
                .map { it.rulingsAuthority to it.rulingsLanguages[it.rulingsAuthority] }
                .distinctUntilChanged()
                .loading(library, retry) { (authority, saved) ->
                    val languages = reader.languages(authority)
                    val language = RulingsReader.preferredLanguage(saved, locale(), languages)
                    RulingsScope(
                        reader.authorities(),
                        authority,
                        languages,
                        languages.firstOrNull { it.id == language },
                    )
                }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), Loadable.Loading)

        val questions: StateFlow<Loadable<List<Ruling>>> =
            combine(scope, query, submitted) { scope, query, submitted ->
                (scope as? Loadable.Loaded)?.value?.let { Triple(it, query.trim(), submitted == query) }
            }.distinctUntilChanged()
                .loading(library, retry, delayFor = { if (it?.second.isNullOrEmpty()) 0 else 150 }) { key ->
                    val (scope, query, online) = key ?: return@loading emptyList()
                    val language = scope.language ?: return@loading emptyList()
                    if (online && query.isNotEmpty()) {
                        val remote =
                            smartSearch.results(
                                query,
                                "rulings",
                                listOf(scope.authority),
                                languages = listOf(language.id),
                            ) { hits ->
                                hits
                                    .mapNotNull { it.reference as? SemanticSearchResult.Reference.Rulings }
                                    .filter { it.authority == scope.authority && it.language == language.id }
                                    .map {
                                        RulingID(
                                            it.authority,
                                            it.language,
                                            it.id,
                                        )
                                    }.distinct()
                                    .mapNotNull { reader.question(it) }
                            }
                        if (remote != null) return@loading remote
                    }
                    reader.questions(scope.authority, language.id, query)
                }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), Loadable.Loading)

        fun setAuthority(id: String) {
            viewModelScope.launch { settings.update { it.copy(rulingsAuthority = id) } }
        }

        fun setLanguage(id: String) {
            viewModelScope.launch {
                settings.update { it.copy(rulingsLanguages = it.rulingsLanguages + (it.rulingsAuthority to id)) }
            }
        }

        fun search(value: String) {
            if (value != submitted.value) submitted.value = ""
            query.value = value
        }

        fun submit() {
            submitted.value = query.value
            record()
        }

        fun record() = history.record(query.value, SearchArea.Rulings)

        fun removeRecent(value: String) = history.remove(value, SearchArea.Rulings)

        fun clearRecent() = history.clear(SearchArea.Rulings)

        fun retry() {
            library.refresh()
            retry.value++
        }
    }

/** The app's first language, as Swift's `locale`. */
fun locale(): Locale = QuranTranslations.preferredLanguages().firstOrNull() ?: Locale.getDefault()

data class RulingDetail(
    val ruling: Ruling,
    val authorityName: String,
    val language: RulingsLanguage?,
    val sections: List<RulingsSection>,
)

/** Swift `RulingsDetailView` and `SavedRulingDestination`: one question and answer, its sections and a bookmark. */
@HiltViewModel(assistedFactory = RulingDetailViewModel.Factory::class)
class RulingDetailViewModel
    @AssistedInject
    constructor(
        @Assisted val route: RulingDetailRoute,
        val library: RulingsLibrary,
        private val settings: ReadingSettings,
        private val user: QuranUserStore,
    ) : ViewModel() {
        @AssistedFactory
        interface Factory {
            fun create(route: RulingDetailRoute): RulingDetailViewModel
        }

        val id = RulingID(route.authority, route.language, route.siteID)
        val reading = settings.state
        private val retry = MutableStateFlow(0)

        /** `null` inside [Loadable.Loaded] when the question is no longer in the pack. */
        val detail: StateFlow<Loadable<RulingDetail?>> =
            MutableStateFlow(id)
                .loading(library, retry) { id ->
                    val reader = library.reader
                    val ruling = reader.question(id) ?: return@loading null
                    val authority = reader.authorities().firstOrNull { it.id == id.authority }
                    RulingDetail(
                        ruling,
                        authority?.name(locale()) ?: id.authority,
                        reader.languages(id.authority).firstOrNull { it.id == id.language },
                        runCatching { reader.sections(id) }.getOrDefault(emptyList()),
                    )
                }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), Loadable.Loading)

        val bookmark: StateFlow<ReadingBookmark?> =
            user.bookmarks
                .map { all -> all.firstOrNull { it.ruling == id } }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

        private val mutableBookmarkFailed = MutableStateFlow(false)
        val bookmarkFailed: StateFlow<Boolean> = mutableBookmarkFailed

        /** Swift `BookmarkButton` with a ruling: the source is the site id, the reference the authority. */
        fun toggleBookmark(detail: RulingDetail) =
            viewModelScope.launch {
                try {
                    val existing = bookmark.value
                    if (existing != null) {
                        user.delete(existing)
                    } else {
                        user.save(
                            ReadingBookmark(
                                source = id.siteID,
                                isHadith = false,
                                excerpt = detail.ruling.question,
                                reference = detail.authorityName,
                                ruling = id,
                            ),
                        )
                    }
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Exception) {
                    mutableBookmarkFailed.value = true
                }
            }

        fun dismissBookmarkFailure() {
            mutableBookmarkFailed.value = false
        }

        fun setSize(percent: Int) = viewModelScope.launch { settings.update { it.copy(readingSizePercent = percent) } }

        fun retry() {
            library.refresh()
            retry.value++
        }
    }

/** Swift `RulingsSectionView`: every question in one section. */
@HiltViewModel(assistedFactory = RulingSectionViewModel.Factory::class)
class RulingSectionViewModel
    @AssistedInject
    constructor(
        @Assisted val route: RulingSectionRoute,
        val library: RulingsLibrary,
    ) : ViewModel() {
        @AssistedFactory
        interface Factory {
            fun create(route: RulingSectionRoute): RulingSectionViewModel
        }

        private val retry = MutableStateFlow(0)

        val questions: StateFlow<Loadable<Pair<List<Ruling>, RulingsLanguage?>>> =
            MutableStateFlow(route)
                .loading(library, retry) { route ->
                    val reader = library.reader
                    reader.questions(route.authority, route.language, RulingsSection(route.section, route.title)) to
                        reader.languages(route.authority).firstOrNull { it.id == route.language }
                }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), Loadable.Loading)

        fun retry() {
            library.refresh()
            retry.value++
        }
    }

/** Swift `RulingsSavedView`: bookmarked rulings. */
@HiltViewModel
class RulingsSavedViewModel
    @Inject
    constructor(
        private val user: QuranUserStore,
    ) : ViewModel() {
        val bookmarks: StateFlow<List<ReadingBookmark>> =
            user.bookmarks
                .map { all -> all.filter { it.kind == ReadingBookmark.Kind.Ruling } }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val unavailable: StateFlow<Boolean> = user.unavailable

        fun remove(bookmark: ReadingBookmark) = viewModelScope.launch { runCatching { user.delete(bookmark) } }

        fun retry() = viewModelScope.launch { user.reopen() }
    }

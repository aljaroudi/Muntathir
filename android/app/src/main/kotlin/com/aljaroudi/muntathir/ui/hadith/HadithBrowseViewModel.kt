package com.aljaroudi.muntathir.ui.hadith

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.app.ReadingPreferences
import com.aljaroudi.muntathir.core.hadith.Hadith
import com.aljaroudi.muntathir.core.hadith.HadithChapter
import com.aljaroudi.muntathir.core.hadith.HadithCollection
import com.aljaroudi.muntathir.core.hadith.HadithCursor
import com.aljaroudi.muntathir.core.hadith.HadithIntroduction
import com.aljaroudi.muntathir.core.hadith.HadithRequest
import com.aljaroudi.muntathir.core.hadith.HadithSearch
import com.aljaroudi.muntathir.core.hadith.LibraryStatus
import com.aljaroudi.muntathir.core.search.SemanticSearchResult
import com.aljaroudi.muntathir.core.text.HadithText
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.data.library.ContentLibraries
import com.aljaroudi.muntathir.data.library.HadithSessionStore
import com.aljaroudi.muntathir.search.SmartSearch
import com.aljaroudi.muntathir.ui.navigation.HadithBrowseRoute
import com.aljaroudi.muntathir.ui.navigation.HadithRoute
import com.aljaroudi.muntathir.ui.search.SmartSearchRunner
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Swift `HadithView` state: books, a book's contents and introduction, and narrations for a chapter or a search. */
data class HadithBrowseState(
    val catalog: List<HadithCollection> = emptyList(),
    val chapters: List<HadithChapter> = emptyList(),
    val introductions: List<HadithIntroduction> = emptyList(),
    val narrations: List<Hadith> = emptyList(),
    val hasMore: Boolean = false,
    val loading: Boolean = true,
    val loadingMore: Boolean = false,
    val failed: Boolean = false,
    /** The submitted query whose results are shown. */
    val completed: String? = null,
)

/**
 * The library (no scope), a book ([HadithBrowseRoute.collectionID]), a chapter, or a search across books. Narrations
 * load a page at a time as the list reaches its end (Swift pages with Previous/Next).
 */
@HiltViewModel(assistedFactory = HadithBrowseViewModel.Factory::class)
class HadithBrowseViewModel
    @AssistedInject
    constructor(
        @Assisted val route: HadithBrowseRoute,
        @Assisted val isRoot: Boolean,
        libraries: ContentLibraries,
        private val history: SearchHistoryStore,
        private val session: HadithSessionStore,
        private val settings: ReadingSettings,
        smartSearch: SmartSearch,
    ) : ViewModel() {
        @AssistedFactory
        interface Factory {
            fun create(
                route: HadithBrowseRoute,
                isRoot: Boolean,
            ): HadithBrowseViewModel
        }

        val library = libraries.hadith
        private val reader = library.reader

        val reading: StateFlow<ReadingPreferences> = settings.state

        /** The session level whose first visible row is saved; `null` for searches that aren't kept. */
        val level: HadithSessionStore.Level? =
            when {
                route.chapterID != null -> HadithSessionStore.Level.Results
                route.collectionID != null -> HadithSessionStore.Level.Contents
                isRoot -> HadithSessionStore.Level.Results
                else -> null
            }

        private val mutableQuery = MutableStateFlow(route.query)

        /** The search field; books and chapters filter as it changes. */
        val query: StateFlow<String> = mutableQuery.asStateFlow()

        private val mutableSubmitted = MutableStateFlow(route.query)

        /** The searched text: narrations follow it. */
        val submitted: StateFlow<String> = mutableSubmitted.asStateFlow()

        private val mutableState = MutableStateFlow(HadithBrowseState())
        val state: StateFlow<HadithBrowseState> = mutableState.asStateFlow()

        val recent: StateFlow<List<String>> =
            history.state
                .map { it.queries(SearchArea.Hadith) }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        private val mutableRestore = MutableStateFlow<List<HadithRoute>?>(null)

        /** Saved screens to reopen below the library, once per process (root only). */
        val restore: StateFlow<List<HadithRoute>?> = mutableRestore.asStateFlow()

        private val mutableRestoredRow = MutableStateFlow(if (isRoot) null else level?.let(session::takeRow))

        /** A restored first visible row to scroll to once loaded. */
        val restoredRow: StateFlow<String?> = mutableRestoredRow.asStateFlow()

        /** Opt-in meaning search for the submitted query, within this screen's book or chapter. */
        val smart = SmartSearchRunner<Hadith>(viewModelScope, smartSearch.client)

        private val retry = MutableStateFlow(0)
        private var cursor: HadithCursor? = null
        private var loadingJob: Job? = null

        init {
            viewModelScope.launch {
                combine(
                    mutableSubmitted,
                    library.state.map { it.revision to (it.status.name) }.distinctUntilChanged(),
                    retry,
                ) { submitted, _, _ -> submitted }
                    .filter { library.state.value.status == LibraryStatus.Ready }
                    .collect(::load)
            }
            if (isRoot) {
                viewModelScope.launch {
                    library.state.first { it.status == LibraryStatus.Ready }
                    val restored = session.restore() ?: return@launch
                    if (restored.rootQuery.isNotBlank() && mutableSubmitted.value.isBlank()) {
                        mutableQuery.value = restored.rootQuery
                        mutableSubmitted.value = restored.rootQuery
                    }
                    // The library's own row, unless a chapter's results were open above it.
                    if (restored.routes.none { it is HadithBrowseRoute && it.chapterID != null }) {
                        mutableRestoredRow.value = session.takeRow(HadithSessionStore.Level.Results)
                    }
                    if (restored.routes.isNotEmpty()) mutableRestore.value = restored.routes
                }
            }
        }

        fun setEnglish(value: Boolean) =
            viewModelScope.launch { settings.update { it.copy(hadithEnglishEnabled = value) } }

        fun restored() {
            mutableRestore.value = null
        }

        fun rowRestored() {
            mutableRestoredRow.value = null
        }

        fun setQuery(value: String) {
            mutableQuery.value = value
            // Clearing the field clears the search (Swift `onChange(of: searchText)`).
            if (value.isEmpty() && mutableSubmitted.value.isNotEmpty()) submit()
        }

        fun submit() {
            if (mutableSubmitted.value == mutableQuery.value) return
            // A new query asks for consent again.
            smart.reset()
            mutableSubmitted.value = mutableQuery.value
            if (isRoot) session.setRootQuery(mutableQuery.value)
        }

        fun search(value: String) {
            mutableQuery.value = value
            submit()
        }

        fun record() = history.record(mutableQuery.value, SearchArea.Hadith)

        fun removeRecent(query: String) = history.remove(query, SearchArea.Hadith)

        fun clearRecent() = history.clear(SearchArea.Hadith)

        fun retry() {
            library.refresh()
            retry.value++
        }

        fun saveRow(row: String?) {
            level?.let { session.setRow(it, row) }
        }

        /** Whether smart search may be offered: a meaning, not a number or chapter lookup. */
        fun offersSmartSearch(submitted: String): Boolean {
            val query = submitted.trim()
            return SmartSearchRunner.accepts(query) && HadithSearch.number(query) == null &&
                HadithSearch.chapter(query) == null
        }

        /**
         * Swift `HadithView` meaning search: references in this scope resolved locally (exactly one match each),
         * without supplications, in the API's order.
         */
        fun smartSearch() {
            val query = mutableSubmitted.value.trim()
            val request = request(query)
            smart.run { client ->
                val (sources, chapter) = reader.meaningSearchScope(request)
                val terms = QuranSearchText.terms(query)
                val seen = mutableSetOf<Int>()
                client
                    .search(query, kind = "hadith", sources = sources, chapter = chapter)
                    .mapNotNull { it.reference as? SemanticSearchResult.Reference.Hadith }
                    .mapNotNull { reference ->
                        val id = reader.resolveSearch(reference.book, reference.chapter, reference.number)
                        if (id == null || !seen.add(id)) return@mapNotNull null
                        val narration = reader.detail(id, query).narration
                        if (narration.isSupplication) return@mapNotNull null
                        narration.copy(
                            arabicPreview = HadithText.preview(narration.arabic, terms),
                            englishPreview =
                                HadithText.preview(
                                    narration.englishNarrator + " " + narration.english,
                                    terms,
                                ),
                        )
                    }
            }
        }

        /** Whether narrations are listed: a chapter, or a text or number search (not a `ch12` filter). */
        fun showsNarrations(submitted: String) =
            HadithSearch.chapter(submitted.trim()) == null && (submitted.isNotBlank() || route.chapterID != null)

        private fun request(submitted: String): HadithRequest {
            val trimmed = submitted.trim()
            val number = HadithSearch.number(trimmed)
            return HadithRequest(
                query = if (number != null) "" else trimmed,
                collectionID = route.collectionID,
                chapterID = route.chapterID,
                number = number,
            )
        }

        private fun load(submitted: String) {
            loadingJob?.cancel()
            cursor = null
            mutableState.update { it.copy(loading = true, failed = false, narrations = emptyList(), hasMore = false) }
            loadingJob =
                viewModelScope.launch {
                    try {
                        val catalog = mutableState.value.catalog.ifEmpty { reader.catalog() }
                        val collection = route.collectionID
                        val introductions =
                            if (submitted.isBlank() && collection != null) {
                                reader.introductions(collection, route.chapterID)
                            } else {
                                emptyList()
                            }
                        val chapters =
                            mutableState.value.chapters.ifEmpty {
                                if (collection != null ||
                                    submitted.isNotBlank()
                                ) {
                                    reader.chapters(collection)
                                } else {
                                    emptyList()
                                }
                            }
                        val page = if (showsNarrations(submitted)) reader.page(request(submitted)) else null
                        cursor = page?.nextCursor
                        mutableState.value =
                            HadithBrowseState(
                                catalog = catalog,
                                chapters = chapters,
                                introductions = introductions,
                                narrations = page?.rows.orEmpty(),
                                hasMore = page?.hasMore == true,
                                loading = false,
                                completed = submitted,
                            )
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (_: Exception) {
                        library.invalidateValidation()
                        mutableState.update { it.copy(loading = false, failed = true) }
                    }
                }
        }

        fun loadMore() {
            val next = cursor ?: return
            if (mutableState.value.loadingMore || mutableState.value.loading) return
            val submitted = mutableSubmitted.value
            mutableState.update { it.copy(loadingMore = true) }
            viewModelScope.launch {
                try {
                    val page = reader.page(request(submitted).copy(cursor = next))
                    if (submitted != mutableSubmitted.value) return@launch
                    cursor = page.nextCursor
                    mutableState.update {
                        it.copy(
                            narrations = (it.narrations + page.rows).distinctBy(Hadith::id),
                            hasMore = page.hasMore,
                            loadingMore = false,
                        )
                    }
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Exception) {
                    mutableState.update { it.copy(loadingMore = false, hasMore = false) }
                }
            }
        }
    }

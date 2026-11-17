package com.aljaroudi.muntathir.ui.quran

import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.search.SemanticSearchClient
import com.aljaroudi.muntathir.core.search.SemanticSearchResult
import com.aljaroudi.muntathir.core.text.InvalidReferenceException
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.search.SmartSearch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.launch

/** Verse matches for the submitted query. Swift `QuranSearchContent` state. */
data class VerseResults(
    /** The query these results answer; empty before any search. */
    val query: String = "",
    val translation: String? = null,
    val verses: List<Ayah> = emptyList(),
    val hasMore: Boolean = false,
    val loading: Boolean = false,
    val failed: Boolean = false,
    val invalidReference: Boolean = false,
)

/** Swift `MeaningSearchResults`: nothing until the user asks, then searching, failed or results. */
sealed interface SmartResults {
    data object Idle : SmartResults

    data object Loading : SmartResults

    data object Failed : SmartResults

    data class Loaded(
        val verses: List<Ayah>,
    ) : SmartResults
}

/**
 * Search over the Quran, in every surah or only [surah]: a live query that filters surahs, a submitted query
 * that searches verses (50 at a time), recent searches, and opt-in smart search.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class QuranSearchModel(
    private val scope: CoroutineScope,
    private val quran: QuranDatabase,
    private val translations: QuranTranslations,
    private val history: SearchHistoryStore,
    smartSearch: SmartSearch,
    val surah: Int?,
) {
    private val client: SemanticSearchClient? = smartSearch.client

    private val mutableQuery = MutableStateFlow("")
    val query: StateFlow<String> = mutableQuery.asStateFlow()

    private val mutableSubmitted = MutableStateFlow("")
    val submitted: StateFlow<String> = mutableSubmitted.asStateFlow()

    private val limit = MutableStateFlow(PAGE)
    private val retry = MutableStateFlow(0)

    val recent: StateFlow<List<String>> =
        history.state.map { it.queries(SearchArea.Quran) }.stateIn(scope, SharingStarted.Eagerly, emptyList())

    private var latest = VerseResults()

    val results: StateFlow<VerseResults> =
        combine(
            mutableSubmitted.map { it.trim() }.distinctUntilChanged(),
            translations.state.map { it.activeID to it.revision }.distinctUntilChanged(),
            limit,
            retry,
        ) { query, (translation, revision), limit, _ -> Request(query, translation, revision, limit) }
            .transformLatest { request ->
                var current = latest
                // Keep showing the old matches while loading more of the same search.
                if (current.query != request.query ||
                    current.translation != request.translation
                ) {
                    current = VerseResults()
                }
                emit(current.copy(loading = true, failed = false, invalidReference = false, hasMore = false))
                emit(load(request, current))
            }.onEach { latest = it }
            .stateIn(scope, SharingStarted.Eagerly, VerseResults())

    private val mutableSmart = MutableStateFlow<SmartResults>(SmartResults.Idle)
    val smart: StateFlow<SmartResults> = mutableSmart.asStateFlow()
    private var smartJob: Job? = null

    /** Whether smart search may be offered for the submitted query. */
    val smartSearchAvailable: Boolean get() = client != null

    init {
        // A new search or translation starts again at the first page and withdraws smart-search consent.
        combine(mutableSubmitted, translations.state.map { it.activeID to it.revision }) { query, translation ->
            query to
                translation
        }.distinctUntilChanged()
            .drop(1)
            .onEach {
                limit.value = PAGE
                smartJob?.cancel()
                mutableSmart.value = SmartResults.Idle
            }.launchIn(scope)
    }

    fun setQuery(value: String) {
        mutableQuery.value = value
        if (value.isEmpty()) mutableSubmitted.value = ""
    }

    fun submit() {
        mutableSubmitted.value = mutableQuery.value
        record(mutableQuery.value)
    }

    /** Fills the field with a recent search and runs it. */
    fun search(recent: String) {
        mutableQuery.value = recent
        submit()
    }

    fun record(query: String = mutableQuery.value) = history.record(query, SearchArea.Quran)

    fun removeRecent(query: String) = history.remove(query, SearchArea.Quran)

    fun clearRecent() = history.clear(SearchArea.Quran)

    fun loadMore() {
        if (!results.value.loading) limit.value += PAGE
    }

    fun retry() {
        retry.value++
    }

    /** Swift `MeaningSearchResults`: references from `/v1/search`, read locally, in the API's order. */
    fun smartSearch() {
        val client = client ?: return
        val query = mutableSubmitted.value.trim()
        val translation = translations.state.value.activeID
        smartJob?.cancel()
        mutableSmart.value = SmartResults.Loading
        smartJob =
            scope.launch {
                mutableSmart.value =
                    try {
                        val references =
                            client
                                .search(query, kind = "quran", chapter = surah?.toString())
                                .mapNotNull { (it.reference as? SemanticSearchResult.Reference.Quran) }
                                .filter { surah == null || it.chapter == surah }
                                .map { "${it.chapter}:${it.verse}" }
                                .distinct()
                        val verses = quran.read { verses(references, translation) }.associateBy { it.id }
                        SmartResults.Loaded(
                            references.mapNotNull { verses[it] }.filter { QuranSearchText.isSearchableVerse(it.text) },
                        )
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (_: Exception) {
                        SmartResults.Failed
                    }
            }
    }

    private data class Request(
        val query: String,
        val translation: String?,
        val revision: Int,
        val limit: Int,
    )

    private suspend fun load(
        request: Request,
        current: VerseResults,
    ): VerseResults {
        if (request.query.isEmpty()) return VerseResults()
        // A number across all surahs filters the surah list only.
        if (surah == null) {
            QuranSearchText.number(request.query)?.let { number ->
                return VerseResults(request.query, request.translation, invalidReference = number !in 1..SURAHS)
            }
        }
        return try {
            val found =
                quran.read { search(request.query, request.translation, request.limit + 1, surah, request.revision) }
            VerseResults(
                request.query,
                request.translation,
                found.take(request.limit),
                hasMore =
                    found.size > request.limit,
            )
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: InvalidReferenceException) {
            VerseResults(request.query, request.translation, invalidReference = true)
        } catch (_: Exception) {
            current.copy(loading = false, failed = true)
        }
    }

    companion object {
        const val PAGE = 50
        private const val SURAHS = 114

        /** Smart search is for meanings, not numbers or references. */
        fun isMeaningQuery(query: String): Boolean =
            query.isNotEmpty() &&
                query.length <= SemanticSearchClient.MAX_QUERY_LENGTH &&
                QuranSearchText.number(query) == null &&
                runCatching { QuranSearchText.reference(query) }.getOrDefault(Unit) == null
    }
}

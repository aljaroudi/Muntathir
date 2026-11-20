package com.aljaroudi.muntathir.ui.quran

import com.aljaroudi.muntathir.core.quran.Ayah
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

/**
 * Search over the Quran, in every surah or only [surah]: a live query that filters surahs, a submitted query
 * that searches verses (50 at a time), recent searches, and remote-first search.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class QuranSearchModel(
    scope: CoroutineScope,
    private val quran: QuranDatabase,
    private val translations: QuranTranslations,
    private val history: SearchHistoryStore,
    private val smartSearch: SmartSearch,
    val surah: Int?,
) {
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

    init {
        // Start each query or translation at the first page.
        combine(mutableSubmitted, translations.state.map { it.activeID to it.revision }) { query, translation ->
            query to
                translation
        }.distinctUntilChanged()
            .drop(1)
            .onEach {
                limit.value = PAGE
            }.launchIn(scope)
    }

    fun setQuery(value: String) {
        mutableQuery.value = value
        if (value != mutableSubmitted.value) mutableSubmitted.value = ""
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
            if (request.limit == PAGE) {
                val number = QuranSearchText.number(request.query)
                val remoteQuery = if (surah != null && number != null) "$surah:$number" else request.query
                val exact = QuranSearchText.reference(remoteQuery)
                val remote =
                    smartSearch.results(remoteQuery, "quran", chapter = surah?.toString()) { hits ->
                        val references =
                            hits
                                .mapNotNull { it.reference as? SemanticSearchResult.Reference.Quran }
                                .filter {
                                    (surah == null || it.chapter == surah) &&
                                        (exact == null || exact == (it.chapter to it.verse))
                                }.map { "${it.chapter}:${it.verse}" }
                                .distinct()
                        val verses = quran.read { verses(references, request.translation) }.associateBy { it.id }
                        references.mapNotNull { verses[it] }.filter {
                            exact != null ||
                                QuranSearchText.isSearchableVerse(it.text)
                        }
                    }
                if (remote != null) return VerseResults(request.query, request.translation, remote)
            }
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
    }
}

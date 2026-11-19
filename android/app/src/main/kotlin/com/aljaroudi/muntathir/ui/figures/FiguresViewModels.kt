package com.aljaroudi.muntathir.ui.figures

import kotlinx.coroutines.Job
import com.aljaroudi.muntathir.core.search.SemanticSearchResult
import com.aljaroudi.muntathir.search.SmartSearch
import com.aljaroudi.muntathir.core.figures.FigureLibrary
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.data.library
import com.aljaroudi.muntathir.data.FigureLoad
import com.aljaroudi.muntathir.data.FigureStore
import com.aljaroudi.muntathir.data.SearchHistoryStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

/** Swift `FigureBrowser`: the library, the query and its recent searches. */
@HiltViewModel
class FiguresViewModel
    @Inject
    constructor(
        store: FigureStore,
        private val history: SearchHistoryStore,
        private val smartSearch: SmartSearch,
    ) : ViewModel() {
        val library: StateFlow<FigureLoad> = store.state

        private val _query = MutableStateFlow("")
        val query: StateFlow<String> = _query.asStateFlow()

        val recent: StateFlow<List<String>> =
            history.state
                .map { it.queries(SearchArea.Figures) }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val remote = MutableStateFlow<List<FigureLibrary.BrowserSection>?>(null)
        private var searchJob: Job? = null

        fun submit() {
            record()
            val text = query.value.trim()
            val catalog = library.value.library ?: return
            searchJob?.cancel()
            if (text.isEmpty()) return
            searchJob = viewModelScope.launch {
                val figures = smartSearch.results(text, "figure") { hits ->
                    hits.mapNotNull { it.reference as? SemanticSearchResult.Reference.Figure }
                        .mapNotNull { catalog.byID[it.id] }
                }
                remote.value = figures?.let {
                    if (it.isEmpty()) emptyList() else listOf(FigureLibrary.BrowserSection("results", it))
                }
            }
        }

        fun search(value: String) {
            searchJob?.cancel()
            remote.value = null
            _query.value = value
        }

        /** Swift `.recordSearchOnOpen`: the query is remembered when a result opens. */
        fun record() = history.record(_query.value, SearchArea.Figures)

        fun removeRecent(value: String) = history.remove(value, SearchArea.Figures)

        fun clearRecent() = history.clear(SearchArea.Figures)
    }

/** Swift `FigureDestination`: the shared library for profiles and observance pickers. */
@HiltViewModel
class FigureLibraryViewModel
    @Inject
    constructor(
        store: FigureStore,
    ) : ViewModel() {
        val library: StateFlow<FigureLoad> = store.state
    }

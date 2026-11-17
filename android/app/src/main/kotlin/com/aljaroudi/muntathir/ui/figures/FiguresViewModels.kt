package com.aljaroudi.muntathir.ui.figures

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.data.FigureLoad
import com.aljaroudi.muntathir.data.FigureStore
import com.aljaroudi.muntathir.data.SearchHistoryStore
import dagger.hilt.android.lifecycle.HiltViewModel
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
    ) : ViewModel() {
        val library: StateFlow<FigureLoad> = store.state

        private val _query = MutableStateFlow("")
        val query: StateFlow<String> = _query.asStateFlow()

        val recent: StateFlow<List<String>> =
            history.state
                .map { it.queries(SearchArea.Figures) }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        fun search(value: String) {
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

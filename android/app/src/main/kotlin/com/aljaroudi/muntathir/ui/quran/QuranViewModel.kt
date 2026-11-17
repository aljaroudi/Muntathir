package com.aljaroudi.muntathir.ui.quran

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.quran.QuranCatalog
import com.aljaroudi.muntathir.core.quran.TranslationState
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.search.SmartSearch
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface CatalogState {
    data object Loading : CatalogState

    data object Failed : CatalogState

    data class Loaded(
        val catalog: QuranCatalog,
    ) : CatalogState
}

/** Swift `QuranView`: the surah list with live filtering, and search across the Quran. */
@HiltViewModel
class QuranViewModel
    @Inject
    constructor(
        private val quran: QuranDatabase,
        val translations: QuranTranslations,
        history: SearchHistoryStore,
        smartSearch: SmartSearch,
    ) : ViewModel() {
        private val mutableCatalog = MutableStateFlow<CatalogState>(CatalogState.Loading)
        val catalog: StateFlow<CatalogState> = mutableCatalog.asStateFlow()

        val translation: StateFlow<TranslationState> = translations.state

        val search = QuranSearchModel(viewModelScope, quran, translations, history, smartSearch, surah = null)

        init {
            load()
        }

        fun load() {
            mutableCatalog.value = CatalogState.Loading
            viewModelScope.launch {
                mutableCatalog.value =
                    try {
                        CatalogState.Loaded(quran.read { catalog() })
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (_: Exception) {
                        CatalogState.Failed
                    }
            }
        }

        fun selectTranslation(selection: String) = translations.select(selection)
    }

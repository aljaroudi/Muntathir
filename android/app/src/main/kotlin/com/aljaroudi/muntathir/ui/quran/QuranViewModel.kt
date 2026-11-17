package com.aljaroudi.muntathir.ui.quran

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.quran.QuranCatalog
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.data.QuranTranslationStore
import com.aljaroudi.muntathir.data.TranslationState
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

/** Swift `QuranView`: the surah list with live filtering. */
@HiltViewModel
class QuranViewModel
    @Inject
    constructor(
        private val quran: QuranDatabase,
        private val translations: QuranTranslationStore,
    ) : ViewModel() {
        private val mutableCatalog = MutableStateFlow<CatalogState>(CatalogState.Loading)
        val catalog: StateFlow<CatalogState> = mutableCatalog.asStateFlow()

        val translation: StateFlow<TranslationState> = translations.state

        /** The search field's text. */
        val query = MutableStateFlow("")

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

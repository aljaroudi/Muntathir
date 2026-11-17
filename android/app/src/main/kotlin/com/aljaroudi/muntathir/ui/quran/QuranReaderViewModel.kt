package com.aljaroudi.muntathir.ui.quran

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.app.QuranReadingMode
import com.aljaroudi.muntathir.core.app.ReadingPreferences
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.quran.QuranCatalog
import com.aljaroudi.muntathir.core.quran.QuranPage
import com.aljaroudi.muntathir.core.quran.TranslationState
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.search.SmartSearch
import com.aljaroudi.muntathir.ui.navigation.QuranReaderRoute
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Loading, failed, or a surah's verses with the active translation. */
sealed interface ChapterState {
    data object Loading : ChapterState

    data object Failed : ChapterState

    data class Loaded(
        val surah: Int,
        val verses: List<Ayah>,
        val translation: String?,
    ) : ChapterState
}

/** A verse in the reader; the reader reports the topmost visible one. */
data class ReaderPosition(
    val surah: Int,
    val verse: Int,
)

/** Swift `QuranReadingView` + `QuranChapterView` + `QuranMushafView` state. */
@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel(assistedFactory = QuranReaderViewModel.Factory::class)
class QuranReaderViewModel
    @AssistedInject
    constructor(
        @Assisted val route: QuranReaderRoute,
        private val quran: QuranDatabase,
        private val settings: ReadingSettings,
        val translations: QuranTranslations,
        private val history: SearchHistoryStore,
        private val smartSearch: SmartSearch,
    ) : ViewModel() {
        @AssistedFactory
        interface Factory {
            fun create(route: QuranReaderRoute): QuranReaderViewModel
        }

        val reading: StateFlow<ReadingPreferences> = settings.state
        val translation: StateFlow<TranslationState> = translations.state

        private val mutablePosition = MutableStateFlow(ReaderPosition(route.surah, route.verse))
        val position: StateFlow<ReaderPosition> = mutablePosition

        private val retry = MutableStateFlow(0)

        val catalog: StateFlow<QuranCatalog?> =
            retry
                .map { runCatching { quran.read { catalog() } }.getOrNull() }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

        val chapter: StateFlow<ChapterState> =
            combine(
                position.map { it.surah }.distinctUntilChanged(),
                translations.state.map { it.activeID to it.revision }.distinctUntilChanged(),
                retry,
            ) { surah, (translation, _), _ -> surah to translation }
                .flatMapLatest { (surah, translation) ->
                    flow {
                        emit(ChapterState.Loading)
                        emit(
                            try {
                                val verses = quran.read { verses(surah, translation) }
                                if (verses.isEmpty()) {
                                    ChapterState.Failed
                                } else {
                                    ChapterState.Loaded(
                                        surah,
                                        verses,
                                        translation,
                                    )
                                }
                            } catch (cancellation: CancellationException) {
                                throw cancellation
                            } catch (_: Exception) {
                                ChapterState.Failed
                            },
                        )
                    }
                }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ChapterState.Loading)

        private val mutableSearch = MutableStateFlow<QuranSearchModel?>(null)

        /** Search within the surah being read when search opened (Swift `searchSurah`), or `null` when closed. */
        val search: StateFlow<QuranSearchModel?> = mutableSearch
        private var searchScope: CoroutineScope? = null

        fun openSearch() {
            if (mutableSearch.value != null) return
            val scope =
                CoroutineScope(viewModelScope.coroutineContext + SupervisorJob(viewModelScope.coroutineContext[Job]))
            searchScope = scope
            mutableSearch.value =
                QuranSearchModel(scope, quran, translations, history, smartSearch, position.value.surah)
        }

        fun closeSearch() {
            searchScope?.cancel()
            searchScope = null
            mutableSearch.value = null
        }

        fun setPosition(position: ReaderPosition) {
            // The hidden reader doesn't move while search results cover it.
            if (mutableSearch.value
                    ?.query
                    ?.value
                    ?.isNotBlank() == true
            ) {
                return
            }
            mutablePosition.value = position
        }

        fun setMode(mode: QuranReadingMode) =
            viewModelScope.launch { settings.update { it.copy(quranReadingMode = mode) } }

        fun setSize(percent: Int) = viewModelScope.launch { settings.update { it.copy(readingSizePercent = percent) } }

        fun selectTranslation(selection: String) = translations.select(selection)

        fun retry() {
            retry.value++
        }

        /** A mushaf page, or `null` when it can't be read. */
        suspend fun page(number: Int): QuranPage? = runCatching { quran.read { page(number) } }.getOrNull()

        suspend fun pageNumber(position: ReaderPosition): Int? =
            runCatching { quran.read { pageNumber(position.surah, position.verse) } }.getOrNull()
    }

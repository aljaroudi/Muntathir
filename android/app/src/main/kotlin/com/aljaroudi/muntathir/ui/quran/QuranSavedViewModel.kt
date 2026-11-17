package com.aljaroudi.muntathir.ui.quran

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.highlight.ReadingBookmark
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.ui.reader.HighlightDraft
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
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

/** The saved verses' text, so rows can open and highlights can be checked against it. */
sealed interface SavedVerses {
    data object Loading : SavedVerses

    data object Failed : SavedVerses

    data class Loaded(
        val verses: Map<String, Ayah>,
    ) : SavedVerses
}

/** Swift `QuranSavedVersesView` + `SavedList` state. */
@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class QuranSavedViewModel
    @Inject
    constructor(
        val user: QuranUserStore,
        private val quran: QuranDatabase,
        translations: QuranTranslations,
        private val settings: ReadingSettings,
        private val history: SearchHistoryStore,
    ) : ViewModel() {
        val highlights: StateFlow<List<ReadingHighlight>> =
            user.highlights
                .map { all -> all.filter { !it.isHadith } }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val bookmarks: StateFlow<List<ReadingBookmark>> =
            user.bookmarks
                .map { all -> all.filter { it.kind == ReadingBookmark.Kind.Quran } }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val unavailable: StateFlow<Boolean> = user.unavailable
        val reading = settings.state

        /** Arabic surah names for Arabic titles. */
        val surahNames: StateFlow<Map<Int, String>> =
            kotlinx.coroutines.flow
                .flow { emit(quran.surahNames()) }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())

        val query = MutableStateFlow("")
        val showingBookmarks = MutableStateFlow(false)

        private val retry = MutableStateFlow(0)

        val verses: StateFlow<SavedVerses> =
            combine(
                combine(
                    highlights,
                    bookmarks,
                ) { h, b -> (h.map { it.source } + b.map { it.source }).distinct().sorted() }
                    .distinctUntilChanged(),
                translations.state.map { it.activeID to it.revision }.distinctUntilChanged(),
                retry,
            ) { sources, (translation, _), _ -> sources to translation }
                .transformLatest { (sources, translation) ->
                    emit(SavedVerses.Loading)
                    emit(
                        try {
                            SavedVerses.Loaded(quran.read { verses(sources, translation) }.associateBy { it.id })
                        } catch (cancellation: CancellationException) {
                            throw cancellation
                        } catch (_: Exception) {
                            SavedVerses.Failed
                        },
                    )
                }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SavedVerses.Loading)

        private val mutableEditing = MutableStateFlow<HighlightDraft?>(null)
        val editing: StateFlow<HighlightDraft?> = mutableEditing

        private val mutableBookmarkFailed = MutableStateFlow(false)
        val bookmarkFailed: StateFlow<Boolean> = mutableBookmarkFailed

        fun setGroupByDate(value: Boolean) =
            viewModelScope.launch { settings.update { it.copy(savedGroupByDate = value) } }

        fun record() = history.record(query.value, SearchArea.Saved)

        fun edit(highlight: ReadingHighlight) {
            mutableEditing.value = HighlightDraft(listOf(highlight), existing = true)
        }

        fun closeEditor() {
            mutableEditing.value = null
        }

        suspend fun save(highlights: List<ReadingHighlight>) = user.save(highlights)

        suspend fun delete(highlight: ReadingHighlight) = user.delete(highlight)

        fun remove(bookmark: ReadingBookmark) =
            viewModelScope.launch {
                try {
                    user.delete(bookmark)
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Exception) {
                    mutableBookmarkFailed.value = true
                }
            }

        fun dismissBookmarkFailure() {
            mutableBookmarkFailed.value = false
        }

        fun retry() {
            viewModelScope.launch { user.reopen() }
            retry.value++
        }
    }

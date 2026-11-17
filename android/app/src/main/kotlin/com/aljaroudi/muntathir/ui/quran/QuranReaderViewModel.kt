package com.aljaroudi.muntathir.ui.quran

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.app.QuranReadingMode
import com.aljaroudi.muntathir.core.app.ReadingPreferences
import com.aljaroudi.muntathir.core.highlight.HighlightRange
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.highlight.ReadingBookmark
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.quran.QuranCatalog
import com.aljaroudi.muntathir.core.quran.QuranPage
import com.aljaroudi.muntathir.core.quran.TranslationState
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.search.SmartSearch
import com.aljaroudi.muntathir.ui.navigation.QuranReaderRoute
import com.aljaroudi.muntathir.ui.reader.HighlightDraft
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
import kotlinx.coroutines.flow.first
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
        val user: QuranUserStore,
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

        /** Quran highlights (not Hadith). */
        val highlights: StateFlow<List<ReadingHighlight>> =
            user.highlights
                .map { all -> all.filter { !it.isHadith } }
                .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val bookmarks: StateFlow<List<ReadingBookmark>> = user.bookmarks

        private val mutableEditing = MutableStateFlow<HighlightDraft?>(null)

        /** The highlight editor's subject, when open. */
        val editing: StateFlow<HighlightDraft?> = mutableEditing

        private val mutableChoosing = MutableStateFlow<List<ReadingHighlight>>(emptyList())

        /** Overlapping highlights under a tap, to choose from (Swift's "Highlights" chooser). */
        val choosing: StateFlow<List<ReadingHighlight>> = mutableChoosing

        private val mutableBookmarkFailed = MutableStateFlow(false)
        val bookmarkFailed: StateFlow<Boolean> = mutableBookmarkFailed

        init {
            // Opening a saved translation highlight shows that translation (Swift `QuranChapterView`).
            route.highlight?.let { id ->
                viewModelScope.launch {
                    val highlight = user.highlights.first { list -> list.any { it.id == id } }.first { it.id == id }
                    val block = highlight.block
                    if (block != null && block != ARABIC_BLOCK &&
                        block != translations.state.value.activeID
                    ) {
                        translations.select(block)
                    }
                }
            }
        }

        /** A selection in [text] of [block] of [ayah] becomes a new highlight for the editor. */
        fun select(
            ayah: Ayah,
            block: String,
            text: String,
            ranges: List<TextRange>,
        ) {
            val selected = ranges.mapNotNull { HighlightRange.of(it, text) }
            if (selected.isEmpty()) return
            mutableEditing.value =
                HighlightDraft(
                    listOf(
                        ReadingHighlight(
                            source = ayah.id,
                            isHadith = false,
                            block = block,
                            ranges = selected,
                            excerpt = selected.joinToString(" … ") { it.quote },
                            reference = ayah.id,
                        ),
                    ),
                    existing = false,
                )
        }

        /** A mushaf selection: one highlight per verse, edited together. */
        fun select(highlights: List<ReadingHighlight>) {
            if (highlights.isNotEmpty()) mutableEditing.value = HighlightDraft(highlights, existing = false)
        }

        /** A tap on highlighted text: edit the one highlight, or choose among overlapping ones. */
        fun open(highlights: List<ReadingHighlight>) {
            when (highlights.size) {
                0 -> Unit
                1 -> edit(highlights.single())
                else -> mutableChoosing.value = highlights
            }
        }

        fun edit(highlight: ReadingHighlight) {
            mutableChoosing.value = emptyList()
            mutableEditing.value = HighlightDraft(listOf(highlight), existing = true)
        }

        fun closeEditor() {
            mutableEditing.value = null
            mutableChoosing.value = emptyList()
        }

        suspend fun save(highlights: List<ReadingHighlight>) = user.save(highlights)

        suspend fun delete(highlight: ReadingHighlight) = user.delete(highlight)

        fun bookmark(ayah: Ayah): ReadingBookmark? =
            bookmarks.value.firstOrNull {
                it.kind == ReadingBookmark.Kind.Quran &&
                    it.source == ayah.id
            }

        /** Swift `BookmarkButton`: adds or removes the verse's bookmark. */
        fun toggleBookmark(ayah: Ayah) =
            viewModelScope.launch {
                try {
                    val existing = bookmark(ayah)
                    if (existing != null) {
                        user.delete(existing)
                    } else {
                        user.save(ReadingBookmark(ayah.id, isHadith = false, excerpt = ayah.text, reference = ayah.id))
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

        /** A mushaf page, or `null` when it can't be read. */
        suspend fun page(number: Int): QuranPage? = runCatching { quran.read { page(number) } }.getOrNull()

        suspend fun pageNumber(position: ReaderPosition): Int? =
            runCatching { quran.read { pageNumber(position.surah, position.verse) } }.getOrNull()
    }

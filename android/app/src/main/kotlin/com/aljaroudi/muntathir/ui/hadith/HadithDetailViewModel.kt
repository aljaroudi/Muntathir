package com.aljaroudi.muntathir.ui.hadith

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.core.app.ReadingPreferences
import com.aljaroudi.muntathir.core.hadith.HadithBlock
import com.aljaroudi.muntathir.core.hadith.HadithDetail
import com.aljaroudi.muntathir.core.hadith.HadithShareContent
import com.aljaroudi.muntathir.core.hadith.LibraryStatus
import com.aljaroudi.muntathir.core.highlight.HighlightRange
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.highlight.ReadingBookmark
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.progress.ProgressActivity
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.library.ContentLibraries
import com.aljaroudi.muntathir.data.user.ProgressStore
import com.aljaroudi.muntathir.ui.navigation.HadithDetailRoute
import com.aljaroudi.muntathir.ui.reader.HighlightDraft
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
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
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.launch
import java.util.Locale

sealed interface DetailState {
    data object Loading : DetailState

    data object Failed : DetailState

    data class Loaded(
        val detail: HadithDetail,
        /** Languages the supplication has translations in. */
        val translationLanguages: List<String> = emptyList(),
    ) : DetailState
}

/** Swift `HadithDetailView`: one narration or supplication, with previous/next, highlights and a bookmark. */
@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel(assistedFactory = HadithDetailViewModel.Factory::class)
class HadithDetailViewModel
    @AssistedInject
    constructor(
        @Assisted val route: HadithDetailRoute,
        libraries: ContentLibraries,
        private val settings: ReadingSettings,
        val user: QuranUserStore,
        private val progress: ProgressStore,
        private val session: HadithSessionStore,
    ) : ViewModel() {
        @AssistedFactory
        interface Factory {
            fun create(route: HadithDetailRoute): HadithDetailViewModel
        }

        val library = if (route.supplication) libraries.supplications else libraries.hadith
        private val reader = library.reader
        val reading: StateFlow<ReadingPreferences> = settings.state

        /** Kept in the session only for hadith opened from the library (not Saved, not supplications). */
        private val tracked = !route.supplication && route.highlight == null

        /** The restored scroll position, once. */
        val initialOffset: Int = if (tracked) session.takeDetailOffset() else 0

        private val current = MutableStateFlow(route.id)

        /** A translation forced by opening a translation highlight, until the user picks another. */
        private val forcedTranslation = MutableStateFlow<String?>(null)
        private val retry = MutableStateFlow(0)

        val languages: List<Locale> get() = QuranTranslations.preferredLanguages()

        val state: StateFlow<DetailState> =
            combine(
                current,
                settings.state.map { it.supplicationTranslation }.distinctUntilChanged(),
                forcedTranslation,
                library.state.map { it.revision to it.status }.distinctUntilChanged(),
                retry,
            ) { id, translation, forced, (_, status), _ -> Triple(id, forced ?: translation, status) }
                .filter { it.third == LibraryStatus.Ready }
                .transformLatest { (id, translation, _) ->
                    emit(DetailState.Loading)
                    emit(
                        try {
                            val detail = reader.detail(id, route.query, translation, languages)
                            val supplication = detail.narration.isSupplication
                            DetailState.Loaded(detail, if (supplication) reader.translationLanguages() else listOf())
                        } catch (cancellation: CancellationException) {
                            throw cancellation
                        } catch (_: Exception) {
                            library.invalidateValidation()
                            DetailState.Failed
                        },
                    )
                }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DetailState.Loading)

        val showEnglish: StateFlow<Boolean> =
            settings.state
                .map { it.showsHadithEnglish(languages) }
                .stateIn(viewModelScope, SharingStarted.Eagerly, settings.state.value.showsHadithEnglish(languages))

        val highlights: StateFlow<List<ReadingHighlight>> =
            combine(user.highlights, state) { all, state ->
                val key =
                    (state as? DetailState.Loaded)
                        ?.detail
                        ?.narration
                        ?.source
                        ?.key
                all.filter { it.isHadith && it.source == key }
            }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

        val bookmarks: StateFlow<List<ReadingBookmark>> = user.bookmarks

        private val mutableEditing = MutableStateFlow<HighlightDraft?>(null)
        val editing: StateFlow<HighlightDraft?> = mutableEditing.asStateFlow()

        private val mutableChoosing = MutableStateFlow<List<ReadingHighlight>>(emptyList())
        val choosing: StateFlow<List<ReadingHighlight>> = mutableChoosing.asStateFlow()

        private val mutableBookmarkFailed = MutableStateFlow(false)
        val bookmarkFailed: StateFlow<Boolean> = mutableBookmarkFailed.asStateFlow()

        init {
            route.highlight?.let { id ->
                viewModelScope.launch {
                    val highlight = user.highlights.first { list -> list.any { it.id == id } }.first { it.id == id }
                    val block = highlight.block.orEmpty()
                    // Swift: a saved English highlight turns English on; a translation one shows that edition.
                    if (block == HadithBlock.ENGLISH || block == HadithBlock.NARRATOR) setEnglish(true)
                    if (block.startsWith(HadithBlock.TRANSLATION_PREFIX)) {
                        forcedTranslation.value = block.removePrefix(HadithBlock.TRANSLATION_PREFIX)
                    }
                }
            }
        }

        fun open(id: Int?) {
            if (id == null) return
            current.value = id
            if (tracked) session.setDetailOffset(0)
        }

        fun saveOffset(offset: Int) {
            if (tracked) session.setDetailOffset(offset)
        }

        fun setEnglish(value: Boolean) =
            viewModelScope.launch { settings.update { it.copy(hadithEnglishEnabled = value) } }

        fun setTranslation(value: String) {
            forcedTranslation.value = null
            viewModelScope.launch { settings.update { it.copy(supplicationTranslation = value) } }
        }

        fun setSize(percent: Int) = viewModelScope.launch { settings.update { it.copy(readingSizePercent = percent) } }

        fun retry() {
            library.refresh()
            retry.value++
        }

        fun share(detail: HadithDetail) =
            HadithShareContent(
                detail.narration,
                showEnglish.value,
                languages.firstOrNull() ?: Locale.getDefault(),
            )

        /** A selection in [text] of [block] becomes a new highlight for the editor. */
        fun select(
            detail: HadithDetail,
            block: String,
            text: String,
            ranges: List<TextRange>,
        ) {
            val source = detail.narration.source?.key ?: return
            val selected = ranges.mapNotNull { HighlightRange.of(it, text) }
            if (selected.isEmpty()) return
            mutableEditing.value =
                HighlightDraft(
                    listOf(
                        ReadingHighlight(
                            source = source,
                            isHadith = true,
                            block = block,
                            ranges = selected,
                            excerpt = selected.joinToString(" … ") { it.quote },
                            reference = share(detail).reference,
                        ),
                    ),
                    existing = false,
                )
        }

        fun openHighlights(highlights: List<ReadingHighlight>) {
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

        fun bookmark(detail: HadithDetail): ReadingBookmark? {
            val key = detail.narration.source?.key ?: return null
            return bookmarks.value.firstOrNull { it.kind == ReadingBookmark.Kind.Hadith && it.source == key }
        }

        /** Swift `HadithBookmarkButton`. */
        fun toggleBookmark(detail: HadithDetail) =
            viewModelScope.launch {
                val key = detail.narration.source?.key ?: return@launch
                try {
                    val existing = bookmark(detail)
                    if (existing != null) {
                        user.delete(existing)
                    } else {
                        val content = share(detail)
                        val bookmark = ReadingBookmark(key, true, excerpt = content.body, reference = content.reference)
                        user.save(bookmark)
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

        fun record(activity: ProgressActivity) = progress.record(activity)
    }

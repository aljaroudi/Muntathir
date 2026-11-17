package com.aljaroudi.muntathir.data

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import com.aljaroudi.muntathir.core.quran.QuranTranslation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/** What the reader, daily ayah and search use. */
data class TranslationState(
    /** [QuranTranslation.AUTO], [QuranTranslation.NONE] or a catalog id. */
    val selection: String = QuranTranslation.AUTO,
    /** The resolved translation, installed or not; `null` for none. */
    val active: QuranTranslation? = null,
    /** Downloaded translations besides the bundled English. */
    val installed: Set<String> = emptySet(),
    /** Bumps whenever the active translation or installed files change; readers reload and search caches reset. */
    val revision: Int = 0,
) {
    fun isInstalled(id: String) = id == QuranTranslation.BUNDLED_ID || id in installed

    /** The translation to show, when it's installed. */
    val activeID: String? get() = active?.id?.takeIf(::isInstalled)
}

/** Swift `QuranTranslationStore`: the selection and the active translation. */
@Singleton
class QuranTranslationStore
    @Inject
    constructor(
        private val settings: ReadingSettings,
        @param:AppScope private val scope: CoroutineScope,
    ) {
        private val mutable = MutableStateFlow(TranslationState())
        val state: StateFlow<TranslationState> = mutable.asStateFlow()

        init {
            val selection = settings.state.value.quranTranslationSelection
            mutable.value = TranslationState(selection, QuranTranslation.resolve(selection, preferredLanguages()))
        }

        /** Selects a translation, [QuranTranslation.AUTO] or [QuranTranslation.NONE]; unchanged or invalid values do nothing. */
        fun select(selection: String) {
            if (selection == mutable.value.selection || !QuranTranslation.isValidSelection(selection)) return
            publish(selection)
            scope.launch { settings.update { it.copy(quranTranslationSelection = selection) } }
        }

        /** Re-resolves Auto after a language change; publishes only when the result changes. */
        fun activate(languages: List<Locale> = preferredLanguages()) {
            val current = mutable.value
            val active = QuranTranslation.resolve(current.selection, languages)
            if (active != current.active) publish(current.selection, languages)
        }

        private fun publish(
            selection: String,
            languages: List<Locale> = preferredLanguages(),
        ) = mutable.update {
            it.copy(
                selection = selection,
                active = QuranTranslation.resolve(selection, languages),
                revision =
                    it.revision + 1,
            )
        }

        companion object {
            /** The per-app language first, then the system's languages. */
            fun preferredLanguages(): List<Locale> {
                val app = AppCompatDelegate.getApplicationLocales()
                val system = LocaleListCompat.getAdjustedDefault()
                return (List(app.size()) { app[it] } + List(system.size()) { system[it] }).filterNotNull().distinct()
            }
        }
    }

package com.aljaroudi.muntathir.data

import android.app.Activity
import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import com.aljaroudi.muntathir.assets.AssetPackBackend
import com.aljaroudi.muntathir.assets.ContentPack
import com.aljaroudi.muntathir.assets.PlayAssetPack
import com.aljaroudi.muntathir.core.quran.QuranTranslationFiles
import com.aljaroudi.muntathir.core.quran.QuranTranslationStore
import com.aljaroudi.muntathir.core.quran.TranslationState
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.io.File
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Quran translations for the whole app: the selection, and downloads from the `quran_translations` pack into
 * `no_backup/QuranTranslations` (the pack is removed once copied). Swift `QuranTranslationStore.shared`; the
 * state machine itself is `core`'s [QuranTranslationStore], driven here on the main thread.
 */
@Singleton
class QuranTranslations
    @Inject
    constructor(
        @ApplicationContext context: Context,
        private val settings: ReadingSettings,
        quran: QuranDatabase,
        private val backend: AssetPackBackend,
        @AppScope scope: CoroutineScope,
    ) {
        private val main = CoroutineScope(scope.coroutineContext + Dispatchers.Main.immediate)
        private val pack = PlayAssetPack(backend, ContentPack.QuranTranslations)

        private val store =
            QuranTranslationStore(
                files =
                    QuranTranslationFiles(
                        File(context.noBackupFilesDir, "QuranTranslations"),
                        quran::isValidTranslation,
                    ),
                pack = pack,
                selection = settings.state.value.quranTranslationSelection,
                languages = preferredLanguages(),
                save = { selection ->
                    main.launch { settings.update { it.copy(quranTranslationSelection = selection) } }
                },
                installedChanged = quran::setTranslations,
            )

        val state: StateFlow<TranslationState> = store.state

        init {
            main.launch { store.refresh() }
            main.launch { pack.events().collect { store.receive(it) } }
            // Swift `monitor()`: while downloading, check every 2 s for a transfer stuck at 100%.
            main.launch {
                state.map { it.isDownloading }.distinctUntilChanged().collectLatest { downloading ->
                    while (downloading) {
                        delay(2_000)
                        store.reconcile(System.currentTimeMillis())
                    }
                }
            }
        }

        fun select(selection: String) = store.select(selection)

        /** On every start: finish or recover downloads, and follow language changes for Auto. */
        fun onForeground() {
            main.launch {
                store.activate(preferredLanguages())
                store.refresh()
            }
        }

        fun download(requested: String? = null) {
            main.launch { store.download(requested) }
        }

        fun remove(ids: List<String>) {
            main.launch { store.remove(ids) }
        }

        fun refresh() {
            main.launch { store.refresh() }
        }

        fun clearStorageError() = store.clearStorageError()

        /** Play's mobile-data or download confirmation dialog. */
        fun confirm(activity: Activity) {
            main.launch { runCatching { backend.confirm(activity) } }
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

package com.aljaroudi.muntathir.data.library

import android.content.Context
import com.aljaroudi.muntathir.assets.AssetPackBackend
import com.aljaroudi.muntathir.assets.ContentPack
import com.aljaroudi.muntathir.data.AppScope
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import javax.inject.Inject
import javax.inject.Singleton

/** The app's hadith-schema libraries, each created on first use. */
@Singleton
class ContentLibraries
    @Inject
    constructor(
        @ApplicationContext context: Context,
        backend: AssetPackBackend,
        @AppScope scope: CoroutineScope,
    ) {
        private val hadithLibrary = lazy { ContentLibrary(context, ContentPack.Hadith, backend, scope) }

        /** Fast-follow, like iOS's essential pack: requested once if Play hasn't delivered it. */
        private val supplicationsLibrary =
            lazy { ContentLibrary(context, ContentPack.Supplications, backend, scope, autoDownload = true) }

        val hadith by hadithLibrary
        val supplications by supplicationsLibrary

        fun get(pack: ContentPack): ContentLibrary? =
            when (pack) {
                ContentPack.Hadith -> hadith
                ContentPack.Supplications -> supplications
                else -> null
            }

        /** Started libraries only: a library nobody opened has nothing to resume. */
        private val started
            get() = listOf(hadithLibrary, supplicationsLibrary).filter(Lazy<*>::isInitialized).map { it.value }

        fun onForeground() = started.forEach(ContentLibrary::onForeground)

        fun onBackground() = started.forEach(ContentLibrary::onBackground)
    }

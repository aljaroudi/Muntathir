package com.aljaroudi.muntathir.data

import android.content.Context
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.figures.FigureLibrary
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject
import javax.inject.Singleton

sealed interface FigureLoad {
    data object Loading : FigureLoad

    data object Failed : FigureLoad

    data class Loaded(
        val library: FigureLibrary,
    ) : FigureLoad
}

/** The library when it's loaded, else `null`. */
val FigureLoad.library: FigureLibrary? get() = (this as? FigureLoad.Loaded)?.library

/** Swift `FigureStore`: the bundled `figures/figures.json`, parsed once off the main thread on first use. */
@Singleton
class FigureStore
    @Inject
    constructor(
        @ApplicationContext context: Context,
        events: EventLibrary,
        @AppScope scope: CoroutineScope,
    ) {
        val state: StateFlow<FigureLoad> =
            flow {
                val loaded =
                    try {
                        val text = context.assets.open(ASSET).use { it.readBytes().decodeToString() }
                        FigureLoad.Loaded(FigureLibrary(text, events.events))
                    } catch (_: Exception) {
                        // Unreadable, malformed or invalid data (Swift `FigureLibrary.Failure`, `DecodingError`).
                        FigureLoad.Failed
                    }
                emit(loaded)
            }.flowOn(Dispatchers.IO)
                .stateIn(scope, SharingStarted.Lazily, FigureLoad.Loading)

        private companion object {
            const val ASSET = "figures/figures.json"
        }
    }

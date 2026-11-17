package com.aljaroudi.muntathir.data.library

import android.app.Activity
import com.aljaroudi.muntathir.assets.AssetPackBackend
import com.aljaroudi.muntathir.assets.ContentPack
import com.aljaroudi.muntathir.assets.PlayAssetPack
import com.aljaroudi.muntathir.core.rulings.RulingsAssetStore
import com.aljaroudi.muntathir.core.rulings.RulingsReader
import com.aljaroudi.muntathir.core.rulings.RulingsState
import com.aljaroudi.muntathir.data.AppScope
import com.aljaroudi.muntathir.data.BundledContentSql
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/** The rulings pack for the whole app, read where Play installs it. `core`'s [RulingsAssetStore] on the main thread. */
@Singleton
class RulingsLibrary
    @Inject
    constructor(
        private val backend: AssetPackBackend,
        @AppScope scope: CoroutineScope,
    ) {
        private val main = CoroutineScope(scope.coroutineContext + Dispatchers.Main.immediate)
        private val pack = PlayAssetPack(backend, ContentPack.Rulings)

        @OptIn(ExperimentalCoroutinesApi::class)
        private val store =
            RulingsAssetStore(pack, RulingsReader(BundledContentSql.Driver, Dispatchers.IO.limitedParallelism(1)))

        val reader: RulingsReader get() = store.reader
        val state: StateFlow<RulingsState> = store.state

        init {
            main.launch { store.refresh() }
            main.launch { pack.events().collect { store.receive(it) } }
        }

        fun refresh() {
            main.launch { store.refresh() }
        }

        fun download() {
            main.launch { store.download() }
        }

        fun remove() {
            main.launch { store.remove() }
        }

        fun clearStorageError() = store.clearStorageError()

        fun confirm(activity: Activity) {
            main.launch { runCatching { backend.confirm(activity) } }
        }
    }

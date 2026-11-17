package com.aljaroudi.muntathir.data.library

import android.app.Activity
import android.content.Context
import android.os.storage.StorageManager
import com.aljaroudi.muntathir.assets.AssetPackBackend
import com.aljaroudi.muntathir.assets.ContentPack
import com.aljaroudi.muntathir.assets.PlayAssetPack
import com.aljaroudi.muntathir.core.hadith.HadithAssetStore
import com.aljaroudi.muntathir.core.hadith.HadithDatabase
import com.aljaroudi.muntathir.core.hadith.HadithLocalLibrary
import com.aljaroudi.muntathir.core.hadith.HadithReader
import com.aljaroudi.muntathir.core.hadith.LibraryState
import com.aljaroudi.muntathir.core.hadith.LibraryStatus
import com.aljaroudi.muntathir.data.BundledContentSql
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.io.File
import java.io.IOException

/**
 * One hadith-schema library (Hadith or Supplications) for the whole app: the Play pack is copied into
 * `no_backup/Libraries/<pack>/library.db` and removed, books can be removed and restored, and [reader] answers
 * every query. `core`'s [HadithAssetStore] holds the state machine, driven here on the main thread.
 *
 * Copies and book removals take a while on large libraries, so they run under [LibraryWorker], which keeps the
 * process alive (expedited work) until they finish; an interrupted install resumes on the next start.
 */
class ContentLibrary(
    private val context: Context,
    val pack: ContentPack,
    private val backend: AssetPackBackend,
    scope: CoroutineScope,
    /** Fast-follow packs: request the download once when the pack is missing (and the user didn't remove it). */
    autoDownload: Boolean = false,
) {
    private val main = CoroutineScope(scope.coroutineContext + Dispatchers.Main.immediate)
    private val assetPack = PlayAssetPack(backend, pack)
    private val directory = File(context.noBackupFilesDir, "Libraries")

    /** One connection, confined to one thread at a time. */
    @OptIn(ExperimentalCoroutinesApi::class)
    val reader = HadithReader(BundledContentSql.Driver, Dispatchers.IO.limitedParallelism(1))

    private val store =
        HadithAssetStore(
            packID = pack.packName,
            pack = assetPack,
            reader = reader,
            flags = FilePackFlags(File(directory, "${pack.packName}.state.json"), scope),
            scope = main,
            fileName = File(pack.database).name,
            library =
                HadithLocalLibrary(
                    File(directory, pack.packName),
                    BundledContentSql.Driver,
                    reserveSpace = ::reserveSpace,
                ),
            validateIntegrity = { HadithDatabase.scan(BundledContentSql.Driver, it) },
        )

    val state: StateFlow<LibraryState> = store.state

    init {
        main.launch {
            store.refresh()
            if (autoDownload && state.value.status == LibraryStatus.Missing && !store.userRemoved) store.download()
        }
        main.launch { assetPack.events().collect { store.receive(it) } }
        // Swift `monitor()`: while downloading, check every 2 s for a transfer stuck at 100%.
        main.launch {
            state.map { it.isDownloading }.distinctUntilChanged().collectLatest { downloading ->
                while (downloading) {
                    delay(2_000)
                    store.reconcile(System.currentTimeMillis())
                }
            }
        }
        main.launch {
            state
                .map { it.preparing }
                .distinctUntilChanged()
                .filter { it }
                .collect { LibraryWorker.keepAlive(context, pack) }
        }
    }

    /** Swift scene activation: finish interrupted downloads and notice external changes. */
    fun onForeground() {
        main.launch { store.refresh() }
    }

    /** Swift cancels the integrity scan in the background; it restarts on the next refresh. */
    fun onBackground() {
        store.cancelIntegrityCheck()
    }

    fun download(title: String? = null) {
        main.launch { store.download(title) }
    }

    fun remove(title: String) {
        main.launch { store.remove(title) }
    }

    fun removeAll() {
        main.launch { store.remove() }
    }

    fun refresh() {
        main.launch { store.refresh() }
    }

    /** A query failed: forget the integrity receipt so the next refresh rescans. */
    fun invalidateValidation() = store.invalidateValidation()

    fun clearStorageError() = store.clearStorageError()

    /** Play's mobile-data or download confirmation dialog. */
    fun confirm(activity: Activity) {
        main.launch { runCatching { backend.confirm(activity) } }
    }

    /** Reserves room for the copy and for `VACUUM`'s temporary copy, clearing caches if needed. */
    private fun reserveSpace(
        directory: File,
        bytes: Long,
    ) {
        val storage = context.getSystemService(StorageManager::class.java)
        val volume = storage.getUuidForPath(directory)
        val needed = bytes * 2
        if (storage.getAllocatableBytes(volume) < needed) throw IOException("Not enough storage")
        storage.allocateBytes(volume, needed)
    }
}

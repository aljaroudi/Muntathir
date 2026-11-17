package com.aljaroudi.muntathir.core.rulings

import com.aljaroudi.muntathir.core.assets.AssetPack
import com.aljaroudi.muntathir.core.hadith.HadithDatabaseException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import java.io.File

enum class RulingsStatus { Checking, Missing, Downloading, Ready, Failed, Incompatible }

data class RulingsState(
    val status: RulingsStatus = RulingsStatus.Checking,
    val progress: Float? = null,
    val needsConfirmation: Boolean = false,
    val installedBytes: Long = 0,
    /** Bumps when the database changes: screens reload. */
    val revision: Int = 0,
    val busy: Boolean = false,
    val storageError: Boolean = false,
)

/**
 * The rulings pack, read where Play installs it. Port of Swift `RulingsAssetStore`; call it from one thread.
 */
class RulingsAssetStore(
    private val pack: AssetPack,
    val reader: RulingsReader,
    private val fileName: String = "rulings.db",
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val mutable = MutableStateFlow(RulingsState())
    val state: StateFlow<RulingsState> = mutable.asStateFlow()
    private val current get() = mutable.value

    private var pendingRefresh = false
    private var downloading = false
    private var signature: String? = null

    suspend fun refresh() {
        if (current.busy) {
            pendingRefresh = true
            return
        }
        set { copy(busy = true) }
        try {
            val file = pack.localDirectory()?.let { File(it, fileName) }?.takeIf { withContext(io) { it.isFile } }
            if (file != null) {
                val (size, modified) = withContext(io) { file.length() to file.lastModified() }
                val signature = "${file.path}|$size|$modified"
                if (signature != this.signature) {
                    reader.install(file)
                    this.signature = signature
                    set { copy(revision = revision + 1) }
                }
                set { copy(installedBytes = size, status = RulingsStatus.Ready) }
            } else {
                reader.install(null)
                signature = null
                val active = pack.isDownloading()
                set {
                    copy(
                        installedBytes = 0,
                        status = if (downloading || active) RulingsStatus.Downloading else RulingsStatus.Missing,
                    )
                }
            }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (error: Exception) {
            signature = null
            runCatching { reader.install(null) }
            val incompatible = error is HadithDatabaseException.Incompatible
            set {
                copy(
                    installedBytes = 0,
                    status = if (incompatible) RulingsStatus.Incompatible else RulingsStatus.Failed,
                )
            }
        }
        set { copy(busy = false) }
        if (pendingRefresh) {
            pendingRefresh = false
            refresh()
        }
    }

    suspend fun download() {
        if (downloading || current.busy) return
        downloading = true
        set { copy(status = RulingsStatus.Downloading, progress = null, needsConfirmation = false) }
        try {
            pack.download()
            downloading = false
            signature = null
            refresh()
        } catch (cancellation: CancellationException) {
            downloading = false
            throw cancellation
        } catch (_: Exception) {
            downloading = false
            set { copy(status = RulingsStatus.Failed) }
        }
    }

    suspend fun remove() {
        if (current.busy || downloading || current.status == RulingsStatus.Downloading) return
        set { copy(busy = true) }
        try {
            pack.remove()
            reader.install(null)
            signature = null
            set { copy(installedBytes = 0, revision = revision + 1, status = RulingsStatus.Missing) }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Exception) {
            set { copy(storageError = true) }
        }
        set { copy(busy = false) }
        if (pendingRefresh) {
            pendingRefresh = false
            refresh()
        }
    }

    suspend fun receive(event: AssetPack.Event) {
        when (event) {
            AssetPack.Event.Began -> {
                set { copy(status = RulingsStatus.Downloading) }
            }

            is AssetPack.Event.Progress -> {
                set { copy(progress = event.fraction, needsConfirmation = false, status = RulingsStatus.Downloading) }
            }

            is AssetPack.Event.NeedsConfirmation -> {
                set { copy(needsConfirmation = event.waiting) }
            }

            AssetPack.Event.Finished -> {
                signature = null
                refresh()
            }

            AssetPack.Event.Failed -> {
                set { copy(status = RulingsStatus.Failed) }
            }
        }
    }

    fun clearStorageError() = set { copy(storageError = false) }

    private inline fun set(change: RulingsState.() -> RulingsState) = mutable.update(change)
}

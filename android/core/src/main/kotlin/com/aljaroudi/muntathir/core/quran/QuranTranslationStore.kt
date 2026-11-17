package com.aljaroudi.muntathir.core.quran

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

/** The one downloadable pack holding every translation but English. Swift `AssetPackBackend` for Quran. */
interface TranslationPack {
    /** The installed pack's folder of `<id>.db` files, or `null`; never starts a download. */
    suspend fun localDirectory(): File?

    /** Whether the store (Play) is already fetching the pack. */
    suspend fun isDownloading(): Boolean

    /** Fetches the pack, returning once it's installed and throwing when it fails. */
    suspend fun download()

    suspend fun remove()

    fun events(): Flow<Event>

    sealed interface Event {
        data object Began : Event

        data class Progress(
            val fraction: Float,
        ) : Event

        data object Finished : Event

        data object Failed : Event

        /** Play waits for Wi-Fi or for the user to confirm the download. */
        data class NeedsConfirmation(
            val waiting: Boolean,
        ) : Event
    }
}

enum class DownloadState { Idle, Downloading, Installing, Failed }

/** Everything the reader, daily ayah, picker and Downloads show. */
data class TranslationState(
    /** [QuranTranslation.AUTO], [QuranTranslation.NONE] or a catalog id. */
    val selection: String = QuranTranslation.AUTO,
    /** The resolved translation, installed or not; `null` for none. */
    val active: QuranTranslation? = null,
    /** Bumps whenever the active translation or installed files change: readers reload and search caches reset. */
    val revision: Int = 0,
    val downloadState: DownloadState = DownloadState.Idle,
    /** 0…1 once Play reports progress. */
    val progress: Float? = null,
    /** Downloading, with no word from Play yet. */
    val preparing: Boolean = false,
    /** Play needs the user to allow mobile data or confirm the download. */
    val needsConfirmation: Boolean = false,
    /** Downloaded translations (not English) and their sizes in bytes. */
    val installedSizes: Map<String, Long> = emptyMap(),
    /** Cleanup failed; some files may remain. */
    val storageError: Boolean = false,
    val busy: Boolean = false,
) {
    fun isInstalled(id: String) = id == QuranTranslation.BUNDLED_ID || id in installedSizes

    /** The translation to show: the active one when it's installed. */
    val activeID: String? get() = active?.id?.takeIf(::isInstalled)

    val isDownloading: Boolean get() =
        downloadState == DownloadState.Downloading ||
            downloadState == DownloadState.Installing
}

/**
 * Port of Swift `QuranTranslationStore`: the selection and every download/install/remove transition. Call it from
 * one thread (the app's main thread, a test's event loop); file work runs on [io].
 */
class QuranTranslationStore(
    private val files: QuranTranslationFiles,
    private val pack: TranslationPack,
    selection: String,
    private var languages: List<Locale>,
    /** Persists the selection. */
    private val save: (String) -> Unit = {},
    /** Called with the installed files before each revision is published, and whenever they change. */
    private val installedChanged: (Map<String, File>) -> Unit = {},
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val mutable: MutableStateFlow<TranslationState>
    val state: StateFlow<TranslationState>

    private var requesting = false
    private var requestJob: Job? = null
    private var requestGeneration = 0
    private var completedTransferAt: Long? = null

    init {
        val initial = selection.takeIf(QuranTranslation::isValidSelection) ?: QuranTranslation.AUTO
        mutable = MutableStateFlow(TranslationState(initial, QuranTranslation.resolve(initial, languages)))
        state = mutable.asStateFlow()
        installedChanged(runCatching { files.installedFiles() }.getOrDefault(emptyMap()))
    }

    private val current get() = mutable.value

    fun select(value: String) {
        if (value == current.selection || !QuranTranslation.isValidSelection(value)) return
        save(value)
        mutable.update { it.copy(selection = value, active = QuranTranslation.resolve(value, languages)) }
        changed()
    }

    /** After a language change, re-resolves Auto; publishes only when the result differs. */
    fun activate(languages: List<Locale>) {
        this.languages = languages
        val resolved = QuranTranslation.resolve(current.selection, languages)
        if (resolved != current.active) {
            mutable.update { it.copy(active = resolved) }
            changed()
        }
    }

    suspend fun refresh() {
        if (current.busy) return
        mutable.update { it.copy(busy = true) }
        try {
            if (io { files.read() }.pending != null) {
                val directory = pack.localDirectory()
                when {
                    directory != null -> {
                        mutable.update { it.copy(downloadState = DownloadState.Installing) }
                        io { files.install(directory) }
                        mutable.update { it.copy(downloadState = DownloadState.Idle, needsConfirmation = false) }
                        completedTransferAt = null
                        finishRequest()
                        updateAvailability(force = true)
                    }

                    pack.isDownloading() || requesting -> {
                        mutable.update {
                            it.copy(
                                downloadState = DownloadState.Downloading,
                                preparing =
                                    it.preparing && requesting,
                            )
                        }
                    }

                    else -> {
                        mutable.update { it.copy(downloadState = DownloadState.Failed) }
                    }
                }
            }
            if (io { files.read() }.needsPackCleanup) {
                try {
                    pack.remove()
                    io { files.write(files.read().copy(needsPackCleanup = false)) }
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Exception) {
                    mutable.update { it.copy(storageError = true) }
                }
            }
            try {
                io { files.cleanOrphans() }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Exception) {
                mutable.update { it.copy(storageError = true) }
            }
            updateAvailability()
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Exception) {
            finishRequest()
            mutable.update { it.copy(downloadState = DownloadState.Failed) }
            runCatching { updateAvailability() }
        } finally {
            mutable.update { it.copy(busy = false) }
        }
    }

    /**
     * Downloads [requested] (or everything). The first download installs every language, since the pack holds
     * them all. Returns once the request ends; progress arrives through [receive].
     */
    suspend fun download(requested: String? = null) =
        coroutineScope {
            if (current.busy || requesting || current.isDownloading) return@coroutineScope
            val retry = current.downloadState == DownloadState.Failed
            mutable.update {
                it.copy(
                    busy = true,
                    storageError = false,
                    downloadState = DownloadState.Downloading,
                    preparing = true,
                    progress = null,
                    needsConfirmation = false,
                )
            }
            completedTransferAt = null
            try {
                // A failed installation may have left corrupt files; retry with a fresh pack.
                if (retry && io { files.read() }.pending != null && pack.localDirectory() != null) pack.remove()
                io { files.prepare(requested) }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Exception) {
                mutable.update { it.copy(busy = false, downloadState = DownloadState.Failed, preparing = false) }
                return@coroutineScope
            }
            requesting = true
            val generation = ++requestGeneration
            mutable.update { it.copy(busy = false) }
            var failed = false
            val job =
                launch {
                    try {
                        pack.download()
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (_: Exception) {
                        failed = true
                    }
                }
            requestJob = job
            job.join()
            // A newer request, removal or install finished this one.
            if (generation != requestGeneration) return@coroutineScope
            requesting = false
            requestJob = null
            refresh()
            if (failed && io { files.read() }.pending != null) {
                mutable.update { it.copy(downloadState = DownloadState.Failed, preparing = false) }
            }
        }

    suspend fun remove(ids: List<String>) {
        if (current.busy || current.isDownloading || requesting) return
        mutable.update { it.copy(busy = true, storageError = false) }
        try {
            // Abandon an interrupted request first so it can't restore deleted files later.
            io {
                files.write(files.read().copy(pending = null, needsPackCleanup = true))
                files.remove(ids)
            }
            updateAvailability()
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Exception) {
            mutable.update { it.copy(storageError = true) }
            runCatching { updateAvailability() }
        }
        mutable.update { it.copy(busy = false, downloadState = DownloadState.Idle) }
        refresh()
    }

    suspend fun receive(event: TranslationPack.Event) {
        when (event) {
            TranslationPack.Event.Began -> {
                if (current.downloadState != DownloadState.Installing && io { files.read() }.pending != null) {
                    mutable.update { it.copy(preparing = false, downloadState = DownloadState.Downloading) }
                }
            }

            is TranslationPack.Event.Progress -> {
                if (current.downloadState == DownloadState.Downloading) {
                    mutable.update {
                        it.copy(
                            preparing = false,
                            progress = event.fraction.coerceIn(0f, 1f),
                            needsConfirmation = false,
                        )
                    }
                }
            }

            is TranslationPack.Event.NeedsConfirmation -> {
                if (current.downloadState ==
                    DownloadState.Downloading
                ) {
                    mutable.update { it.copy(needsConfirmation = event.waiting) }
                }
            }

            TranslationPack.Event.Finished -> {
                refresh()
            }

            TranslationPack.Event.Failed -> {
                finishRequest()
                refresh()
                if (io { files.read() }.pending != null) {
                    mutable.update { it.copy(downloadState = DownloadState.Failed, preparing = false) }
                }
            }
        }
    }

    /** Runs every few seconds while downloading: a transfer stuck at 100% for two minutes becomes retryable. */
    suspend fun reconcile(now: Long) {
        if (!current.isDownloading) return
        refresh()
        if (current.downloadState != DownloadState.Downloading || (current.progress ?: 0f) < 1f) return
        val since = completedTransferAt ?: now.also { completedTransferAt = it }
        if (now - since >= STALL_MILLIS) {
            finishRequest()
            mutable.update { it.copy(downloadState = DownloadState.Failed, preparing = false) }
        }
    }

    fun clearStorageError() = mutable.update { it.copy(storageError = false) }

    private fun finishRequest() {
        requestGeneration++
        requesting = false
        requestJob?.cancel()
        requestJob = null
    }

    private suspend fun updateAvailability(force: Boolean = false) {
        val installed = io { files.installedFiles() }
        val sizes = installed.mapValues { it.value.length() }
        if (force || sizes != current.installedSizes) {
            installedChanged(installed)
            mutable.update { it.copy(installedSizes = sizes) }
            changed()
        }
    }

    private fun changed() = mutable.update { it.copy(revision = it.revision + 1) }

    private suspend fun <T> io(block: suspend () -> T): T = withContext(io) { block() }

    companion object {
        const val STALL_MILLIS = 120_000L
    }
}

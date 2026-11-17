package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.assets.AssetPack
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File

enum class LibraryStatus { Checking, Missing, Downloading, Installing, Ready, Failed, Incompatible }

/** Everything the library screens and Downloads show. */
data class LibraryState(
    val status: LibraryStatus = LibraryStatus.Checking,
    /** Titles in the local library (installed or removed), when the store has one. */
    val books: List<DownloadedBook> = emptyList(),
    /** 0…1 once the pack reports progress. */
    val progress: Float? = null,
    val downloadStarted: Boolean = false,
    /** Play waits for Wi-Fi or for the user to confirm the download. */
    val needsConfirmation: Boolean = false,
    val installedBytes: Long = 0,
    val hasLocalAsset: Boolean = false,
    /** Bumps whenever the reader's database changes: screens reload. */
    val revision: Int = 0,
    val busy: Boolean = false,
    /** Copying the pack into the library or removing a book: long, disk-heavy work the app keeps alive. */
    val preparing: Boolean = false,
    val storageError: Boolean = false,
    val storageErrorMessage: String = "",
    val fullValidationCount: Int = 0,
) {
    val isDownloading: Boolean get() = status == LibraryStatus.Downloading || status == LibraryStatus.Installing

    /** Downloading, with no word from the pack yet. */
    val preparingDownload: Boolean get() = isDownloading && !downloadStarted && progress == null
}

/** The device-local flags Swift keeps in `UserDefaults` as `<packID>.restoring`/`.cleanup`/`.removed`/`.validated.v1`. */
@Serializable
data class PackFlags(
    /** A title being restored, `""` to reinstall everything after a failure, or `null`. */
    val restoring: String? = null,
    /** The hosted pack was copied into the library and still needs removing. */
    val cleanup: Boolean = false,
    /** The user removed everything: pack events are ignored until they download again. */
    val removed: Boolean = false,
    /** The signature of the last library that passed the full integrity scan. */
    val validated: String? = null,
)

interface PackFlagStore {
    fun read(): PackFlags

    fun write(flags: PackFlags)
}

class MemoryPackFlags(
    private var value: PackFlags = PackFlags(),
) : PackFlagStore {
    override fun read() = value

    override fun write(flags: PackFlags) {
        value = flags
    }
}

/**
 * Downloads, installs, validates and removes one hadith or supplications pack. Port of Swift `HadithAssetStore`.
 * With a [library], the pack is copied into it and removed, and single books can be removed and restored.
 *
 * Call it from one thread (the app's main thread, a test's event loop); file work runs on [io] and the
 * background integrity scan in [scope].
 */
class HadithAssetStore(
    val packID: String,
    private val pack: AssetPack,
    val reader: HadithReader,
    private val flags: PackFlagStore,
    private val scope: CoroutineScope,
    /** The database's name inside the pack folder, e.g. `hadith.db`. */
    private val fileName: String = "$packID.db",
    private val library: HadithLocalLibrary? = null,
    private val validateIntegrity: suspend (File) -> Unit,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val mutable = MutableStateFlow(LibraryState())
    val state: StateFlow<LibraryState> = mutable.asStateFlow()
    private val current get() = mutable.value

    /** Whether the user removed everything (and hasn't downloaded since). */
    val userRemoved: Boolean get() = flags.read().removed

    /** The running background integrity scan, if any. */
    var integrityCheck: Job? = null
        private set

    private var installedSignature: String? = null
    private var refreshPending = false
    private var downloadGeneration = 0
    private var pendingDownload: Int? = null
    private var downloadJob: Job? = null
    private var progressSample: Pair<Long, Float>? = null
    private var transferFinishedAt: Long? = null

    fun cancelIntegrityCheck() {
        integrityCheck?.cancel()
    }

    /** Forgets the integrity receipt, e.g. after a query failed: the next refresh rescans. */
    fun invalidateValidation() {
        integrityCheck?.cancel()
        forgetValidation()
    }

    fun clearStorageError() = set { copy(storageError = false) }

    suspend fun refresh() {
        if (current.busy) {
            refreshPending = true
            return
        }
        set { copy(busy = true) }
        resolve()
        finishOperation()
    }

    private suspend fun resolve() {
        if (flags.read().removed) {
            set { copy(status = LibraryStatus.Missing) }
            return
        }
        try {
            var local = library?.localFile()
            // A freshly prepared library passed `integrity_check`, so it needs no background scan.
            var prepared = false
            if (library == null || local == null || flags.read().restoring != null) {
                managedFile()?.let { managed ->
                    local = if (library != null) copyIntoLibrary(library, managed).also { prepared = true } else managed
                }
            }
            if (library != null) {
                val books = library.books()
                set { copy(books = books) }
                if (flags.read().cleanup) {
                    try {
                        pack.remove()
                        updateFlags { copy(cleanup = false) }
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (error: Exception) {
                        storageError(error)
                    }
                }
            }
            val file = local
            if (file == null) {
                integrityCheck?.cancel()
                reader.install(null)
                forgetValidation()
                val downloading = pack.isDownloading()
                set {
                    copy(
                        hasLocalAsset = false,
                        installedBytes = 0,
                        downloadStarted = downloadStarted || (downloading && pendingDownload == null),
                        status =
                            if (downloading ||
                                pendingDownload != null
                            ) {
                                LibraryStatus.Downloading
                            } else {
                                LibraryStatus.Missing
                            },
                    )
                }
                return
            }
            val (size, modified) = withContext(io) { file.length() to file.lastModified() }
            set { copy(hasLocalAsset = true, installedBytes = size) }
            val signature = "validation-1|${file.path}|$size|$modified"
            if (signature != installedSignature) {
                integrityCheck?.cancel()
                set { copy(status = if (isDownloading) LibraryStatus.Installing else LibraryStatus.Checking) }
                reader.install(file)
                installedSignature = signature
                set { copy(revision = revision + 1) }
                when {
                    prepared -> updateFlags { copy(validated = signature) }
                    flags.read().validated != signature -> startIntegrityCheck(file, signature)
                }
            }
            val downloading = pack.isDownloading()
            set {
                copy(
                    status =
                        when {
                            flags.read().restoring == null -> LibraryStatus.Ready
                            pendingDownload != null || downloading -> LibraryStatus.Downloading
                            else -> LibraryStatus.Failed
                        },
                )
            }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: HadithDatabaseException.Incompatible) {
            forgetValidation()
            set { copy(status = LibraryStatus.Incompatible) }
        } catch (error: Exception) {
            if (library != null) storageError(error)
            forgetValidation()
            set { copy(status = LibraryStatus.Failed) }
        }
    }

    /** Copies the hosted pack into [library] (keeping removed books removed) and swaps it in. */
    private suspend fun copyIntoLibrary(
        library: HadithLocalLibrary,
        managed: File,
    ): File {
        set { copy(status = LibraryStatus.Installing, preparing = true) }
        try {
            val staged = library.prepare(managed, restoring = flags.read().restoring)
            try {
                updateFlags { copy(cleanup = true) }
                reader.commit(staged, library.file)
                updateFlags { copy(restoring = null) }
                return library.file
            } finally {
                staged.delete()
            }
        } finally {
            set { copy(preparing = false) }
        }
    }

    private fun startIntegrityCheck(
        file: File,
        signature: String,
    ) {
        integrityCheck =
            scope.launch {
                try {
                    withContext(io) { validateIntegrity(file) }
                } catch (cancellation: CancellationException) {
                    throw cancellation
                } catch (_: Exception) {
                    if (installedSignature != signature) return@launch
                    forgetValidation()
                    set { copy(status = LibraryStatus.Failed, revision = revision + 1) }
                    runCatching { reader.install(null) }
                    return@launch
                }
                if (installedSignature != signature) return@launch
                updateFlags { copy(validated = signature) }
                set { copy(fullValidationCount = fullValidationCount + 1) }
            }
    }

    /**
     * Downloads the pack, or with [title] restores that one book. Returns once the request ends; progress and
     * completion also arrive through [receive].
     */
    suspend fun download(title: String? = null): Unit =
        coroutineScope {
            if (current.busy || (current.status == LibraryStatus.Ready && title == null) || pendingDownload != null) {
                return@coroutineScope
            }
            if (flags.read().removed) {
                if (title != null) return@coroutineScope
                updateFlags { copy(removed = false) }
            }
            val invalid = current.status == LibraryStatus.Failed || current.status == LibraryStatus.Incompatible
            if (title != null) {
                updateFlags { copy(restoring = title) }
            } else if (library != null && invalid && flags.read().restoring == null) {
                updateFlags { copy(restoring = "") }
            }
            set {
                copy(
                    busy = true,
                    status = LibraryStatus.Downloading,
                    progress = null,
                    downloadStarted = false,
                    needsConfirmation = false,
                )
            }
            progressSample = null
            transferFinishedAt = null
            val generation = ++downloadGeneration
            pendingDownload = generation
            try {
                if (invalid && pack.localDirectory() != null) {
                    forgetValidation()
                    if (library == null) reader.install(null)
                    pack.remove()
                }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Exception) {
                pendingDownload = null
                resolve()
                if (current.status != LibraryStatus.Ready && current.status != LibraryStatus.Incompatible) {
                    set { copy(status = LibraryStatus.Failed) }
                }
                finishOperation()
                return@coroutineScope
            }
            // The network wait must not block finished events or local availability checks.
            finishOperation()
            if (generation != downloadGeneration) return@coroutineScope
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
            downloadJob = job
            job.join()
            // A newer request, removal or stall finished this one.
            if (generation != downloadGeneration) return@coroutineScope
            pendingDownload = null
            downloadJob = null
            if (!failed) {
                refresh()
                return@coroutineScope
            }
            // An in-flight validation already decides whether the local content is usable.
            if (current.busy) {
                refreshPending = true
                return@coroutineScope
            }
            // An older compatible pack stays useful if an update fails offline.
            refresh()
            if (generation != downloadGeneration) return@coroutineScope
            if (flags.read().restoring != null ||
                (current.status != LibraryStatus.Ready && current.status != LibraryStatus.Incompatible)
            ) {
                set { copy(status = LibraryStatus.Failed) }
            }
        }

    /** Removes one book from the library; it can be restored with [download]. */
    suspend fun remove(title: String) {
        val library = library ?: return
        if (current.busy || current.isDownloading || current.books.none { it.id == title && it.installed }) return
        set { copy(busy = true, storageError = false, preparing = true) }
        integrityCheck?.cancel()
        try {
            val source = library.localFile() ?: throw HadithDatabaseException.Unavailable()
            val staged = library.prepare(source, removing = title)
            try {
                reader.commit(staged, library.file)
            } finally {
                staged.delete()
            }
            forgetValidation()
            resolve()
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (error: Exception) {
            storageError(error)
        } finally {
            set { copy(preparing = false) }
        }
        finishOperation()
    }

    /** Removes everything; pack events are ignored until the next [download]. */
    suspend fun remove() {
        if (current.busy) return
        set { copy(busy = true, storageError = false, status = LibraryStatus.Checking, revision = revision + 1) }
        integrityCheck?.cancel()
        abandonDownload()
        try {
            forgetValidation()
            reader.install(null)
            val managed = pack.localDirectory()
            val downloading = pack.isDownloading()
            if (library == null || managed != null || downloading) pack.remove()
            library?.remove()
            updateFlags { copy(removed = true, restoring = null, cleanup = false, validated = null) }
            set {
                copy(books = emptyList(), hasLocalAsset = false, installedBytes = 0, status = LibraryStatus.Missing)
            }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (error: Exception) {
            storageError(error)
            resolve()
            if (current.status != LibraryStatus.Ready) set { copy(status = LibraryStatus.Failed) }
        }
        finishOperation()
    }

    suspend fun receive(event: AssetPack.Event) {
        if (flags.read().removed) return
        val status = current.status
        when (event) {
            AssetPack.Event.Began -> {
                if (status != LibraryStatus.Ready && status != LibraryStatus.Installing) {
                    if (status != LibraryStatus.Downloading) progressSample = null
                    set {
                        copy(
                            downloadStarted = true,
                            progress = if (status == LibraryStatus.Downloading) progress else null,
                            status = LibraryStatus.Downloading,
                        )
                    }
                } else {
                    set { copy(downloadStarted = true) }
                }
            }

            is AssetPack.Event.Progress -> {
                if (status == LibraryStatus.Ready || status == LibraryStatus.Installing) return
                val fraction = event.fraction.coerceIn(0f, 1f)
                if (status == LibraryStatus.Downloading && fraction < (current.progress ?: 0f)) return
                if (progressSample == null) progressSample = now() to fraction
                set {
                    copy(
                        downloadStarted = true,
                        progress = fraction,
                        needsConfirmation = false,
                        status = LibraryStatus.Downloading,
                    )
                }
            }

            is AssetPack.Event.NeedsConfirmation -> {
                if (current.isDownloading) set { copy(needsConfirmation = event.waiting) }
            }

            AssetPack.Event.Finished -> {
                pendingDownload = null
                refresh()
                if (current.status == LibraryStatus.Missing && !flags.read().removed) {
                    set { copy(status = LibraryStatus.Failed) }
                }
            }

            AssetPack.Event.Failed -> {
                pendingDownload = null
                if (!current.busy) {
                    refresh()
                    val after = current.status
                    if (after != LibraryStatus.Ready && after != LibraryStatus.Incompatible && !flags.read().removed) {
                        set { copy(status = LibraryStatus.Failed) }
                    }
                }
            }
        }
    }

    /** Time left, extrapolated from progress since the first report at least two seconds ago. */
    fun estimatedRemainingMillis(at: Long): Long? {
        val progress = current.progress ?: return null
        if (progress <= 0f || progress >= 1f) return null
        val (time, fraction) = progressSample ?: return null
        val elapsed = at - time
        val advanced = progress - fraction
        if (elapsed < 2_000 || advanced <= 0f) return null
        return (elapsed * (1 - progress) / advanced).toLong()
    }

    /** Runs every few seconds while downloading: a transfer stuck at 100% for two minutes becomes retryable. */
    suspend fun reconcile(at: Long) {
        if (!current.isDownloading) return
        refresh()
        if (current.status != LibraryStatus.Downloading || (current.progress ?: 0f) < 1f) return
        val since = transferFinishedAt ?: at.also { transferFinishedAt = it }
        if (at - since >= STALL_MILLIS) {
            abandonDownload()
            set { copy(status = LibraryStatus.Failed) }
        }
    }

    /** Ends the current download request: its late result is ignored. */
    private fun abandonDownload() {
        downloadGeneration++
        pendingDownload = null
        downloadJob?.cancel()
        downloadJob = null
    }

    private suspend fun managedFile(): File? =
        pack.localDirectory()?.let { File(it, fileName) }?.takeIf { withContext(io) { it.isFile } }

    private suspend fun finishOperation() {
        while (refreshPending) {
            refreshPending = false
            resolve()
        }
        set { copy(busy = false) }
    }

    private fun forgetValidation() {
        installedSignature = null
        updateFlags { copy(validated = null) }
    }

    private fun storageError(error: Exception) =
        set {
            copy(storageError = true, storageErrorMessage = error.message.orEmpty())
        }

    private inline fun updateFlags(change: PackFlags.() -> PackFlags) {
        val old = flags.read()
        val new = old.change()
        if (new != old) flags.write(new)
    }

    private inline fun set(change: LibraryState.() -> LibraryState) = mutable.update(change)

    companion object {
        const val STALL_MILLIS = 120_000L
    }
}

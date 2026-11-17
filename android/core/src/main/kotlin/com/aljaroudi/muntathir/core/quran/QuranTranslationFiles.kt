package com.aljaroudi.muntathir.core.quran

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.io.IOException
import java.util.UUID

/**
 * Downloaded translations under [root] (in `noBackupFilesDir`), published through an atomic `index.json`.
 * Port of Swift `QuranTranslationFiles`: each install copies into a fresh generation folder and is published only
 * after every file validates, so a failed or interrupted install never touches the languages already installed.
 */
class QuranTranslationFiles(
    val root: File,
    private val validate: (File) -> Boolean,
    private val copy: (File, File) -> Unit = { source, target -> source.copyTo(target, overwrite = true) },
) {
    @Serializable
    data class Index(
        /** Id → path relative to [root]. */
        val installed: Map<String, String> = emptyMap(),
        val pending: List<String>? = null,
        val hasInstalled: Boolean = false,
        val needsPackCleanup: Boolean = false,
    )

    private val indexFile get() = File(root, "index.json")

    fun read(): Index = if (indexFile.isFile) json.decodeFromString(indexFile.readText()) else Index()

    fun write(index: Index) {
        root.mkdirs()
        val temporary = File(root, "index.json.tmp")
        temporary.writeText(json.encodeToString(index))
        if (!temporary.renameTo(indexFile)) throw IOException("Unable to write the translation index")
    }

    /** Installed files that exist on disk. */
    fun installedFiles(): Map<String, File> =
        read().installed.mapValues { File(root, it.value) }.filterValues { it.isFile }

    /** Marks what the next install takes: everything the first time, then only [requested] (or everything). */
    fun prepare(requested: String?) {
        val ids = QuranTranslation.downloadable.map { it.id }
        if (requested != null && requested !in ids) throw QuranUnavailableException()
        val index = read()
        write(
            index.copy(
                pending = if (index.hasInstalled) requested?.let(::listOf) ?: ids else ids,
                needsPackCleanup = false,
            ),
        )
    }

    /** Copies and validates every pending translation from [directory], then publishes them together. */
    suspend fun install(directory: File) {
        val index = read()
        val pending = index.pending ?: return
        val generation = UUID.randomUUID().toString().uppercase()
        val staging = File(root, generation).apply { mkdirs() }
        try {
            val installed = index.installed.toMutableMap()
            for (id in pending) {
                currentCoroutineContext().ensureActive()
                if (QuranTranslation.downloadable.none { it.id == id }) throw QuranUnavailableException()
                val target = File(staging, "$id.db")
                copy(File(directory, "$id.db"), target)
                if (!validate(target)) throw QuranUnavailableException()
                installed[id] = "$generation/$id.db"
            }
            write(index.copy(installed = installed, pending = null, hasInstalled = true, needsPackCleanup = true))
        } catch (error: Throwable) {
            staging.deleteRecursively()
            throw error
        }
    }

    fun remove(ids: List<String>) {
        var index = read()
        if (index.pending != null) throw QuranUnavailableException()
        for (id in ids) {
            val relative = index.installed[id] ?: continue
            File(
                root,
                relative,
            ).takeIf { it.exists() }?.let { if (!it.delete()) throw IOException("Unable to delete $id") }
            index = index.copy(installed = index.installed - id)
            write(index)
        }
    }

    /** Reclaims replaced files and interrupted staging folders without touching installed languages. */
    fun cleanOrphans() {
        if (!root.isDirectory) return
        val retained = read().installed.values.toSet()
        for (directory in root.listFiles().orEmpty().filter { it.isDirectory }) {
            for (file in directory.listFiles().orEmpty()) {
                if ("${directory.name}/${file.name}" !in retained && !file.deleteRecursively()) {
                    throw IOException("Unable to delete ${file.name}")
                }
            }
            if (directory.listFiles().isNullOrEmpty() &&
                !directory.delete()
            ) {
                throw IOException("Unable to delete ${directory.name}")
            }
        }
    }

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}

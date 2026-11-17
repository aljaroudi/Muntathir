package com.aljaroudi.muntathir.core.quran

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.Locale
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Ports of Swift `QuranAssetStoreTests` and `QuranTranslationStoreTests`, with the iOS translation databases. */
class QuranTranslationStoreTest {
    private val root: File = Files.createTempDirectory("translations").toFile()
    private val source = JdbcQuranSql.quranFolder

    @AfterTest
    fun cleanUp() {
        root.deleteRecursively()
    }

    private fun files(copy: (File, File) -> Unit = { from, to -> from.copyTo(to, overwrite = true) }) =
        QuranTranslationFiles(root, validate = { QuranReader.isValidTranslation(JdbcQuranSql(it)) }, copy = copy)

    private fun store(
        pack: FakePack,
        languages: List<Locale> = listOf(Locale.ENGLISH),
        onInstalled: (Map<String, File>) -> Unit = {},
    ) = QuranTranslationStore(files(), pack, QuranTranslation.AUTO, languages, installedChanged = onInstalled)

    @Test
    fun selectionPersistsAndNoneOverridesAuto() {
        var saved = ""
        val store =
            QuranTranslationStore(files(), FakePack(source), QuranTranslation.AUTO, listOf(Locale.ENGLISH), save = {
                saved =
                    it
            })
        assertEquals("en.qarai", store.state.value.activeID)
        store.select(QuranTranslation.NONE)
        store.activate(listOf(Locale.GERMAN))
        assertNull(store.state.value.active)
        assertEquals(QuranTranslation.NONE, saved)
        store.select(QuranTranslation.AUTO)
        assertEquals(
            "de.bubenheim",
            store.state.value.active
                ?.id,
        )
    }

    @Test
    fun unchangedSelectionDoesNotReloadReaders() {
        val store = store(FakePack(source))
        val revision = store.state.value.revision
        store.select(QuranTranslation.AUTO)
        store.activate(listOf(Locale.ENGLISH))
        assertEquals(revision, store.state.value.revision)
        store.select(QuranTranslation.NONE)
        assertEquals(revision + 1, store.state.value.revision)
    }

    @Test
    fun installDeleteRestoreAndOfflineRelaunch() =
        runBlocking {
            val pack = FakePack(source)
            var changes = 0
            val store = store(pack) { changes++ }
            store.refresh()
            assertTrue(
                store.state.value.installedSizes
                    .isEmpty(),
            )
            assertTrue(store.state.value.isInstalled("en.qarai"))
            assertEquals(0, pack.downloads)
            store.select("de.bubenheim")
            val before = changes
            store.download("de.bubenheim")
            assertEquals(12, store.state.value.installedSizes.size)
            assertEquals(DownloadState.Idle, store.state.value.downloadState)
            assertFalse(pack.installed)
            assertTrue(changes > before)
            val revision = store.state.value.revision
            store.remove(listOf("de.bubenheim", "es.bornez"))
            assertEquals(10, store.state.value.installedSizes.size)
            assertEquals(
                "de.bubenheim",
                store.state.value.active
                    ?.id,
            )
            assertNull(store.state.value.activeID)
            assertTrue(store.state.value.revision > revision)
            store.download("de.bubenheim")
            assertEquals(11, store.state.value.installedSizes.size)
            assertFalse(store.state.value.isInstalled("es.bornez"))
            assertEquals(2, pack.downloads)
            val relaunched = store(pack)
            relaunched.refresh()
            assertEquals(11, relaunched.state.value.installedSizes.size)
            assertEquals(2, pack.downloads)
            relaunched.remove(QuranTranslation.downloadable.map { it.id })
            assertTrue(
                relaunched.state.value.installedSizes
                    .isEmpty(),
            )
            assertTrue(relaunched.state.value.isInstalled("en.qarai"))
            relaunched.download("ru.kuliev")
            assertEquals(setOf("ru.kuliev"), relaunched.state.value.installedSizes.keys)
        }

    @Test
    fun cleanupFailureNeverReinstallsDeletedLanguages() =
        runBlocking {
            val pack = FakePack(source).apply { removalFails = true }
            val store = store(pack)
            store.download()
            assertTrue(store.state.value.storageError)
            assertEquals(12, store.state.value.installedSizes.size)
            store.remove(listOf("de.bubenheim"))
            assertTrue(files().read().needsPackCleanup)
            val relaunched = store(pack)
            pack.removalFails = false
            relaunched.refresh()
            assertFalse(relaunched.state.value.isInstalled("de.bubenheim"))
            assertEquals(11, relaunched.state.value.installedSizes.size)
            assertFalse(files().read().needsPackCleanup)
            assertEquals(1, pack.downloads)
        }

    @Test
    fun interruptedRequestRecoversLocallyWithoutNetwork() =
        runBlocking {
            files().prepare("de.bubenheim")
            val pack = FakePack(source).apply { installed = true }
            val store = store(pack)
            store.refresh()
            assertEquals(12, store.state.value.installedSizes.size)
            assertEquals(0, pack.downloads)
            assertNull(files().read().pending)
        }

    @Test
    fun networkFailureCanRetry() =
        runBlocking {
            val pack = FakePack(source).apply { suspend = true }
            val store = store(pack)
            val request = launch { store.download() }
            pack.waitForRequest()
            assertTrue(store.state.value.isDownloading)
            assertTrue(store.state.value.preparing)
            assertNull(store.state.value.progress)
            store.receive(TranslationPack.Event.Began)
            assertFalse(store.state.value.preparing)
            store.receive(TranslationPack.Event.Progress(0.4f))
            assertEquals(0.4f, store.state.value.progress)
            pack.downloadFails = true
            pack.resume()
            request.join()
            assertEquals(DownloadState.Failed, store.state.value.downloadState)
            assertFalse(store.state.value.preparing)
            assertTrue(
                store.state.value.installedSizes
                    .isEmpty(),
            )

            pack.downloadFails = false
            pack.suspend = true
            val retry = launch { store.download() }
            pack.waitForRequest()
            assertTrue(store.state.value.preparing)
            assertNull(store.state.value.progress)
            pack.resume()
            retry.join()
            assertEquals(12, store.state.value.installedSizes.size)
        }

    @Test
    fun corruptOrOutOfSpaceInstallPreservesPublishedFiles() =
        runBlocking {
            files().prepare(null)
            files().install(source)
            val original = files().installedFiles()
            files().prepare("de.bubenheim")
            assertFailsWith<IOException> {
                files {
                    _,
                    _,
                    ->
                    throw IOException("No space left on device")
                }.install(source)
            }
            assertEquals(original, files().installedFiles())
            assertFailsWith<QuranUnavailableException> {
                files {
                    _,
                    target,
                    ->
                    target.writeText("invalid SQLite")
                }.install(source)
            }
            assertEquals(original, files().installedFiles())
            assertEquals(listOf("de.bubenheim"), files().read().pending)
            files().install(source)
            assertNull(files().read().pending)
            files().cleanOrphans()
            assertFalse(original.getValue("de.bubenheim").exists())
            assertTrue(files().installedFiles().getValue("es.bornez").exists())
        }

    @Test
    fun finishedEventInstallsWhileRequestWaitsAndLateResultCannotRestoreDeletedLanguage() =
        runBlocking {
            val pack = FakePack(source).apply { suspend = true }
            val store = store(pack)
            val request = launch { store.download() }
            pack.waitForRequest()
            store.receive(TranslationPack.Event.Progress(0.6f))
            assertEquals(0.6f, store.state.value.progress)
            pack.installed = true
            store.receive(TranslationPack.Event.Finished)
            assertEquals(12, store.state.value.installedSizes.size)
            store.remove(listOf("de.bubenheim"))
            pack.resume()
            request.join()
            assertFalse(store.state.value.isInstalled("de.bubenheim"))
            assertEquals(DownloadState.Idle, store.state.value.downloadState)
        }

    @Test
    fun stalledCompletedTransferBecomesRetryable() =
        runBlocking {
            val pack = FakePack(source).apply { suspend = true }
            val store = store(pack)
            val request = launch { store.download() }
            pack.waitForRequest()
            store.receive(TranslationPack.Event.Progress(1f))
            store.reconcile(0)
            store.reconcile(121_000)
            assertEquals(DownloadState.Failed, store.state.value.downloadState)
            pack.resume()
            request.join()
            store.download()
            assertEquals(12, store.state.value.installedSizes.size)
        }

    @Test
    fun missingTranslationLeavesArabicReadable() =
        runBlocking {
            val installed = files().installedFiles()
            val reader =
                QuranReader(
                    arabic = { JdbcQuranSql(source.resolve("quran.db")) },
                    surahs = { JdbcQuranSql.surahs },
                    translation = { id -> installed[id]?.let(::JdbcQuranSql) },
                )
            val verse = reader.verse(1, 1, "de.bubenheim")
            assertTrue(verse?.text?.isNotEmpty() == true)
            assertEquals(emptyMap(), verse?.translations)
        }
}

/** Swift `QuranTestBackend`: the pack folder is the iOS bundle's translations. */
private class FakePack(
    private val source: File,
) : TranslationPack {
    var installed = false
    var downloads = 0
    var removalFails = false
    var downloadFails = false
    var suspend = false
    private var gate: CompletableDeferred<Unit>? = null
    private var waiter: CompletableDeferred<Unit>? = null

    override suspend fun localDirectory() = if (installed) source else null

    override suspend fun isDownloading() = false

    override suspend fun download() {
        downloads++
        if (suspend) {
            val gate = CompletableDeferred<Unit>().also { gate = it }
            waiter?.complete(Unit)
            waiter = null
            gate.await()
        }
        currentCoroutineContext().ensureActive()
        if (downloadFails) throw IOException("Offline")
        installed = true
    }

    override suspend fun remove() {
        if (removalFails) throw IOException("No permission")
        installed = false
    }

    override fun events() = emptyFlow<TranslationPack.Event>()

    suspend fun waitForRequest() {
        if (gate != null) return
        CompletableDeferred<Unit>().also { waiter = it }.await()
    }

    fun resume() {
        suspend = false
        gate?.complete(Unit)
        gate = null
    }
}

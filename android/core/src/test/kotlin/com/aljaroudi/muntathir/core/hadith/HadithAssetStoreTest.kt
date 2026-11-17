package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.assets.AssetPack
import com.aljaroudi.muntathir.core.sql.JdbcDriver
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assume.assumeTrue
import java.io.File
import java.io.IOException
import java.nio.file.Files
import kotlin.system.measureTimeMillis
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of Swift `HadithAssetStoreTests`. */
class HadithAssetStoreTest {
    private val cleanup = mutableListOf<() -> Unit>()

    @AfterTest
    fun cleanUp() = cleanup.forEach { it() }

    private fun fixture(count: Int) = HadithFixture(count).also { cleanup += it::remove }

    private fun temporaryDirectory() =
        Files.createTempDirectory("library").toFile().also { cleanup += { it.deleteRecursively() } }

    private var clock = 0L

    private fun CoroutineScope.store(
        pack: FakeAssets,
        flags: PackFlagStore = MemoryPackFlags(),
        packID: String = "hadith",
        library: HadithLocalLibrary? = null,
        validate: suspend (File) -> Unit = { HadithDatabase.scan(JdbcDriver, it) },
    ) = HadithAssetStore(
        packID = packID,
        pack = pack,
        reader = HadithReader(JdbcDriver),
        flags = flags,
        scope = this,
        fileName = pack.file.name,
        library = library,
        validateIntegrity = validate,
        now = { clock },
    )

    private val HadithAssetStore.status get() = state.value.status

    @Test
    fun supplicationsHaveIndependentDownloadAndValidationState() =
        runBlocking<Unit> {
            val fixture = fixture(1)
            val hadithFlags = MemoryPackFlags()
            val prayerFlags = MemoryPackFlags()
            val hadithBackend = FakeAssets(fixture.file)
            val hadith = store(hadithBackend, hadithFlags)
            val prayers = store(FakeAssets(fixture.file), prayerFlags, packID = "supplications")
            hadith.refresh()
            prayers.download()
            prayers.integrityCheck?.join()
            assertEquals(LibraryStatus.Ready, prayers.status)
            assertEquals(LibraryStatus.Missing, hadith.status)
            assertEquals(0, hadithBackend.downloads)
            assertNotNull(prayerFlags.read().validated)
            assertNull(hadithFlags.read().validated)
            hadith.download()
            hadith.integrityCheck?.join()
            prayers.remove()
            assertEquals(LibraryStatus.Missing, prayers.status)
            assertEquals(LibraryStatus.Ready, hadith.status)
            assertNotNull(hadithFlags.read().validated)
        }

    @Test
    fun explicitDownloadOfflineRelaunchAndRemoval() =
        runBlocking<Unit> {
            val fixture = fixture(1)
            val flags = MemoryPackFlags()
            val backend = FakeAssets(fixture.file)
            val store = store(backend, flags)
            store.refresh()
            assertEquals(LibraryStatus.Missing, store.status)
            assertEquals(0, backend.downloads)
            store.download()
            assertEquals(LibraryStatus.Ready, store.status)
            assertEquals(2, store.reader.catalog().size)
            val relaunched = store(backend, flags)
            relaunched.refresh()
            assertEquals(LibraryStatus.Ready, relaunched.status)
            assertEquals(1, backend.downloads)
            backend.failing = true
            store.remove()
            assertEquals(LibraryStatus.Ready, store.status)
            assertEquals(2, store.reader.catalog().size)
            backend.failing = false
            store.remove()
            assertEquals(LibraryStatus.Missing, store.status)
            assertFailsWith<HadithDatabaseException> { store.reader.catalog() }
            store.download()
            assertEquals(LibraryStatus.Ready, store.status)
            assertEquals(2, backend.downloads)
            listOf(store, relaunched).forEach { it.integrityCheck?.join() }
        }

    @Test
    fun failureRetryAndInterruptedDownload() =
        runBlocking<Unit> {
            val backend = FakeAssets(fixture(1).file).apply { failing = true }
            val store = store(backend)
            store.download()
            assertEquals(LibraryStatus.Failed, store.status)
            backend.failing = false
            backend.downloading = true
            store.refresh()
            assertEquals(LibraryStatus.Downloading, store.status)
            store.download()
            assertEquals(LibraryStatus.Ready, store.status)
            store.integrityCheck?.join()
        }

    @Test
    fun progressCompletionAndExternalRemovalRefreshReader() =
        runBlocking<Unit> {
            val backend = FakeAssets(fixture(1).file)
            val store = store(backend)
            store.receive(AssetPack.Event.Progress(0.4f))
            assertEquals(LibraryStatus.Downloading, store.status)
            assertEquals(0.4f, store.state.value.progress)
            backend.downloading = true
            store.refresh()
            store.receive(AssetPack.Event.Began)
            assertEquals(0.4f, store.state.value.progress)
            backend.download()
            store.receive(AssetPack.Event.Finished)
            assertEquals(LibraryStatus.Ready, store.status)
            val revision = store.state.value.revision
            store.refresh()
            assertEquals(revision, store.state.value.revision)
            store.integrityCheck?.join()
            backend.remove()
            store.refresh()
            assertEquals(LibraryStatus.Missing, store.status)
            assertFailsWith<HadithDatabaseException> { store.reader.catalog() }
        }

    @Test
    fun finishedEventOpensReaderWhileRequestStillWaits() =
        runBlocking<Unit> {
            val backend = FakeAssets(fixture(1).file).apply { suspended = true }
            val store = store(backend)
            val request = launch { store.download() }
            backend.waitForDownload()
            assertFalse(store.state.value.busy)
            assertTrue(store.state.value.preparingDownload)
            store.receive(AssetPack.Event.Progress(0.4f))
            assertFalse(store.state.value.preparingDownload)
            assertEquals(0.4f, store.state.value.progress)
            backend.installed = true
            store.receive(AssetPack.Event.Finished)
            assertEquals(LibraryStatus.Ready, store.status)
            assertEquals(2, store.reader.catalog().size)
            store.remove()
            backend.resume()
            request.join()
            assertEquals(LibraryStatus.Missing, store.status)
        }

    @Test
    fun completedTransferReconcilesWithoutFinishedEvent() =
        runBlocking<Unit> {
            val backend = FakeAssets(fixture(1).file).apply { downloading = true }
            val store = store(backend)
            store.receive(AssetPack.Event.Progress(1f))
            store.reconcile(0)
            assertEquals(LibraryStatus.Downloading, store.status)
            assertNull(store.estimatedRemainingMillis(0))
            backend.installed = true
            store.reconcile(2_000)
            assertEquals(LibraryStatus.Ready, store.status)
            store.integrityCheck?.join()
        }

    @Test
    fun stalledInstallationBecomesRetryable() =
        runBlocking<Unit> {
            val backend = FakeAssets(fixture(1).file).apply { downloading = true }
            val store = store(backend)
            store.receive(AssetPack.Event.Progress(1f))
            store.reconcile(0)
            store.reconcile(121_000)
            assertEquals(LibraryStatus.Failed, store.status)
            store.download()
            assertEquals(LibraryStatus.Ready, store.status)
            store.integrityCheck?.join()
        }

    @Test
    fun progressDoesNotRegressWhenAnOlderEventArrives() =
        runBlocking<Unit> {
            val store = store(FakeAssets(File("/unused/hadith.db")))
            store.receive(AssetPack.Event.Began)
            assertTrue(store.state.value.isDownloading)
            assertNull(store.state.value.progress)
            assertFalse(store.state.value.preparingDownload)
            store.receive(AssetPack.Event.Progress(0.6f))
            store.receive(AssetPack.Event.Progress(0.3f))
            assertEquals(0.6f, store.state.value.progress)
        }

    @Test
    fun estimatedRemainingUsesLiveProgress() =
        runBlocking<Unit> {
            val store = store(FakeAssets(File("/unused/hadith.db")))
            clock = 0
            store.receive(AssetPack.Event.Progress(0.1f))
            assertNull(store.estimatedRemainingMillis(0))
            store.receive(AssetPack.Event.Progress(0.5f))
            assertTrue(store.estimatedRemainingMillis(10_000)!! > 12_000)
            store.receive(AssetPack.Event.Progress(1f))
            assertNull(store.estimatedRemainingMillis(10_000))
        }

    @Test
    fun incompatibleAndCorruptFilesAreRejected() =
        runBlocking<Unit> {
            for (version in listOf(6, 999)) {
                val fixture = fixture(1)
                HadithFixture.script(fixture.file, "PRAGMA user_version = $version;")
                val store = store(FakeAssets(fixture.file))
                store.download()
                assertEquals(LibraryStatus.Incompatible, store.status)
                assertFailsWith<HadithDatabaseException> { store.reader.catalog() }
                HadithFixture.script(fixture.file, "PRAGMA user_version = 7;")
                store.download()
                assertEquals(LibraryStatus.Ready, store.status)
                store.integrityCheck?.join()
            }
            val corrupt = File(temporaryDirectory(), "corrupt.db").apply { writeText("invalid") }
            val broken = store(FakeAssets(corrupt))
            broken.download()
            assertEquals(LibraryStatus.Failed, broken.status)
        }

    @Test
    fun validationReceiptSurvivesRelaunchAndRemovalInvalidatesIt() =
        runBlocking<Unit> {
            val fixture = fixture(1)
            val flags = MemoryPackFlags()
            val backend = FakeAssets(fixture.file).apply { installed = true }
            val first = store(backend, flags)
            first.refresh()
            first.integrityCheck?.join()
            val receipt = assertNotNull(flags.read().validated)
            val second = store(backend, flags)
            second.refresh()
            assertEquals(LibraryStatus.Ready, second.status)
            assertEquals(1, first.state.value.fullValidationCount)
            assertEquals(0, second.state.value.fullValidationCount)
            assertEquals(receipt, flags.read().validated)
            val revision = second.state.value.revision
            second.refresh()
            assertEquals(revision, second.state.value.revision)
            second.invalidateValidation()
            second.refresh()
            second.integrityCheck?.join()
            assertEquals(1, second.state.value.fullValidationCount)
            fixture.file.setLastModified(fixture.file.lastModified() + 250)
            second.refresh()
            second.integrityCheck?.join()
            assertEquals(2, second.state.value.fullValidationCount)
            second.remove()
            assertNull(flags.read().validated)
        }

    @Test
    fun oldSearchSessionRestartsPaginationAndKeepsScope() {
        val saved =
            HadithSession(
                request =
                    HadithRequest(
                        "mercy",
                        "bukhari",
                        3,
                        cursor = HadithCursor(HadithCursor.Phase.Substring, 99),
                    ),
                history = listOf(HadithCursor()),
                listOffset = 120.0,
                listRow = "hadith:old",
            )
        val json = Json.parseToJsonElement(saved.encode()).jsonObject
        val old = JsonObject(json - "searchRankingVersion").toString()
        val restored = HadithSession.decode(old)
        assertEquals("mercy", restored.request.query)
        assertEquals("bukhari", restored.request.collectionID)
        assertEquals(3, restored.request.chapterID)
        assertEquals(HadithCursor(), restored.request.cursor)
        assertTrue(restored.history.isEmpty())
        assertTrue(restored.cursorSources.isEmpty())
        assertEquals(0.0, restored.listOffset)
        assertNull(restored.listRow)
        assertEquals(2, restored.searchRankingVersion)
    }

    @Test
    fun readingSessionRoundTripsWithoutTheLibrary() {
        val session =
            HadithSession(
                active = true,
                request =
                    HadithRequest(
                        "mercy",
                        "bukhari",
                        3,
                        cursor = HadithCursor(HadithCursor.Phase.Substring, 99),
                    ),
                history = listOf(HadithCursor()),
                selection = HadithSource("bukhari", "1.json", 1, 1),
                detailOffset = 480.0,
                listOffset = 120.0,
            )
        assertEquals(session, HadithSession.decode(session.encode()))
        assertEquals(HadithSession(), HadithSession.decode("broken"))
    }

    @Test
    fun installedLibraryValidationTimings() =
        runBlocking<Unit> {
            val file = Fixtures.repository("build/hadith/dist/hadith.db")
            assumeTrue("build/hadith/dist/hadith.db isn't built", file.isFile)
            val flags = MemoryPackFlags()
            val backend = FakeAssets(file).apply { installed = true }
            val cold = store(backend, flags)
            val coldTime = measureTimeMillis { cold.refresh() }
            val catalogTime = measureTimeMillis { cold.reader.catalog() }
            val scanTime = measureTimeMillis { cold.integrityCheck?.join() }
            val relaunch = store(backend, flags)
            val relaunchTime = measureTimeMillis { relaunch.refresh() }
            val revision = relaunch.state.value.revision
            val foregroundTime = measureTimeMillis { relaunch.refresh() }
            assertEquals(LibraryStatus.Ready, cold.status)
            assertEquals(LibraryStatus.Ready, relaunch.status)
            assertEquals(1, cold.state.value.fullValidationCount)
            assertEquals(0, relaunch.state.value.fullValidationCount)
            assertEquals(revision, relaunch.state.value.revision)
            println(
                "Hadith asset checks: cold=${coldTime}ms, catalog=${catalogTime}ms, scan=${scanTime}ms, " +
                    "unchanged relaunch=${relaunchTime}ms, foreground=${foregroundTime}ms",
            )
        }

    @Test
    fun slowIntegrityCheckDoesNotBlockReadingAndFailureInvalidatesReader() =
        runBlocking<Unit> {
            val flags = MemoryPackFlags()
            val release = Channel<Unit>()
            val backend = FakeAssets(fixture(1).file).apply { installed = true }
            val store =
                store(backend, flags) {
                    release.receive()
                    throw IOException("Corrupt page")
                }
            store.refresh()
            assertEquals(LibraryStatus.Ready, store.status)
            assertEquals(2, store.reader.catalog().size)
            assertNull(flags.read().validated)
            release.send(Unit)
            store.integrityCheck?.join()
            assertEquals(LibraryStatus.Failed, store.status)
            assertNull(flags.read().validated)
            assertFailsWith<HadithDatabaseException> { store.reader.catalog() }
        }

    @Test
    fun removingLibraryCancelsPendingIntegrityReceipt() =
        runBlocking<Unit> {
            val flags = MemoryPackFlags()
            val backend = FakeAssets(fixture(1).file).apply { installed = true }
            val store = store(backend, flags) { awaitCancellation() }
            store.refresh()
            store.remove()
            store.integrityCheck?.join()
            assertEquals(LibraryStatus.Missing, store.status)
            assertNull(flags.read().validated)
        }

    @Test
    fun managedPackMigratesAndRestoresOneTitle() =
        runBlocking<Unit> {
            val fixture = fixture(3)
            val root = temporaryDirectory()
            val flags = MemoryPackFlags()
            val backend = FakeAssets(fixture.file).apply { installed = true }
            val library = HadithLocalLibrary(root, JdbcDriver)
            val store = store(backend, flags, library = library)

            fun installed() =
                store.state.value.books
                    .filter { it.installed }
                    .map { it.id }
            store.refresh()
            assertEquals(LibraryStatus.Ready, store.status)
            assertNull(backend.localDirectory())
            assertEquals(2, installed().size)
            store.remove("merged")
            assertFalse(store.state.value.storageError)
            assertEquals(listOf("other"), installed())
            assertEquals(
                1,
                store.reader
                    .page(HadithRequest(collectionID = "other"))
                    .rows.size,
            )
            assertEquals(0, backend.downloads)
            store.remove("other")
            assertTrue(installed().isEmpty())
            assertEquals(0, backend.downloads)
            store.download("merged")
            assertEquals(LibraryStatus.Ready, store.status)
            assertEquals(listOf("merged"), installed())
            assertEquals(1, backend.downloads)
            assertNull(backend.localDirectory())
            store.receive(AssetPack.Event.Progress(0f))
            assertEquals(LibraryStatus.Ready, store.status)
            store.remove()
            assertEquals(LibraryStatus.Missing, store.status)
            assertNull(library.localFile())

            backend.installed = true
            store.receive(AssetPack.Event.Began)
            assertEquals(LibraryStatus.Missing, store.status)
            store.receive(AssetPack.Event.Finished)
            store.refresh()
            assertEquals(LibraryStatus.Missing, store.status)
            assertNull(library.localFile())
            assertFailsWith<HadithDatabaseException> { store.reader.catalog() }

            val relaunched = store(backend, flags, library = library)
            relaunched.refresh()
            assertEquals(LibraryStatus.Missing, relaunched.status)
            assertFalse(relaunched.state.value.hasLocalAsset)
            assertFailsWith<HadithDatabaseException> { relaunched.reader.catalog() }
            assertEquals(1, backend.downloads)

            relaunched.download()
            assertEquals(LibraryStatus.Ready, relaunched.status)
            assertEquals(
                2,
                relaunched.state.value.books
                    .count { it.installed },
            )
            assertEquals(2, backend.downloads)
            relaunched.integrityCheck?.join()
        }
}

/** Swift `TestHadithAssets`: the pack folder is the fixture's. */
private class FakeAssets(
    val file: File,
) : AssetPack {
    var installed = false
    var downloads = 0
    var failing = false
    var downloading = false
    var suspended = false
    private var gate: CompletableDeferred<Unit>? = null
    private var started: CompletableDeferred<Unit>? = null

    override suspend fun localDirectory(): File? = if (installed) file.parentFile else null

    override suspend fun isDownloading() = downloading

    override suspend fun download() {
        downloads++
        started?.complete(Unit)
        started = null
        if (suspended) CompletableDeferred<Unit>().also { gate = it }.await()
        currentCoroutineContext().ensureActive()
        if (failing) throw IOException("Offline")
        installed = true
        downloading = false
    }

    override suspend fun remove() {
        if (failing) throw IOException("No permission")
        installed = false
    }

    override fun events() = emptyFlow<AssetPack.Event>()

    suspend fun waitForDownload() {
        if (downloads == 0) CompletableDeferred<Unit>().also { started = it }.await()
    }

    fun resume() {
        suspended = false
        gate?.complete(Unit)
        gate = null
    }
}

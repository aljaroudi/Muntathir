package com.aljaroudi.muntathir.ui.rakaat

import android.Manifest
import androidx.camera.core.SurfaceRequest
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.camera.CameraModule
import com.aljaroudi.muntathir.camera.SujoodCamera
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.qibla.QiblaSession
import com.aljaroudi.muntathir.core.rakaat.RakaatPreparation
import com.aljaroudi.muntathir.core.rakaat.RakaatUpdate
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.data.user.ProgressStore
import com.aljaroudi.muntathir.data.user.RoomUserRecords
import com.aljaroudi.muntathir.data.user.UserDataModule
import com.aljaroudi.muntathir.data.user.UserDatabase
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import com.aljaroudi.muntathir.location.QiblaModule
import com.aljaroudi.muntathir.location.QiblaReading
import com.aljaroudi.muntathir.location.QiblaSensors
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

/** Swift `RakaatTrackerUITests` with a scripted camera instead of `--rakaat-demo`/`--rakaat-dark`. */
@HiltAndroidTest
@UninstallModules(
    StorageModule::class,
    LocationModule::class,
    UserDataModule::class,
    CameraModule::class,
    QiblaModule::class,
)
class RakaatTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain =
        RuleChain.outerRule(hilt).around(GrantPermissionRule.grant(Manifest.permission.CAMERA)).around(compose)

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    private val database = UserDatabase.inMemory(InstrumentationRegistry.getInstrumentation().targetContext)

    @BindValue @JvmField
    val user: QuranUserStore = QuranUserStore(RoomUserRecords(database.dao()), { "test-device" })

    @BindValue @JvmField
    val progress: ProgressStore = ProgressStore(database.dao(), CoroutineScope(Dispatchers.IO))

    private val fakeCamera = FakeCamera()

    @BindValue @JvmField
    val camera: SujoodCamera = fakeCamera

    // Riyadh, facing north.
    @BindValue @JvmField
    val qibla: QiblaSensors =
        QiblaSensors {
            flowOf(
                QiblaReading(
                    QiblaSession.Status.Ready,
                    QiblaSession.Fix(24.7136, 46.6753, accuracy = 10.0, time = 0.0),
                    QiblaSession.Heading(0.0, accuracy = 5.0, time = 0.0),
                ),
            )
        }

    @Before
    fun setUp() {
        runBlocking { user.reopen() }
    }

    private fun waitFor(tag: String) =
        compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    private fun waitForText(text: String) =
        compose.waitUntil(15_000) { compose.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty() }

    private fun string(id: Int) = compose.activity.getString(id)

    private fun choose(
        target: Int,
        prayer: String,
    ) {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag("rakaat-tracker"))
        compose.onNodeWithTag("rakaat-tracker").performClick()
        waitFor("rakaat-target-$target")
        // The Qibla hint shows above the placement diagram.
        waitFor("rakaat-qibla-hint")
        compose.onNodeWithTag("rakaat-target-$target").performClick()
        waitFor("rakaat-prayer-$prayer")
        compose.onNodeWithTag("rakaat-prayer-$prayer").performClick()
        waitFor("rakaat-prayer-screen")
    }

    @Test
    fun countsFajrToCompletionAndRecordsIt() {
        choose(2, "fajr")
        compose.waitUntil(10_000) { fakeCamera.target == 2 }
        fakeCamera.send(RakaatUpdate())
        waitForText(string(R.string.keep_the_camera_uncovered_in_steady_light_while))
        fakeCamera.send(RakaatUpdate(count = 2, calibrated = true))
        waitFor("rakaat-count")
        compose.onNodeWithTag("rakaat-count").assertContentDescriptionEquals("1 rakaat")
        fakeCamera.send(RakaatUpdate(count = 4, calibrated = true, complete = true))
        waitFor("rakaat-complete")
        compose.onNodeWithTag("rakaat-count").assertContentDescriptionEquals("2 rakaat")
        compose.onNodeWithText(string(R.string.start_tasbih)).assertExists()
        compose.waitUntil(10_000) { runBlocking { progress.prayers() }.isNotEmpty() }
        val saved = runBlocking { progress.prayers() }.single()
        assertEquals(PrayerName.Fajr, saved.prayer)
        assertEquals(FakeLocator.MECCA, saved.location)
    }

    @Test
    fun darknessExplainsTheFailure() {
        choose(2, "other")
        compose.waitUntil(10_000) { fakeCamera.target == 2 }
        fakeCamera.send(RakaatUpdate(failure = RakaatPreparation.Failure.TooDark))
        waitForText(string(R.string.too_dark_to_count_reliably))
        compose.onNodeWithText(string(R.string.increase_the_light_and_keep_the_camera_uncovered)).assertExists()
        compose.onNodeWithText(string(R.string.try_again)).performClick()
        waitFor("rakaat-target-2")
        assertEquals(listOf<Any>(), runBlocking { progress.prayers() })
    }

    /** Emits what the test sends; the session ends the flow after a complete or failed update. */
    private class FakeCamera : SujoodCamera {
        private val channel = Channel<RakaatUpdate>(Channel.UNLIMITED)

        @Volatile
        var target: Int? = null

        override val preview: StateFlow<SurfaceRequest?> = MutableStateFlow(null)

        override fun updates(target: Int): Flow<RakaatUpdate> {
            this.target = target
            return channel.receiveAsFlow()
        }

        fun send(update: RakaatUpdate) {
            channel.trySend(update)
        }
    }
}

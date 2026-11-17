package com.aljaroudi.muntathir.ui.qibla

import android.Manifest
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.rule.GrantPermissionRule
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.qibla.QiblaSession
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import com.aljaroudi.muntathir.location.QiblaMapConfig
import com.aljaroudi.muntathir.location.QiblaMapModule
import com.aljaroudi.muntathir.location.QiblaModule
import com.aljaroudi.muntathir.location.QiblaReading
import com.aljaroudi.muntathir.location.QiblaSensors
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

/** Swift's `--qibla-ready` / `--qibla-heading` / `--qibla-aligned` UI fixtures, as fake [QiblaSensors]. */
@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class, QiblaModule::class, QiblaMapModule::class)
class QiblaTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    // Granted, so the screen doesn't open the system prompt; the fake decides the status.
    private val permissions =
        GrantPermissionRule.grant(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(permissions).around(hilt).around(compose)

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    private val reading = MutableStateFlow(QiblaReading(QiblaSession.Status.Settings))

    @BindValue @JvmField
    val sensors: QiblaSensors = QiblaSensors { reading }

    /** The compass dial, so the test doesn't depend on a Maps key or network tiles. */
    @BindValue @JvmField
    val mapConfig = QiblaMapConfig(enabled = false)

    private fun ready(heading: Double) {
        reading.value =
            QiblaReading(
                QiblaSession.Status.Ready,
                QiblaSession.Fix(24.7136, 46.6753, accuracy = 5.0, time = 0.0),
                QiblaSession.Heading(heading, accuracy = 5.0, time = 0.0),
            )
    }

    private fun waitFor(tag: String) =
        compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    private fun openQibla() {
        compose.onNodeWithTag("tab-tools").performClick()
        if (compose.onAllNodes(hasTestTag("qibla")).fetchSemanticsNodes().isEmpty()) {
            compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasTestTag("qibla"))
        }
        compose.onNodeWithTag("qibla").performClick()
    }

    @Test
    fun withoutPreciseAccessAsksForIt() {
        openQibla()
        waitFor("qibla-location-required")
        val text = compose.activity.getString(R.string.precise_location_required)
        compose.waitUntil(5_000) { compose.onAllNodes(hasText(text)).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("qibla-map-ready").assertDoesNotExist()
    }

    @Test
    fun showsTheTurnCueAwayFromQibla() {
        ready(heading = 90.0)
        openQibla()
        waitFor("qibla-map-ready")
        waitFor("qibla-heading-indicator")
        // Riyadh's Qibla is about 244°, so from 90° the shortest turn is clockwise.
        val turn = compose.activity.getString(R.string.turn_right)
        compose.waitUntil(5_000) { compose.onAllNodes(hasText(turn)).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("qibla-aligned").assertDoesNotExist()
    }

    @Test
    fun confirmsAlignmentWithTheKaaba() {
        ready(heading = 244.0)
        openQibla()
        waitFor("qibla-map-ready")
        waitFor("qibla-aligned")
    }
}

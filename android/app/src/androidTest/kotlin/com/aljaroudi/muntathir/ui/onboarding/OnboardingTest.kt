package com.aljaroudi.muntathir.ui.onboarding

import android.Manifest
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.rule.GrantPermissionRule
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class)
class OnboardingTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain =
        RuleChain
            .outerRule(hilt)
            .around(GrantPermissionRule.grant(Manifest.permission.ACCESS_COARSE_LOCATION))
            .around(compose)

    private val memory = MemoryStorage()

    @BindValue @JvmField
    val storage: AppStorage = memory

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    @Test
    fun setupNeedsALocationAndPersistsEachStep() {
        compose.onNodeWithTag("onboarding-continue").performClick() // Welcome
        compose.onNodeWithTag("onboarding-continue").performClick() // Language
        assertEquals(2, memory.device.onboardingStep)
        compose.onNodeWithTag("onboarding-continue").assertIsNotEnabled()
        compose.onNodeWithTag("use-device-location").performClick()
        compose.waitUntil { memory.device.liveLocation != null }
        compose.onNodeWithTag("location-name").assertTextEquals(compose.activity.getString(R.string.device_location))
        compose.onNodeWithTag("onboarding-continue").assertIsEnabled().performClick()
        compose.onNodeWithTag("onboarding-continue").performClick() // Method
        compose.onNodeWithTag("onboarding-finish").performClick() // Not now
        compose.waitUntil { memory.device.onboardingCompleted }
        compose.onNodeWithTag("tab-today").assertExists()
        assertEquals(FakeLocator.MECCA, memory.device.liveLocation)
    }
}

package com.aljaroudi.muntathir.baselineprofile

import androidx.benchmark.macro.junit4.BaselineProfileRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The journeys whose code goes into the Baseline Profile: cold start through onboarding to Today, then the
 * Calendar, the Tools grid, and opening and scrolling a surah. Generate with
 * `./gradlew :app:generateReleaseBaselineProfile` on an emulator with a location (any fix will do).
 */
@RunWith(AndroidJUnit4::class)
class BaselineProfileGenerator {
    @get:Rule
    val rule = BaselineProfileRule()

    @Test
    fun generate() =
        rule.collect(packageName = PACKAGE) {
            // Each iteration starts from a fresh install state, so onboarding runs every time.
            device.executeShellCommand("pm clear $PACKAGE")
            device.executeShellCommand("pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION")
            device.executeShellCommand("pm grant $PACKAGE android.permission.POST_NOTIFICATIONS")
            pressHome()
            startActivityAndWait()
            device.completeOnboarding()

            device.tap("tab-calendar")
            device.waitFor("calendar-year")
            device.tap("tab-tools")
            device.tap("holy-quran")
            device.tap("quran-surah-2")
            device
                .waitFor("quran-verses")
                .fling(Direction.DOWN)
            device.waitForIdle()
        }

    private fun UiDevice.completeOnboarding() {
        tap("onboarding-continue") // Welcome
        tap("onboarding-continue") // Language
        tap("use-device-location")
        // Continue is enabled once the fix arrives.
        wait(Until.hasObject(By.res("onboarding-continue").enabled(true)), FIX_TIMEOUT)
        tap("onboarding-continue") // Location
        tap("onboarding-continue") // Method
        tap("onboarding-finish") // Notifications: not now
        waitFor("tab-today")
    }

    private fun UiDevice.waitFor(tag: String) =
        checkNotNull(wait(Until.findObject(By.res(tag)), TIMEOUT)) { "No $tag on screen" }

    private fun UiDevice.tap(tag: String) {
        waitFor(tag).click()
        waitForIdle()
    }

    private companion object {
        const val PACKAGE = "com.aljaroudi.muntathir"
        const val TIMEOUT = 10_000L
        const val FIX_TIMEOUT = 30_000L
    }
}

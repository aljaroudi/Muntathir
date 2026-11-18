package com.aljaroudi.muntathir.ui

import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.printToLog
import androidx.core.os.LocaleListCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.app.Preferences
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.qibla.QiblaSession
import com.aljaroudi.muntathir.core.quran.DailyAyah
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import com.aljaroudi.muntathir.location.QiblaModule
import com.aljaroudi.muntathir.location.QiblaReading
import com.aljaroudi.muntathir.location.QiblaSensors
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import java.io.FileInputStream

@HiltAndroidTest
@UninstallModules(
    StorageModule::class,
    LocationModule::class,
    com.aljaroudi.muntathir.data.ClockModule::class,
    QiblaModule::class,
)
class MarketingScreenshotTest {
    @BindValue @JvmField
    val sensors =
        QiblaSensors {
            kotlinx.coroutines.flow.flowOf(
                QiblaReading(
                    QiblaSession.Status.Ready,
                    QiblaSession.Fix(24.7136, 46.6753, accuracy = 5.0, time = 0.0),
                    QiblaSession.Heading(244.0, accuracy = 5.0, time = 0.0),
                ),
            )
        }

    @BindValue @JvmField
    val quran: QuranDatabase =
        object : QuranDatabase(InstrumentationRegistry.getInstrumentation().targetContext) {
            override suspend fun dailyAyah(translation: String?): DailyAyah {
                val ayah = read { requireNotNull(verse(94, 6, translation)) }
                return DailyAyah(List(DailyAyah.COUNT) { ayah })
            }
        }

    @javax.inject.Inject lateinit var translations: com.aljaroudi.muntathir.data.QuranTranslations

    private val hilt = HiltAndroidRule(this)
    private val compose = createEmptyComposeRule()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(
            preferences =
                Preferences(
                    hiddenPrayers =
                        setOf(
                            PrayerName.Imsak,
                            PrayerName.Sunrise,
                            PrayerName.Asr,
                            PrayerName.Isha,
                            PrayerName.Midnight,
                        ),
                ),
            device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA),
        )

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    @BindValue @JvmField
    val clock: java.time.Clock =
        java.time.Clock.fixed(java.time.Instant.parse("2026-10-23T06:00:00Z"), java.time.ZoneId.of("Asia/Riyadh"))

    @Test
    fun storeGallery() {
        val locale = InstrumentationRegistry.getArguments().getString("galleryLocale")
        org.junit.Assume.assumeNotNull(locale)
        hilt.inject()
        val folder = "/data/local/tmp/muntathir-marketing"

        fun capture(
            scene: String,
            tag: String,
        ) {
            waitFor(tag)
            compose.waitForIdle()
            shell("screencap -p $folder/$scene.png")
        }
        shell("cmd uimode night no")
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                setLanguage(locale)
                compose.waitUntil(10_000) {
                    var applied = false
                    scenario.onActivity {
                        applied =
                            it.resources.configuration.locales[0]
                                .language ==
                            java.util.Locale
                                .forLanguageTag(locale!!)
                                .language
                    }
                    applied
                }
                val translation =
                    when (locale) {
                        "ar-SA" -> ""
                        "de-DE" -> "de.bubenheim"
                        "ru" -> "ru.kuliev"
                        "es-ES" -> "es.bornez"
                        "zh-Hans" -> "zh.jian"
                        "zh-Hant" -> "zh.majian"
                        "fa" -> "fa.fooladvand"
                        else -> "en.qarai"
                    }
                scenario.onActivity { translations.select(translation) }
                compose.waitUntil(10_000) {
                    translations.state.value.activeID
                        .orEmpty() == translation
                }
                capture("01-Today", "daily-ayah-text")
                compose.onNodeWithTag("tab-calendar").performClick()
                waitFor("calendar-year")
                compose.onNodeWithTag("calendar-year").performClick()
                compose.onNodeWithTag("calendar-jump-month-8").performClick()
                waitFor("calendar-month-1448-8")
                compose.onNodeWithTag("calendar-month-1448-8").performClick()
                compose.onNodeWithTag("calendar-day-1448-8-1").performClick()
                capture("09-Calendar", "calendar-year")
            }

            fun tool(
                tag: String,
                visit: () -> Unit,
            ) {
                ActivityScenario.launch(MainActivity::class.java).use {
                    compose.onNodeWithTag("tab-tools").performClick()
                    openTool(tag)
                    visit()
                }
            }
            tool("holy-quran") {
                waitFor("quran-surah-1")
                compose.onNodeWithTag("quran-list").performScrollToNode(hasTestTag("quran-surah-94"))
                compose.onNodeWithTag("quran-surah-94").performClick()
                compose.onNodeWithTag("quran-verses").performScrollToNode(hasTestTag("quran-verse-94:6"))
                capture("02-Quran", "quran-verse-94:6")
            }
            tool("hadith") {
                waitFor("hadith-saved")
                compose.onNodeWithTag("hadith-list").performScrollToNode(hasTestTag("hadith-book-bukhari"))
                compose.onNodeWithTag("hadith-book-bukhari").performClick()
                waitFor("hadith-chapter-1")
                compose.onNodeWithTag("hadith-chapter-1").performClick()
                capture("03-Hadith", "hadith-result-1")
            }
            tool("supplications") { capture("05-Supplications", "supplication-1") }
            tool("tasbih") { capture("06-Tasbih", "tasbih-beads") }
            tool("rakaat-tracker") { capture("07-Rakaat", "rakaat-target-2") }
            tool("qibla") {
                if (com.aljaroudi.muntathir.BuildConfig.MAPS_API_KEY_SET) {
                    waitFor("qibla-map-loaded")
                    compose.waitUntil(60_000) { mapTilesVisible() }
                }
                capture("10-Qibla", "qibla-map-ready")
            }
        } finally {
            setLanguage(null)
        }
    }

    private fun setLanguage(tag: String?) =
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            AppCompatDelegate.setApplicationLocales(
                tag?.let(LocaleListCompat::forLanguageTags) ?: LocaleListCompat.getEmptyLocaleList(),
            )
        }

    private fun openTool(tag: String) {
        waitFor("holy-quran")
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
    }

    private fun waitFor(tag: String) {
        try {
            compose.waitUntil(60_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }
        } catch (timeout: androidx.compose.ui.test.ComposeTimeoutException) {
            compose.onAllNodes(isRoot()).printToLog("MarketingScreenshotTest")
            throw timeout
        }
    }

    // Sample the map interior away from the compass, system bars and attribution.
    private fun mapTilesVisible(): Boolean {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val image = automation.takeScreenshot() ?: return false
        try {
            val colors = mutableSetOf<Int>()
            for (x in 1..8) {
                for (y in 3..16) {
                    colors += image.getPixel(image.width * x / 25, image.height * y / 20)
                }
            }
            return colors.size > 24
        } finally {
            image.recycle()
        }
    }

    private fun shell(command: String) {
        // Reading the output waits for the command to finish.
        InstrumentationRegistry
            .getInstrumentation()
            .uiAutomation
            .executeShellCommand(command)
            .use { FileInputStream(it.fileDescriptor).readBytes() }
    }
}

package com.aljaroudi.muntathir.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.Chronometer
import android.widget.FrameLayout
import android.widget.TextView
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.compose
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.data.ClockModule
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.title
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

/** The widgets as the lock screen hosts them (Swift's accessory families), and unchanged on the home screen. */
@HiltAndroidTest
@UninstallModules(StorageModule::class, ClockModule::class)
class LockScreenWidgetTest {
    @get:Rule
    val hilt = HiltAndroidRule(this)

    private val memory =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val storage: AppStorage = memory

    // 09:00 in Mecca, between sunrise and Dhuhr.
    private var now = Instant.parse("2026-11-22T06:00:00Z")

    @BindValue @JvmField
    val clock: Clock =
        object : Clock() {
            override fun getZone(): ZoneId = ZoneId.of("Asia/Riyadh")

            override fun withZone(zone: ZoneId): Clock = fixed(now, zone)

            override fun instant(): Instant = now
        }

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val locale get() = context.widgetLocale
    private val app get() =
        context
            .widgetDeps()
            .model()
            .state.value

    /** Every text view of [widget] as [category]'s host would inflate it. */
    private fun render(
        widget: GlanceAppWidget,
        category: Int,
        size: DpSize = DpSize(360.dp, 240.dp),
    ): List<TextView> {
        val options = Bundle().apply { putInt(AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY, category) }
        val views = runBlocking { widget.compose(context, options = options, size = size) }
        var texts = emptyList<TextView>()
        instrumentation.runOnMainSync { texts = textViews(views.apply(context, FrameLayout(context))) }
        return texts
    }

    private fun textViews(view: View): List<TextView> =
        when (view) {
            is TextView -> listOf(view)
            is ViewGroup -> (0 until view.childCount).flatMap { textViews(view.getChildAt(it)) }
            else -> emptyList()
        }.filter { it.visibility == View.VISIBLE }

    private fun List<TextView>.texts() = map { it.text.toString() }

    @Test
    fun prayerShowsOnlyTheNextNameAndTimeOnTheLockScreen() {
        val next = checkNotNull(app.prayerSettings.nextPrayer(clock.instant()))
        val expected =
            listOf(context.getString(next.name.title), Formats.clockTime(next.time, app.location!!.zone, locale))
        assertEquals(expected, render(PrayerWidget(), KEYGUARD).texts())

        val home = render(PrayerWidget(), HOME)
        assertEquals(expected, home.texts().take(2))
        assertTrue(home.any { it is Chronometer })
    }

    @Test
    fun prayerAsksForALocationOnTheLockScreen() {
        memory.device = DeviceState(onboardingCompleted = true)
        assertEquals(listOf(context.getString(R.string.set_location_in_app)), render(PrayerWidget(), KEYGUARD).texts())
    }

    @Test
    fun hijriShowsOnlyTheDayAndMonthOnTheLockScreen() {
        val day = app.engine.resolve(clock.instant())
        val expected = listOf(Formats.number(day.day, locale), Formats.hijriMonth(day.month.month, locale))
        assertEquals(expected, render(HijriWidget(), KEYGUARD).texts())
        assertEquals(4, render(HijriWidget(), HOME).size)
    }

    @Test
    fun ayahShowsOnlyTheVerseOnTheLockScreen() {
        val home = render(AyahWidget(), HOME).texts()
        assertEquals(2, home.size) // verse and translation
        assertNotEquals(home[0], home[1])

        val lock = render(AyahWidget(), KEYGUARD)
        assertEquals(home.take(1), lock.texts())
        assertEquals(4, lock.single().maxLines)
        assertEquals(2, render(AyahWidget(), KEYGUARD, DpSize(360.dp, 110.dp)).single().maxLines)
    }

    @Test
    fun lockScreenTextFitsTheCardAtLargeFontSizes() {
        val options = Bundle().apply { putInt(AppWidgetManager.OPTION_APPWIDGET_HOST_CATEGORY, KEYGUARD) }
        // The day of the longest verse in the schedule, so it wraps to every line it may use.
        val schedule = runBlocking { context.widgetDeps().quran().dailyAyah(null) }
        now =
            (0L..370L)
                .map { now + Duration.ofDays(it) }
                .maxBy { schedule.verse(it, app.engine)?.text?.length ?: 0 }
        for (language in listOf("en", "ar")) {
            for (scale in listOf(1f, 1.3f, 2f)) {
                val configuration =
                    Configuration(context.resources.configuration).apply {
                        fontScale = scale
                        setLocale(Locale.forLanguageTag(language))
                    }
                val configured = context.createConfigurationContext(configuration)
                for (widget in listOf(PrayerWidget(), HijriWidget(), AyahWidget())) {
                    for (height in listOf(110, 150, 240)) {
                        val size = DpSize(300.dp, height.dp)
                        val views = runBlocking { widget.compose(configured, options = options, size = size) }
                        val case = "${widget.javaClass.simpleName} $language ${scale}x ${height}dp"
                        instrumentation.runOnMainSync {
                            assertFits(case, views.apply(configured, FrameLayout(configured)), size)
                        }
                    }
                }
            }
        }
    }

    /** Lays [root] out at [size]; each text must keep its full height, inside the card's padding. */
    private fun assertFits(
        case: String,
        root: View,
        size: DpSize,
    ) {
        val density = root.resources.displayMetrics.density
        val width = (size.width.value * density).toInt()
        val height = (size.height.value * density).toInt()
        root.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
        )
        root.layout(0, 0, width, height)
        for (text in textViews(root)) {
            val shown = minOf(text.lineCount, text.maxLines)
            val needed = text.layout.getLineTop(shown)
            assertTrue("$case clips \"${text.text}\": ${text.height} < $needed", text.height >= needed)
            val bounds = Rect(0, 0, text.width, text.height)
            (root as ViewGroup).offsetDescendantRectToMyCoords(text, bounds)
            assertTrue("$case overflows: $bounds", bounds.top >= 0 && bounds.bottom <= height)
        }
    }

    @Test
    fun allThreeWidgetsAreOfferedToTheLockScreen() {
        val providers = AppWidgetManager.getInstance(context).getInstalledProvidersForPackage(context.packageName, null)
        assertEquals(3, providers.size)
        for (provider in providers) {
            assertEquals(provider.provider.className, HOME or KEYGUARD, provider.widgetCategory)
            assertNotEquals(0, provider.initialKeyguardLayout)
        }
    }

    private companion object {
        const val HOME = AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN
        const val KEYGUARD = AppWidgetProviderInfo.WIDGET_CATEGORY_KEYGUARD
    }
}

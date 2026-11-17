package com.aljaroudi.muntathir.ui.today

import androidx.compose.runtime.Composable
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.app.Preferences
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.quran.DailyAyah
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.ui.ScreenPreviews
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import com.android.tools.screenshot.PreviewTest
import java.time.Instant
import java.time.ZoneId

private val mecca = SavedLocation(21.4225, 39.8262, "Asia/Riyadh")
private val library = EventLibrary.bundled()
private val ayah =
    Ayah(
        26,
        114,
        "وَمَآ أَنَا۠ بِطَارِدِ ٱلْمُؤْمِنِينَ",
        mapOf(QuranDatabase.ENGLISH to "And I will not drive away the faithful."),
    )
private val names = mapOf(26 to "الشعراء")

/** Auto resolves to no translation in Arabic and to the bundled English otherwise. */
@Composable
private fun state(
    instant: String,
    location: SavedLocation? = mecca,
): TodayUi {
    val verse = if (currentLocale().language == "ar") ayah.copy(translations = emptyMap()) else ayah
    return TodayUi.make(
        AppState(Preferences(), DeviceState(liveLocation = location), emptyList(), 0, ZoneId.of("Asia/Riyadh")),
        Instant.parse(instant),
        library,
        DailyAyah(List(DailyAyah.COUNT) { verse }),
        names,
    )
}

@PreviewTest
@ScreenPreviews
@Composable
fun TodayNoonScreenshot() {
    MuntathirTheme(dynamicColor = false) { TodayContent(state("2026-10-21T09:05:00Z"), TodayActions()) }
}

@PreviewTest
@ScreenPreviews
@Composable
fun TodayTwilightScreenshot() {
    MuntathirTheme(dynamicColor = false) { TodayContent(state("2026-10-21T15:25:00Z"), TodayActions()) }
}

@PreviewTest
@ScreenPreviews
@Composable
fun TodayWithoutLocationScreenshot() {
    MuntathirTheme(dynamicColor = false) { TodayContent(state("2026-10-21T09:05:00Z", null), TodayActions()) }
}

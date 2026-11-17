package com.aljaroudi.muntathir.ui.calendar

import androidx.compose.runtime.Composable
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.ui.ScreenPreviews
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import com.android.tools.screenshot.PreviewTest
import java.time.LocalDate
import java.time.ZoneId

private val engine = CalendarEngine(ZoneId.of("Asia/Riyadh"))
private val now = engine.startOfDay(LocalDate.of(2026, 11, 17)).plusSeconds(10 * 3600)
private val library = EventLibrary.bundled()

@PreviewTest
@ScreenPreviews
@Composable
fun CalendarScreenshot() {
    MuntathirTheme(dynamicColor = false) {
        CalendarContent(CalendarUi(now, engine, emptyList(), library), onBack = null)
    }
}

@PreviewTest
@ScreenPreviews
@Composable
fun EventsScreenshot() {
    MuntathirTheme(dynamicColor = false) { EventsScreen(library, onBack = {}) }
}

@PreviewTest
@ScreenPreviews
@Composable
fun MonthAdjustmentsScreenshot() {
    val month = HijriMonth(1448, 6)
    MuntathirTheme(dynamicColor = false) {
        MonthAdjustmentsContent(
            MonthAdjustmentUi(month, 1, engine.start(month).minusDays(1)),
            onMonth = {},
            onOffset = {},
            onSave = {},
            onBack = {},
        )
    }
}

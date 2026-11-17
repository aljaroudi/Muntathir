package com.aljaroudi.muntathir.ui.calendar

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.CalendarTargets
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import org.junit.Rule
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class CalendarTest {
    @get:Rule val compose = createComposeRule()

    private val engine = CalendarEngine(ZoneId.of("Asia/Riyadh"))
    private val now = engine.startOfDay(LocalDate.of(2026, 11, 17)).plusSeconds(36_000)
    private val library = EventLibrary.bundled()

    @Test
    fun opensOnNextEventAndJumpsToPickedDay() {
        compose.setContent {
            MuntathirTheme {
                CalendarContent(
                    CalendarUi(now, engine, emptyList(), library),
                    onBack = null,
                )
            }
        }
        val next = engine.resolve(library.nextEventDate(engine.localDate(now), engine)!!)
        compose.onNodeWithTag(CalendarTargets.dayID(next.month, next.day)).assertIsDisplayed()
        compose.onNodeWithTag("calendar-countdown").assertIsDisplayed()

        // Jump to the first day of Ramadan: the list scrolls to its first event day on or after it.
        compose.onNodeWithTag("calendar-jump").performClick()
        val ramadan = next.month.copy(month = 9)
        repeat(ramadan.index - next.month.index) {
            compose.onNodeWithTag("calendar-month-title").assertIsDisplayed()
            compose
                .onNode(
                    androidx.compose.ui.test
                        .hasContentDescriptionExactly("Next month"),
                ).performClick()
        }
        compose.onNodeWithTag("calendar-day-${ramadan.year}-9-1").performScrollTo().performClick()
        val days = library.events.filter { it.month == 9 }.map { it.day }
        val target = CalendarTargets.jumpTarget(engine.resolve(engine.start(ramadan)), days, engine)
        compose.waitUntil(5_000) {
            compose
                .onAllNodes(
                    androidx.compose.ui.test
                        .hasTestTag(target),
                ).fetchSemanticsNodes()
                .isNotEmpty()
        }
        compose.onNodeWithTag(target).assertIsDisplayed()
    }
}

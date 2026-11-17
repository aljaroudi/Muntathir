package com.aljaroudi.muntathir.ui.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.CenterFocusWeak
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Toll
import androidx.compose.material.icons.outlined.VolunteerActivism
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.ui.graphics.vector.ImageVector
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppTool

@get:StringRes
val AppTool.title: Int
    get() =
        when (this) {
            AppTool.Calendar -> R.string.calendar
            AppTool.Events -> R.string.events
            AppTool.Quran -> R.string.holy_quran
            AppTool.Hadith -> R.string.hadith
            AppTool.Supplications -> R.string.supplications
            AppTool.Rulings -> R.string.rulings
            AppTool.Figures -> R.string.figures
            AppTool.Tasbih -> R.string.tasbih
            AppTool.Rakaat -> R.string.rakaat_tracker
            AppTool.PrayerProgress -> R.string.activity
            AppTool.Qibla -> R.string.qibla
        }

/** Material counterparts of the iOS SF Symbols. */
val AppTool.icon: ImageVector
    get() =
        when (this) {
            AppTool.Calendar -> Icons.Outlined.CalendarMonth
            AppTool.Events -> Icons.AutoMirrored.Outlined.ListAlt
            AppTool.Quran -> Icons.AutoMirrored.Outlined.MenuBook
            AppTool.Hadith -> Icons.Outlined.Book
            AppTool.Supplications -> Icons.Outlined.VolunteerActivism
            AppTool.Rulings -> Icons.AutoMirrored.Outlined.Article
            AppTool.Figures -> Icons.Outlined.People
            AppTool.Tasbih -> Icons.Outlined.Toll
            AppTool.Rakaat -> Icons.Outlined.CenterFocusWeak
            AppTool.PrayerProgress -> Icons.Outlined.BarChart
            AppTool.Qibla -> Icons.Outlined.Explore
        }

@get:StringRes
val Route.tabTitle: Int
    get() =
        when (this) {
            TodayRoute -> R.string.today
            ToolsRoute -> R.string.tools
            is ToolRoute -> tool.title
            else -> R.string.app_name
        }

val Route.tabIcon: ImageVector
    get() =
        when (this) {
            TodayRoute -> Icons.Outlined.WbSunny
            ToolsRoute -> Icons.Outlined.GridView
            is ToolRoute -> tool.icon
            else -> Icons.Outlined.Settings
        }

val Route.testTag: String
    get() =
        when (this) {
            TodayRoute -> "today"
            ToolsRoute -> "tools"
            is ToolRoute -> tool.testTag
            else -> toString()
        }

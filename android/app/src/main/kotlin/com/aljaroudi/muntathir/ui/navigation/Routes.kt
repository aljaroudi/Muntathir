package com.aljaroudi.muntathir.ui.navigation

import androidx.navigation3.runtime.NavKey
import com.aljaroudi.muntathir.core.app.AppTool
import kotlinx.serialization.Serializable

/** Every destination. Tab roots are [TodayRoute], [ToolsRoute] and [ToolRoute]. */
@Serializable
sealed interface Route : NavKey

@Serializable
data object TodayRoute : Route

@Serializable
data object ToolsRoute : Route

@Serializable
data class ToolRoute(
    val tool: AppTool,
) : Route

@Serializable
data object SettingsRoute : Route

@Serializable
data object TabsSettingsRoute : Route

@Serializable
data object MonthAdjustmentsRoute : Route

@Serializable
data object DownloadsRoute : Route

@Serializable
data object CreditsRoute : Route

/**
 * A surah in the reader, opened at [verse]. [query] underlines a search match; [highlight] scrolls to and focuses
 * a saved highlight.
 */
@Serializable
data class QuranReaderRoute(
    val surah: Int,
    val verse: Int = 1,
    val query: String? = null,
    val highlight: String? = null,
) : Route

/** Opened from Today's empty state and Settings; a dialog over the current tab. */
@Serializable
data object LocationRoute : Route

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

/** Saved Quran highlights and bookmarks. */
@Serializable
data object QuranSavedRoute : Route

/** A hadith or supplications screen; in two panes, lists replace the detail beside them. */
sealed interface HadithRoute : Route

/**
 * Swift `HadithView` with an initial request: a book's contents ([collectionID]), a chapter's narrations
 * ([chapterID]), or a search across every book ([query] alone). The library itself is `ToolRoute(Hadith)`.
 */
@Serializable
data class HadithBrowseRoute(
    val collectionID: String? = null,
    val chapterID: Int? = null,
    val query: String = "",
) : HadithRoute

/** One narration or supplication. [highlight] focuses a saved highlight; [query] underlines a search match. */
@Serializable
data class HadithDetailRoute(
    val id: Int,
    val query: String = "",
    val highlight: String? = null,
    val supplication: Boolean = false,
) : HadithRoute

@Serializable
data class HadithIntroductionRoute(
    val id: Int,
) : HadithRoute

/** Saved hadith, or saved supplications. */
@Serializable
data class HadithSavedRoute(
    val supplications: Boolean = false,
) : HadithRoute

/** A ruling, or the rulings of one of its sections; in two panes these sit beside the Rulings list. */
sealed interface RulingsRoute : Route

@Serializable
data class RulingDetailRoute(
    val authority: String,
    val language: String,
    val siteID: String,
) : RulingsRoute

@Serializable
data class RulingSectionRoute(
    val authority: String,
    val language: String,
    val section: Long,
    val title: String,
) : RulingsRoute

@Serializable
data object RulingsSavedRoute : RulingsRoute

/** Settings → Highlight colors. */
@Serializable
data object HighlightPaletteRoute : Route

/** Opened from Today's empty state and Settings; a dialog over the current tab. */
@Serializable
data object LocationRoute : Route

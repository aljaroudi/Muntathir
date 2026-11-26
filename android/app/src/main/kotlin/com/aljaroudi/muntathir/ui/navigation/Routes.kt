package com.aljaroudi.muntathir.ui.navigation

import androidx.navigation3.runtime.NavKey
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.core.prayer.PrayerName
import kotlinx.serialization.Serializable

/** Every destination. Tab roots are [TodayRoute], [ToolsRoute] and [ToolRoute]. */
@Serializable
sealed interface Route : NavKey

/** Shown beside a list in two panes, where opening another detail replaces it rather than stacking. */
sealed interface DetailRoute : Route

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
data object TabsSettingsRoute : DetailRoute

@Serializable
data object MonthAdjustmentsRoute : DetailRoute

@Serializable
data object DownloadsRoute : DetailRoute

@Serializable
data object CreditsRoute : DetailRoute

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
) : DetailRoute

/** Saved Quran highlights and bookmarks. */
@Serializable
data object QuranSavedRoute : DetailRoute

/** A hadith or supplications screen, as kept in the hadith session. */
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
) : HadithRoute,
    DetailRoute

@Serializable
data class HadithIntroductionRoute(
    val id: Int,
) : HadithRoute,
    DetailRoute

/** Saved hadith, or saved supplications. */
@Serializable
data class HadithSavedRoute(
    val supplications: Boolean = false,
) : HadithRoute,
    DetailRoute

@Serializable
data class SermonRoute(
    val id: String,
) : DetailRoute

@Serializable
data class RulingDetailRoute(
    val authority: String,
    val language: String,
    val siteID: String,
) : DetailRoute

/** The rulings of one section, opened from a ruling. */
@Serializable
data class RulingSectionRoute(
    val authority: String,
    val language: String,
    val section: Long,
    val title: String,
) : DetailRoute

@Serializable
data object RulingsSavedRoute : DetailRoute

/** Settings → Highlight colors. */
@Serializable
data object HighlightPaletteRoute : DetailRoute

/** Opened from Today's empty state and Settings; a dialog over the current tab. */
@Serializable
data object LocationRoute : DetailRoute

/** A Rakaat tracker session counting [target] rakaat; [prayer] is recorded in Activity when chosen. */
@Serializable
data class RakaatSessionRoute(
    val target: Int,
    val prayer: PrayerName? = null,
) : Route

@Serializable
data class FigureProfileRoute(
    val id: String,
) : DetailRoute

/** The figures of an observance linked to more than one. */
@Serializable
data class FigurePickerRoute(
    val ids: List<String>,
) : DetailRoute

package com.aljaroudi.muntathir.core.feed

import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.CalendarException
import com.aljaroudi.muntathir.core.calendar.CalendarException.Kind
import com.aljaroudi.muntathir.core.calendar.CivilDate
import com.aljaroudi.muntathir.core.calendar.DateProvenance
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.MonthCorrection
import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.core.location.SavedLocation
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.ZoneOffset

@Serializable
enum class SightingMethod {
    @SerialName("nakedEye")
    NakedEye,

    @SerialName("aidedSight")
    AidedSight,

    @SerialName("government")
    Government,

    @SerialName("calculation")
    Calculation,
}

/** The calendar a user follows. Titles are app resources. */
enum class CalendarMethod { System, NakedEye, Government }

object CalendarSource {
    val countries = listOf("SA")
    const val MIDDLE_EAST = "naked-eye-middle-east"

    fun method(sourceID: String?): CalendarMethod =
        when {
            sourceID == MIDDLE_EAST -> CalendarMethod.NakedEye
            sourceID != null && countries.any { sourceID == "government-$it" } -> CalendarMethod.Government
            else -> CalendarMethod.System
        }

    fun sightingMethod(sourceID: String?): SightingMethod? =
        when (method(sourceID)) {
            CalendarMethod.System -> null
            CalendarMethod.NakedEye -> SightingMethod.NakedEye
            CalendarMethod.Government -> SightingMethod.Government
        }
}

@Serializable
data class GeoPoint(
    val latitude: Double,
    val longitude: Double,
)

/** Where an announcement was observed. Informational: following a source is worldwide, so it's only validated. */
@Serializable
data class Coverage(
    val countries: List<String>,
    val polygons: List<List<GeoPoint>>,
) {
    val isValid: Boolean
        get() =
            (countries.isNotEmpty() || polygons.isNotEmpty()) &&
                countries.all { it.length == 2 && it == it.uppercase() } &&
                polygons.all { polygon ->
                    polygon.size >= 3 &&
                        polygon.all {
                            it.latitude.isFinite() && it.longitude.isFinite() && it.latitude in -90.0..90.0 &&
                                it.longitude in -180.0..180.0
                        }
                }
}

@Serializable
data class Announcement(
    val id: String,
    val revision: Int,
    val method: SightingMethod,
    val sourceID: String,
    val coverage: Coverage,
    val month: HijriMonth,
    val start: CivilDate,
) {
    val correction: MonthCorrection get() = MonthCorrection(month, start, DateProvenance.Confirmed, sourceID)
}

@Serializable
data class CorrectionsFeed(
    val schemaVersion: Int,
    val announcements: List<Announcement>,
) {
    /**
     * Announcements for the followed [sourceID] (worldwide; coverage is informational). Throws
     * [CalendarException] when rows conflict or can't form a calendar in the location's zone.
     */
    fun matching(
        location: SavedLocation,
        sourceID: String?,
    ): List<Announcement> {
        val method = CalendarSource.sightingMethod(sourceID) ?: return emptyList()
        val months = linkedMapOf<HijriMonth, Announcement>()
        for (row in announcements.filter { it.sourceID == sourceID && it.method == method }) {
            val previous = months[row.month]
            if (previous != null && previous.start != row.start) throw CalendarException(Kind.ConflictingMonths)
            months[row.month] = row
        }
        val result = months.values.toList()
        CalendarEngine(location.zone, confirmed = result.map { it.correction })
        return result
    }

    /**
     * The confirmations to apply for [location] with the user's [offsets]; throws when they can't coexist,
     * so the caller keeps its previous calendar. The pure part of Swift `AppModel.receive`.
     */
    fun confirmations(
        location: SavedLocation,
        offsets: List<MonthOffset>,
    ): List<Announcement> {
        val rows = matching(location, CalendarSource.MIDDLE_EAST)
        CalendarEngine.withOffsets(location.zone, offsets, rows.map { it.correction })
        return rows
    }

    companion object {
        const val MAX_ANNOUNCEMENTS = 10_000

        private val json = Json { ignoreUnknownKeys = true }

        /** Strictly decodes and validates a feed; any invalid row rejects the whole feed. */
        fun decode(text: String): CorrectionsFeed {
            val feed = json.decodeFromString<CorrectionsFeed>(text)
            if (feed.schemaVersion != 1 || feed.announcements.size > MAX_ANNOUNCEMENTS) {
                throw CalendarException(Kind.InvalidDate)
            }
            val ids = mutableSetOf<String>()
            for (row in feed.announcements) {
                val valid =
                    row.id.isNotEmpty() && row.sourceID.isNotEmpty() && row.revision > 0 &&
                        row.method != SightingMethod.Calculation && row.coverage.isValid && row.month.isValid &&
                        row.start.toLocalDate() != null && ids.add(row.id)
                if (!valid) throw CalendarException(Kind.InvalidDate)
                CalendarEngine(ZoneOffset.UTC, confirmed = listOf(row.correction))
            }
            return feed
        }

        fun encode(feed: CorrectionsFeed): String = json.encodeToString(feed)
    }
}

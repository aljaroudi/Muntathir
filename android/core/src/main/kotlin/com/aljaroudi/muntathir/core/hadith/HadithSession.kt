package com.aljaroudi.muntathir.core.hadith

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject

/**
 * Where the reader was in the hadith library, kept device-local so it reopens there. Port of Swift
 * `HadithSessionState` (`hadith.session.v1`); optional fields keep older sessions decodable.
 */
@Serializable
data class HadithSession(
    val searchRankingVersion: Int? = RANKING_VERSION,
    val active: Boolean = false,
    val request: HadithRequest = HadithRequest(),
    val history: List<HadithCursor> = emptyList(),
    val selection: HadithSource? = null,
    val listOffset: Double = 0.0,
    val detailOffset: Double = 0.0,
    val chapter: HadithSource? = null,
    val cursorSources: List<HadithSource?> = emptyList(),
    val screen: String? = null,
    val contentsQuery: String? = null,
    val contentsOffset: Double? = null,
    val listRow: String? = null,
    val contentsRow: String? = null,
) {
    /** A session saved before the current search ranking restarts its result pages, keeping the scope. */
    fun migrated(): HadithSession {
        if (searchRankingVersion == RANKING_VERSION) return this
        if (request.query.isEmpty()) return copy(searchRankingVersion = RANKING_VERSION)
        return copy(
            searchRankingVersion = RANKING_VERSION,
            request = request.copy(cursor = HadithCursor()),
            history = emptyList(),
            cursorSources = emptyList(),
            listOffset = 0.0,
            listRow = null,
        )
    }

    fun encode(): String = json.encodeToString(serializer(), this)

    companion object {
        const val RANKING_VERSION = 2
        private val json =
            Json {
                ignoreUnknownKeys = true
                encodeDefaults = true
            }

        /** The saved session, migrated; a fresh one when [text] is missing or unreadable. */
        fun decode(text: String?): HadithSession {
            if (text == null) return HadithSession()
            return runCatching {
                val element = json.parseToJsonElement(text).jsonObject
                val session = json.decodeFromJsonElement(serializer(), element)
                // Like Swift's optional, a missing version means an older session (not the default).
                if ("searchRankingVersion" in element) session else session.copy(searchRankingVersion = null)
            }.getOrNull()?.migrated() ?: HadithSession()
        }
    }
}

package com.aljaroudi.muntathir.core.text

/** Where a search was made; each keeps its own recent searches. Swift `SearchHistory.Area` (minus locations). */
enum class SearchArea(
    val id: String,
) {
    Quran("quran"),
    Hadith("hadith"),
    Supplications("supplications"),
    Rulings("rulings"),
    Saved("saved"),
    Figures("figures"),
}

/** Recent searches per area, newest first. Port of Swift `SearchHistory`. */
data class SearchHistory(
    val entries: Map<String, List<String>> = emptyMap(),
) {
    fun queries(area: SearchArea): List<String> = entries[area.id].orEmpty()

    /** Moves [query] (trimmed) to the front, keeping at most [LIMIT]; blank queries change nothing. */
    fun recording(
        query: String,
        area: SearchArea,
    ): SearchHistory {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return this
        return with(area, (listOf(trimmed) + queries(area).filter { it != trimmed }).take(LIMIT))
    }

    fun removing(
        query: String,
        area: SearchArea,
    ): SearchHistory = with(area, queries(area).filter { it != query })

    fun clearing(area: SearchArea): SearchHistory = with(area, emptyList())

    private fun with(
        area: SearchArea,
        queries: List<String>,
    ) = SearchHistory(entries + (area.id to queries))

    companion object {
        const val LIMIT = 20
    }
}

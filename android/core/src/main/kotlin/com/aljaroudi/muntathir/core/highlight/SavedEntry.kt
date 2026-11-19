package com.aljaroudi.muntathir.core.highlight

import com.aljaroudi.muntathir.core.quran.QuranReference
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.SearchRelevance
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** A highlight or bookmark in the Saved list. Port of Swift `SavedEntry`. */
data class SavedEntry(
    val id: String,
    val source: String,
    val isHadith: Boolean,
    val reference: String,
    val excerpt: String,
    val note: String,
    val createdAt: Long,
    val modifiedAt: Long,
    val highlight: ReadingHighlight? = null,
    val bookmark: ReadingBookmark? = null,
) {
    constructor(highlight: ReadingHighlight) : this(
        "highlight:" + highlight.id,
        highlight.source,
        highlight.isHadith,
        highlight.reference,
        highlight.excerpt,
        highlight.note,
        highlight.createdAt,
        highlight.modifiedAt,
        highlight = highlight,
    )

    constructor(bookmark: ReadingBookmark) : this(
        "bookmark:" + bookmark.id,
        bookmark.source,
        bookmark.isHadith,
        bookmark.reference,
        bookmark.excerpt,
        "",
        bookmark.createdAt,
        bookmark.modifiedAt,
        bookmark = bookmark,
    )

    /** The reference, or in Arabic the surah name with the verse reference. */
    fun title(
        language: String,
        surahNames: Map<Int, String>,
    ): String =
        if (bookmark?.kind == ReadingBookmark.Kind.Ruling || isHadith || language != "ar") {
            reference
        } else {
            QuranReference.display(source, language, surahNames)
        }

    fun relevance(
        query: String,
        language: String,
        surahNames: Map<Int, String>,
    ): SearchRelevance? =
        SearchRelevance.score(
            listOf(
                if (isHadith) "" else source,
                reference,
                title(language, surahNames),
                excerpt,
                note,
            ).joinToString(" "),
            QuranSearchText.queryTerms(query),
        )

    /** A Saved section: search matches ("matches"/"related"), a day (`date`), or a source. */
    data class Section(
        val id: String,
        val date: LocalDate?,
        val entries: List<SavedEntry>,
    )

    companion object {
        /** Swift `SavedEntry.sections`: search results by relevance, else groups by source or by day, newest first. */
        fun sections(
            entries: List<SavedEntry>,
            byDate: Boolean,
            query: String,
            zone: ZoneId,
            language: String,
            surahNames: Map<Int, String>,
        ): List<Section> {
            if (query.isNotBlank()) {
                val ranked =
                    entries
                        .mapNotNull { entry -> entry.relevance(query, language, surahNames)?.let { entry to it } }
                        .sortedWith(compareBy<Pair<SavedEntry, SearchRelevance>> { it.second }.thenBy { it.first.id })
                return listOf(false, true).mapNotNull { related ->
                    val values = ranked.filter { (it.second.tier == 2) == related }.map { it.first }
                    if (values.isEmpty()) null else Section(if (related) "related" else "matches", null, values)
                }
            }

            fun day(entry: SavedEntry) = Instant.ofEpochMilli(entry.createdAt).atZone(zone).toLocalDate()
            val groups =
                entries.groupBy { entry ->
                    if (byDate) {
                        "date:${day(entry)}"
                    } else {
                        entry.bookmark?.id ?: ((if (entry.isHadith) "hadith:" else "quran:") + entry.source)
                    }
                }
            return groups
                .map { (key, values) ->
                    val sorted =
                        values.sortedWith(
                            compareByDescending<SavedEntry> { if (byDate) it.createdAt else it.modifiedAt }
                                .thenByDescending { it.id },
                        )
                    Section(key, if (byDate) day(sorted[0]) else null, sorted)
                }.sortedWith(
                    compareByDescending<Section> { section ->
                        section.date
                            ?.atStartOfDay(zone)
                            ?.toInstant()
                            ?.toEpochMilli() ?: section.entries[0].modifiedAt
                    }.thenByDescending { it.id },
                )
        }
    }
}

package com.aljaroudi.muntathir.core.text

import com.aljaroudi.muntathir.core.text.QuranSearchText.fold
import kotlin.math.abs

/** Comparable relevance within explicit match tiers; lower sorts first. Source text stays untouched. */
data class SearchRelevance(
    val tier: Int,
    val missing: Int,
    val fragments: Int,
    val distance: Int,
    val length: Int,
) : Comparable<SearchRelevance> {
    override fun compareTo(other: SearchRelevance): Int =
        compareValuesBy(this, other, { it.tier }, { it.missing }, { it.fragments }, { it.distance }, { it.length })

    companion object {
        /** `null` when [text] isn't a plausible match for [terms] (from [QuranSearchText.terms]). */
        fun score(
            text: String,
            terms: List<String>,
        ): SearchRelevance? {
            if (text.isEmpty() || terms.isEmpty()) return null
            val query = terms.map(::fold)
            val asciiQuery = query.all { term -> term.all { it.code < 128 } }
            if (asciiQuery && query.any { term -> term.any(Char::isLetter) } &&
                text.none { it.code < 128 && it.isLetter() }
            ) {
                return null
            }
            val normalized = fold(QuranSearchText.normalize(text))
            val absent = query.filter { it !in normalized }
            if (absent.size > 1) return null
            if (absent.isNotEmpty() && query.any { it.count() < 3 }) return null
            val words = QuranSearchText.terms(text).map(::fold)
            if (words.isEmpty()) return null
            val positions = mutableListOf<List<Int>>()
            var fragments = 0
            var corrections = 0
            for (term in query) {
                val exact = words.indices.filter { words[it] == term }
                if (exact.isNotEmpty()) {
                    positions += exact
                    continue
                }
                val partial = words.indices.filter { term in words[it] }
                if (partial.isNotEmpty()) {
                    positions += partial
                    fragments += 1
                    continue
                }
                val corrected = words.indices.filter { close(words[it], term) }
                if (corrected.isNotEmpty()) {
                    positions += corrected
                    corrections += 1
                    continue
                }
                positions += emptyList<Int>()
            }
            val missing = positions.count { it.isEmpty() }
            val tier = minOf(QuranSearchText.literalRank(text, terms), 2)
            if (tier == 2) {
                val plausible =
                    query.all { it.count() >= 3 } && missing + corrections <= 1 && (missing == 0 || query.size >= 3)
                if (!plausible) return null
            }
            // Sliding window finds the tightest span covering every matched query term.
            val events = positions.flatMapIndexed { term, offsets -> offsets.map { it to term } }.sortedBy { it.first }
            val required = positions.size - missing
            val counts = mutableMapOf<Int, Int>()
            var left = 0
            var distance = Int.MAX_VALUE
            for (right in events.indices) {
                counts.merge(events[right].second, 1, Int::plus)
                while (counts.size == required && left <= right) {
                    distance = minOf(distance, events[right].first - events[left].first)
                    val key = events[left].second
                    val remaining = counts.getValue(key) - 1
                    if (remaining == 0) counts.remove(key) else counts[key] = remaining
                    left += 1
                }
            }
            return SearchRelevance(tier, missing + corrections, fragments, distance, words.size)
        }

        /** One edit or adjacent transposition, restricted to words with enough evidence. */
        private fun close(
            word: String,
            query: String,
        ): Boolean {
            val a = word.codePoints().toArray()
            val b = query.codePoints().toArray()
            if (b.size < 5 || abs(a.size - b.size) > 1) return false
            if (a.size == b.size) {
                val differences = a.indices.filter { a[it] != b[it] }
                return when (differences.size) {
                    1 -> {
                        true
                    }

                    2 -> {
                        val (first, second) = differences
                        second == first + 1 && a[first] == b[second] && a[second] == b[first]
                    }

                    else -> {
                        false
                    }
                }
            }
            val longer = if (a.size > b.size) a else b
            val shorter = if (a.size > b.size) b else a
            var offset = 0
            for (index in shorter.indices) {
                if (longer[index + offset] != shorter[index]) {
                    if (offset != 0) return false
                    offset = 1
                    if (longer[index + offset] != shorter[index]) return false
                }
            }
            return true
        }

        private fun String.count(): Int = codePointCount(0, length)
    }
}

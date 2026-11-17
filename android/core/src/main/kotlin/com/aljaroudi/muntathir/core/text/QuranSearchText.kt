package com.aljaroudi.muntathir.core.text

import java.text.Normalizer

class InvalidReferenceException : Exception("Invalid Quran reference")

/** Search keys and query parsing. Port of Swift `QuranSearchText`. */
object QuranSearchText {
    /**
     * Search keys only; never apply this to displayed or shared Quran text. Must match the normalization
     * the bundled search indexes were built with (`build/quran/build.sh`, `build/hadith/build.py`).
     */
    fun normalize(text: String): String {
        if (text.all { it.code < 128 }) return text
        val result = StringBuilder(text.length)
        text.codePoints().forEach { scalar ->
            when (scalar) {
                in 0x0610..0x061A, 0x0640, in 0x064B..0x065F, 0x0670, in 0x06D6..0x06ED -> Unit
                0x0622, 0x0623, 0x0625, 0x0671 -> result.append('ا')
                0x0649 -> result.append('ي')
                0x0629 -> result.append('ه')
                else -> result.appendCodePoint(scalar)
            }
        }
        return result.toString()
    }

    /** A whole number written with any decimal digits (e.g. Arabic-Indic), or `null`. */
    fun number(text: String): Int? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null
        val digits = StringBuilder()
        for (codePoint in trimmed.codePoints()) {
            val digit = Character.digit(codePoint, 10)
            if (digit < 0) return null
            digits.append(digit)
        }
        return digits.toString().toIntOrNull()
    }

    /** `surah:verse` when [text] looks like a reference; throws when it does but is out of range. */
    fun reference(text: String): Pair<Int, Int>? {
        val first = text.trim().codePointAtOrNull(0)
        if (':' !in text || first == null || Character.digit(first, 10) < 0) return null
        val parts = text.split(':')
        val surah = parts.getOrNull(0)?.let(::number)
        val verse = parts.getOrNull(1)?.let(::number)
        if (parts.size != 2 || surah == null || verse == null || surah !in 1..114 ||
            verse <= 0
        ) {
            throw InvalidReferenceException()
        }
        return surah to verse
    }

    /** Normalized, lowercased words of a query; never contains FTS syntax characters. */
    fun terms(text: String): List<String> {
        val words = mutableListOf<String>()
        val current = StringBuilder()
        normalize(text).lowercase().codePoints().forEach { codePoint ->
            if (isLetterOrMark(codePoint) || isNumber(codePoint)) {
                current.appendCodePoint(codePoint)
            } else if (current.isNotEmpty()) {
                words += current.toString()
                current.clear()
            }
        }
        if (current.isNotEmpty()) words += current.toString()
        return words
    }

    /** 0: contiguous whole-word phrase, 1: every term occurs literally, 2: no match. */
    fun literalRank(
        text: String,
        terms: List<String>,
    ): Int {
        val keys = terms.map(::fold)
        if (keys.isEmpty()) return 2
        // Latin queries cannot match Arabic-only text; check them before normalizing whole narrations.
        val folded by lazy { fold(text) }
        for (term in keys.sortedByDescending { it.length }) {
            if (term.isAscii() && term !in folded) return 2
        }
        if (keys.size == 1) {
            val term = keys[0]
            val source = if (term.isAscii()) folded else fold(normalize(text))
            var start = 0
            var rank = 2
            while (start < source.length) {
                val found = source.indexOf(term, start)
                if (found < 0 || term.isEmpty()) break
                val end = found + term.length
                val begins = found == 0 || !isWordCharacter(source.codePointBefore(found))
                val ends = end == source.length || !isWordCharacter(source.codePointAt(end))
                if (begins && ends) return 0
                rank = 1
                start = end
            }
            return rank
        }
        val words = terms(text).map(::fold)
        for (start in 0..words.size - keys.size) {
            if (words.subList(start, start + keys.size) == keys) return 0
        }
        return if (keys.all { term -> words.any { term in it } }) 1 else 2
    }

    fun isSearchableVerse(text: String): Boolean =
        normalize(text).codePoints().filter { it in 0x0600..0x06FF && Character.isLetter(it) }.count() >= 7

    /** Foundation `folding(options: [.diacriticInsensitive, .caseInsensitive])`. */
    internal fun fold(text: String): String {
        val decomposed = Normalizer.normalize(text, Normalizer.Form.NFD)
        val stripped = StringBuilder(decomposed.length)
        decomposed.codePoints().forEach {
            if (Character.getType(it).toByte() != Character.NON_SPACING_MARK) stripped.appendCodePoint(it)
        }
        return Normalizer.normalize(stripped, Normalizer.Form.NFC).lowercase()
    }

    private fun isWordCharacter(codePoint: Int) = Character.isLetter(codePoint) || isNumber(codePoint)

    private fun String.isAscii() = all { it.code < 128 }
}

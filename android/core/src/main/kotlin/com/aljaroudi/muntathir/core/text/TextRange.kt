package com.aljaroudi.muntathir.core.text

import java.text.BreakIterator

/** A UTF-16 range, like `NSRange`; Kotlin string indices are the same units. */
data class TextRange(
    val location: Int,
    val length: Int,
) {
    val end: Int get() = location + length

    fun intersects(other: TextRange): Boolean = minOf(end, other.end) - maxOf(location, other.location) > 0

    fun union(other: TextRange): TextRange {
        val start = minOf(location, other.location)
        return TextRange(start, maxOf(end, other.end) - start)
    }

    companion object {
        fun of(
            start: Int,
            end: Int,
        ) = TextRange(start, end - start)
    }
}

fun String.substring(range: TextRange): String = substring(range.location, range.end)

/** User-perceived characters (Swift `Character`s) as UTF-16 ranges. */
internal fun graphemes(
    text: String,
    from: Int = 0,
    to: Int = text.length,
): List<TextRange> {
    val iterator = BreakIterator.getCharacterInstance()
    iterator.setText(text.substring(from, to))
    val result = mutableListOf<TextRange>()
    var start = iterator.first()
    var end = iterator.next()
    while (end != BreakIterator.DONE) {
        result += TextRange.of(from + start, from + end)
        start = end
        end = iterator.next()
    }
    return result
}

internal fun String.codePointAtOrNull(index: Int): Int? = if (index in indices) codePointAt(index) else null

internal fun isLetterOrMark(codePoint: Int): Boolean =
    Character.isLetter(codePoint) ||
        when (Character.getType(codePoint).toByte()) {
            Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK -> true
            else -> false
        }

internal fun isNumber(codePoint: Int): Boolean =
    when (Character.getType(codePoint).toByte()) {
        Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
        else -> false
    }

/** Swift `Character.isWhitespace` (includes newlines). */
internal fun isWhitespace(codePoint: Int): Boolean =
    Character.isWhitespace(codePoint) || Character.isSpaceChar(codePoint)

/** Swift `Character.isNewline`. */
internal fun isNewline(codePoint: Int): Boolean =
    codePoint in 0x0A..0x0D || codePoint == 0x85 || codePoint == 0x2028 || codePoint == 0x2029

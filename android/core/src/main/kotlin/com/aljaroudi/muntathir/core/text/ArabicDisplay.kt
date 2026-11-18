package com.aljaroudi.muntathir.core.text

/** UTF-16 boundaries for displaying a passage and saving selections against its source. */
class ArabicDisplay(
    source: StyledText,
) {
    private val displayed = IntArray(source.length + 1)
    private val original = IntArray(source.length + 1)
    val text: StyledText

    init {
        val plain = StringBuilder(source.length)
        source.text.forEachIndexed { index, char ->
            if (!isMark(char)) plain.append(char)
            displayed[index + 1] = plain.length
            original[plain.length] = index + 1
        }
        text =
            StyledText(
                plain.toString(),
                source.spans.mapNotNull { span ->
                    span.copy(start = displayed[span.start], end = displayed[span.end]).takeIf { it.start < it.end }
                },
            )
    }

    fun displayRange(range: TextRange) = TextRange.of(displayed[range.location], displayed[range.end])

    fun sourceRange(range: TextRange) = TextRange.of(original[range.location], original[range.end])

    companion object {
        fun isMark(char: Char) =
            char in '\u064b'..'\u0652' || char in '\u0656'..'\u0657' || char == '\u0670' ||
                char == '\u06e1' || char in '\u08f0'..'\u08f2'
    }
}

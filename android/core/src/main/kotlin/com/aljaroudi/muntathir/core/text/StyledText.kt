package com.aljaroudi.muntathir.core.text

/** Platform-neutral inline styles; the app maps them to `AnnotatedString` or `Spannable` styles. */
sealed interface TextStyle {
    data object Strong : TextStyle

    data object Emphasis : TextStyle

    data object Code : TextStyle

    data object Strikethrough : TextStyle

    data class Link(
        val url: String,
    ) : TextStyle

    /** A search match: underlined and bold, so it doesn't rely on color alone. */
    data object Match : TextStyle
}

/** [start]..<[end] in UTF-16 units. */
data class TextSpan(
    val start: Int,
    val end: Int,
    val style: TextStyle,
)

/** Plain text plus styled spans. Immutable; operations return new values. */
data class StyledText(
    val text: String,
    val spans: List<TextSpan> = emptyList(),
) {
    val length: Int get() = text.length

    fun has(style: TextStyle): Boolean = spans.any { it.style == style }

    fun spans(style: TextStyle): List<TextSpan> = spans.filter { it.style == style }

    fun styled(
        start: Int,
        end: Int,
        vararg styles: TextStyle,
    ): StyledText = if (start >= end) this else copy(spans = spans + styles.map { TextSpan(start, end, it) })

    /** The text in [start]..<[end], with spans clipped to it. */
    fun slice(
        start: Int,
        end: Int,
    ): StyledText =
        StyledText(
            text.substring(start, end),
            spans.mapNotNull { span ->
                val s = maxOf(span.start, start)
                val e = minOf(span.end, end)
                if (s < e) TextSpan(s - start, e - start, span.style) else null
            },
        )

    /** Removes [start]..<[end], shifting later spans and dropping emptied ones. */
    fun removing(
        start: Int,
        end: Int,
    ): StyledText {
        val removed = end - start

        fun shift(offset: Int) =
            when {
                offset <= start -> offset
                offset >= end -> offset - removed
                else -> start
            }
        return StyledText(
            text.removeRange(start, end),
            spans.map { TextSpan(shift(it.start), shift(it.end), it.style) }.filter { it.start < it.end },
        )
    }

    operator fun plus(other: StyledText): StyledText =
        StyledText(
            text + other.text,
            spans + other.spans.map { it.copy(start = it.start + length, end = it.end + length) },
        )

    operator fun plus(other: String): StyledText = copy(text = text + other)

    companion object {
        fun join(
            parts: List<StyledText>,
            separator: String,
        ): StyledText = parts.reduceOrNull { result, part -> result + separator + part } ?: StyledText("")
    }
}

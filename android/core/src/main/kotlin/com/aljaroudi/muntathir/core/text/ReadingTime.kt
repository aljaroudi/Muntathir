package com.aljaroudi.muntathir.core.text

/** A deliberately simple estimate of the primary text, independent of enabled translations. */
object ReadingTime {
    enum class Unit { Minutes, Hours }

    data class Duration(
        val value: Int,
        val unit: Unit,
    )

    private val image = Regex("""!\[([^\]]*)]\([^)]*\)""")
    private val link = Regex("""\[([^\]]*)]\([^)]*\)""")
    private val autolink = Regex("""<((?:https?|mailto):[^>\s]+)>""")
    private val markers = Regex("""[*_~`]""")

    /** Words in [arabic], or in [english] when the Arabic is blank. Only letter-bearing tokens count. */
    fun words(
        arabic: String,
        english: String = "",
    ): Int {
        val source = if (arabic.isBlank()) english else arabic
        return stripInlineMarkdown(source)
            .split(Regex("\\s+"))
            .count { token -> token.codePoints().anyMatch(Character::isLetter) }
    }

    fun minutes(words: Int): Int = if (words > 0) maxOf(1, (words + 199) / 200) else 0

    /** One unit: minutes below an hour, otherwise whole hours rounded up. */
    fun duration(words: Int): Duration? {
        val minutes = minutes(words)
        if (minutes <= 0) return null
        return if (minutes < 60) Duration(minutes, Unit.Minutes) else Duration((minutes + 59) / 60, Unit.Hours)
    }

    /** Inline-only Markdown, like Swift's `.inlineOnlyPreservingWhitespace`: block syntax such as `#` stays. */
    internal fun stripInlineMarkdown(text: String): String =
        text
            .replace(image, "$1")
            .replace(link, "$1")
            .replace(autolink, "$1")
            .replace(markers, "")
}

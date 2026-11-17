package com.aljaroudi.muntathir.core.highlight

import com.aljaroudi.muntathir.core.text.TextRange
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.text.Normalizer
import java.util.UUID

/** A saved selection in UTF-16 offsets, with its [quote] to detect source text that changed since. */
@Serializable
data class HighlightRange(
    val location: Int,
    val length: Int,
    val quote: String,
) {
    /** The range if it still fits [text] and still covers the same quote (canonically equivalent), else `null`. */
    fun validated(text: String): TextRange? {
        val range = TextRange(location, length)
        if (!fits(range, text)) return null
        return range.takeIf { equivalent(text.substring(location, range.end), quote) }
    }

    companion object {
        /** `null` for empty or out-of-bounds ranges, or ranges that split a surrogate pair. */
        fun of(
            range: TextRange,
            text: String,
        ): HighlightRange? =
            if (fits(
                    range,
                    text,
                )
            ) {
                HighlightRange(range.location, range.length, text.substring(range.location, range.end))
            } else {
                null
            }

        private fun fits(
            range: TextRange,
            text: String,
        ): Boolean {
            if (range.location < 0 || range.length <= 0 || range.location > text.length ||
                range.length > text.length - range.location
            ) {
                return false
            }

            fun splits(offset: Int) =
                offset in 1 until text.length && text[offset - 1].isHighSurrogate() && text[offset].isLowSurrogate()
            return !splits(range.location) && !splits(range.end)
        }

        private fun equivalent(
            a: String,
            b: String,
        ) = a == b || Normalizer.normalize(a, Normalizer.Form.NFC) == Normalizer.normalize(b, Normalizer.Form.NFC)
    }
}

/** Palette order matches iOS; [Cyan] is shown as "Pearl". */
@Serializable
enum class HighlightColor {
    @SerialName("yellow")
    Yellow,

    @SerialName("green")
    Green,

    @SerialName("blue")
    Blue,

    @SerialName("pink")
    Pink,

    @SerialName("purple")
    Purple,

    @SerialName("orange")
    Orange,

    @SerialName("red")
    Red,

    @SerialName("mint")
    Mint,

    @SerialName("teal")
    Teal,

    @SerialName("cyan")
    Cyan,

    @SerialName("indigo")
    Indigo,

    @SerialName("brown")
    Brown,
}

/** A highlight of a verse, hadith or supplication. Port of Swift `ReadingHighlight`. */
@Serializable
data class ReadingHighlight(
    val source: String,
    val isHadith: Boolean,
    /** `null` covers the whole item; otherwise "arabic", "english", "englishNarrator", an edition id, … */
    val block: String? = null,
    val ranges: List<HighlightRange> = emptyList(),
    val excerpt: String,
    val reference: String,
    val color: HighlightColor = HighlightColor.Yellow,
    val note: String = "",
    val id: String = UUID.randomUUID().toString().uppercase(),
    /** Epoch milliseconds. */
    val createdAt: Long = System.currentTimeMillis(),
    val modifiedAt: Long = createdAt,
) {
    /** Ranges to draw in [text] of [block]: everything for whole-item highlights, and all ranges or none otherwise. */
    fun ranges(
        text: String,
        block: String,
    ): List<TextRange> {
        val selected = this.block ?: return listOf(TextRange(0, text.length))
        if (selected != block) return emptyList()
        val validated = ranges.mapNotNull { it.validated(text) }
        return if (validated.size == ranges.size) validated else emptyList()
    }

    fun isAvailable(blocks: Map<String, String>): Boolean {
        val block = block ?: return true
        val text = blocks[block] ?: return false
        return ranges.isNotEmpty() && ranges.all { it.validated(text) != null }
    }
}

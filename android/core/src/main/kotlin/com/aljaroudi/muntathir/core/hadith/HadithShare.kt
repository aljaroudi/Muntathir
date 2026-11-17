package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.text.HadithText
import java.util.Locale

/** What copying, sharing and bookmarking a narration use. Port of Swift `HadithShareContent`. */
data class HadithShareContent(
    val narration: Hadith,
    val showEnglish: Boolean,
    val locale: Locale,
) {
    /** "Book · 12", or a supplication's title. */
    val reference: String
        get() {
            if (narration.isSupplication) return narration.chapter.title(locale)
            return narration.chapter.bookTitle(locale) + (narration.displayNumber?.let { " · $it" } ?: "")
        }

    private val translatedTexts: List<String>
        get() =
            when {
                narration.isSupplication -> listOfNotNull(narration.translation?.text)
                showEnglish -> listOf(narration.englishNarrator, narration.english)
                else -> emptyList()
            }

    /** Arabic, translations and the reference, as Markdown source. */
    val text: String get() =
        (listOf(narration.arabic) + translatedTexts + reference)
            .filter {
                it.isNotEmpty()
            }.joinToString("\n\n")

    /** The bookmark excerpt: plain text without the reference. */
    val body: String
        get() =
            (listOf(narration.arabic) + translatedTexts)
                .filter { it.isNotEmpty() }
                .joinToString("\n\n") { HadithText.flattened(HadithText.markdown(it)).text }
}

/** The reader text of every highlightable block, as saved highlight ranges index into it. */
val HadithDetail.highlightBlocks: Map<String, String>
    get() =
        buildMap {
            put(HadithBlock.ARABIC, HadithText.canonical(arabicText).text)
            put(HadithBlock.ENGLISH, HadithText.canonical(englishText).text)
            put(HadithBlock.NARRATOR, HadithText.canonical(narratorText).text)
            narration.translation?.let { put(it.block, HadithText.canonical(HadithText.markdown(it.text)).text) }
        }

/** Highlight block names, shared with iOS. */
object HadithBlock {
    const val ARABIC = "arabic"
    const val ENGLISH = "english"
    const val NARRATOR = "englishNarrator"

    /** Followed by a translation's `language:edition`. */
    const val TRANSLATION_PREFIX = "translation:"
}

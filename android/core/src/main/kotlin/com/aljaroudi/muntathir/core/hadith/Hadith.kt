package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.text.HadithParagraph
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.SearchRelevance
import com.aljaroudi.muntathir.core.text.StyledText
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.util.Base64
import java.util.Locale

private val Locale.isArabic get() = language == "ar"

/** A book (collection of volumes). Port of Swift `HadithCollection`. */
data class HadithCollection(
    val id: String,
    val arabic: String,
    val english: String,
    val count: Int,
) {
    val group: HadithBookGroup get() = HadithBookGroup.of(id)

    fun title(locale: Locale) = if (locale.isArabic || english.isEmpty()) arabic else english

    fun matches(query: String): Boolean {
        val text = QuranSearchText.normalize("$arabic $english").lowercase()
        return SearchRelevance.score(text, QuranSearchText.terms(query)) != null
    }
}

data class HadithChapter(
    val id: Int,
    val arabic: String,
    val english: String,
    val bookArabic: String,
    val bookEnglish: String,
    val collectionID: String = "",
    /** Zero-based position within its volume. */
    val index: Int = 0,
    val bookID: String = "",
    val count: Int = 0,
    val readingWords: Int = 0,
) {
    fun matches(query: String): Boolean {
        if (query.isBlank()) return true
        val text = QuranSearchText.normalize("$arabic $english $bookArabic $bookEnglish").lowercase()
        return SearchRelevance.score(text, QuranSearchText.terms(query)) != null
    }

    fun title(locale: Locale): String {
        val book = bookTitle(locale)
        val chapter = chapterTitle(locale)
        return if (chapter.isEmpty()) book else "$book · $chapter"
    }

    fun bookTitle(locale: Locale) = if (locale.isArabic || bookEnglish.isEmpty()) bookArabic else bookEnglish

    fun chapterTitle(locale: Locale) =
        if ((locale.isArabic && arabic.isNotEmpty()) ||
            english.isEmpty()
        ) {
            arabic
        } else {
            english
        }
}

/**
 * One narration. In pages, [arabic] and [english] hold short previews (with [arabicPreview]/[englishPreview]
 * styling); full text is loaded only by [HadithReader.detail].
 */
data class Hadith(
    val id: Int,
    val collectionID: String,
    val number: Int,
    val chapter: HadithChapter,
    val arabic: String,
    val englishNarrator: String,
    val english: String,
    val source: HadithSource? = null,
    val arabicPreview: StyledText? = null,
    val englishPreview: StyledText? = null,
    val readingWords: Int = 0,
    val readingNumber: Int? = null,
    val translation: SupplicationTranslation? = null,
) {
    val isSupplication: Boolean get() = collectionID in SUPPLICATION_COLLECTION_IDS

    /** The printed number readers cite; supplications have none. */
    val displayNumber: Int?
        get() =
            when {
                collectionID in SOURCE_NUMBERED -> source?.sourceID
                isSupplication -> null
                else -> readingNumber ?: number
            }

    companion object {
        const val SUPPLICATION_COLLECTION_ID = "openiti-Sahifa-Sajjadiyya"
        val SUPPLICATION_COLLECTION_IDS = listOf(SUPPLICATION_COLLECTION_ID, "mafatih-supplications")
        internal val SOURCE_NUMBERED = setOf("openiti-wasail", "openiti-bihar")
    }
}

data class HadithPage(
    val rows: List<Hadith>,
    val hasMore: Boolean,
    val nextCursor: HadithCursor? = null,
    val relatedIDs: Set<Int> = emptySet(),
)

/** A narration with full text, styled for search terms, and its neighbours in the same book. */
data class HadithDetail(
    val narration: Hadith,
    val author: String,
    val authorArabic: String,
    val gradings: List<HadithGrading>,
    val previousID: Int?,
    val nextID: Int?,
    val arabicText: List<HadithParagraph> = emptyList(),
    val englishText: List<HadithParagraph> = emptyList(),
    val narratorText: List<HadithParagraph> = emptyList(),
) {
    fun authorName(locale: Locale) = if (locale.isArabic && authorArabic.isNotEmpty()) authorArabic else author
}

@Serializable
data class HadithRequest(
    val query: String = "",
    val collectionID: String? = null,
    val chapterID: Int? = null,
    val number: Int? = null,
    val cursor: HadithCursor = HadithCursor(),
)

data class HadithGrading(
    val id: Int,
    val graderID: String?,
    val graderArabic: String,
    val graderEnglish: String,
    val gradeArabic: String,
    val gradeEnglish: String,
    val referenceArabic: String,
    val referenceEnglish: String,
    val status: String,
    val originalText: String,
) {
    fun grader(locale: Locale) = localized(graderArabic, graderEnglish, locale)

    fun judgment(locale: Locale) = localized(gradeArabic, gradeEnglish, locale)

    fun reference(locale: Locale) = localized(referenceArabic, referenceEnglish, locale)

    private fun localized(
        arabic: String,
        english: String,
        locale: Locale,
    ) = if (locale.isArabic) arabic.ifEmpty { english } else english.ifEmpty { arabic }
}

enum class HadithBookGroup {
    Four,
    Six,
    Other,
    ;

    companion object {
        fun of(collectionID: String): HadithBookGroup =
            when (collectionID) {
                "bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah" -> {
                    Six
                }

                "alkafi", "additional-Man-La-Yahduruh-al-Faqih-Saduq", "additional-Tahdhib-al-Ahkam-Tusi",
                "additional-Al-Istibsar-Tusi",
                -> {
                    Four
                }

                else -> {
                    Other
                }
            }
    }
}

@Serializable
data class HadithCursor(
    @Serializable(PhaseSerializer::class) val phase: Phase = Phase.Words,
    val afterID: Int = 0,
) {
    enum class Phase { Words, Substring, Broader }
}

/** Swift encodes the phase as its raw `Int`. */
private object PhaseSerializer : KSerializer<HadithCursor.Phase> {
    override val descriptor = PrimitiveSerialDescriptor("HadithCursor.Phase", PrimitiveKind.INT)

    override fun serialize(
        encoder: Encoder,
        value: HadithCursor.Phase,
    ) = encoder.encodeInt(value.ordinal)

    override fun deserialize(decoder: Decoder) =
        HadithCursor.Phase.entries.getOrElse(decoder.decodeInt()) { HadithCursor.Phase.Words }
}

/** Source identity: survives generated SQLite row renumbering. Saved highlights and bookmarks use [key]. */
@Serializable
data class HadithSource(
    val book: String,
    val chapterFile: String,
    val number: Int,
    val sourceID: Int? = null,
) {
    /** Base64 of the sorted-key JSON Swift's `JSONEncoder` writes (slashes escaped, nil omitted). */
    val key: String
        get() {
            val json =
                buildString {
                    append("{\"book\":").append(swiftJSON(book))
                    append(",\"chapterFile\":").append(swiftJSON(chapterFile))
                    append(",\"number\":").append(number)
                    if (sourceID != null) append(",\"sourceID\":").append(sourceID)
                    append('}')
                }
            return Base64.getEncoder().encodeToString(json.toByteArray())
        }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun fromKey(key: String): HadithSource? =
            runCatching {
                json.decodeFromString<HadithSource>(Base64.getDecoder().decode(key).decodeToString())
            }.getOrNull()

        private fun swiftJSON(value: String) =
            buildString {
                append('"')
                for (character in value) {
                    when (character) {
                        '"' -> {
                            append("\\\"")
                        }

                        '\\' -> {
                            append("\\\\")
                        }

                        '/' -> {
                            append("\\/")
                        }

                        '\n' -> {
                            append("\\n")
                        }

                        '\r' -> {
                            append("\\r")
                        }

                        '\t' -> {
                            append("\\t")
                        }

                        '\b' -> {
                            append("\\b")
                        }

                        '\u000C' -> {
                            append("\\f")
                        }

                        else -> {
                            if (character.code <
                                0x20
                            ) {
                                append("\\u%04x".format(character.code))
                            } else {
                                append(character)
                            }
                        }
                    }
                }
                append('"')
            }
    }
}

/** Chapters grouped by volume, in database order. */
data class HadithContentsGroup(
    val id: String,
    val chapters: List<HadithChapter>,
) {
    companion object {
        fun groups(
            chapters: List<HadithChapter>,
            matching: String = "",
        ): List<HadithContentsGroup> =
            chapters
                .filter { it.matches(matching) }
                .groupBy { it.bookID }
                .map { (id, chapters) -> HadithContentsGroup(id, chapters) }
    }
}

data class HadithIntroduction(
    val id: Int,
    val title: String,
    val arabic: String,
    val english: String,
    val bookArabic: String,
    val bookEnglish: String,
    val readingWords: Int = 0,
) {
    fun bookTitle(locale: Locale) = if (locale.isArabic || bookEnglish.isEmpty()) bookArabic else bookEnglish
}

/** A title in the library and whether it's installed, with its share of the file. */
data class DownloadedBook(
    val id: String,
    val arabic: String,
    val english: String,
    val installed: Boolean,
    val estimatedBytes: Long? = null,
) {
    fun title(locale: Locale) = if (locale.isArabic || english.isEmpty()) arabic else english
}

/** Number and chapter lookups typed into hadith search. */
object HadithSearch {
    /** A narration number in any decimal digits, ignoring spaces. */
    fun number(query: String): Int? = QuranSearchText.number(query.filterNot(Char::isWhitespace))?.takeIf { it > 0 }

    /** `ch12` or `ج12`: a one-based chapter number. */
    fun chapter(query: String): Int? {
        val text = query.trim().lowercase()
        val digits =
            when {
                text.startsWith("ch") -> text.drop(2)
                text.startsWith("ج") -> text.drop(1)
                else -> return null
            }
        if (digits.any(Char::isWhitespace)) return null
        return number(digits)
    }
}

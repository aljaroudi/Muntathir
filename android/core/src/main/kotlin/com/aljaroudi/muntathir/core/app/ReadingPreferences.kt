package com.aljaroudi.muntathir.core.app

import com.aljaroudi.muntathir.core.hadith.SupplicationTranslation
import com.aljaroudi.muntathir.core.highlight.HighlightColor
import com.aljaroudi.muntathir.core.highlight.HighlightPalette
import com.aljaroudi.muntathir.core.quran.QuranTranslation
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.util.Locale

enum class QuranReadingMode(
    val id: String,
) {
    Verses("verses"),
    Mushaf("mushaf"),
}

/**
 * Reader choices that iOS syncs through iCloud key-value storage (`ReadingPreferencesSync.keys`), under the same
 * keys and validation. Stored as one backed-up JSON file; an invalid value falls back to its default on its own.
 */
data class ReadingPreferences(
    val readingSizePercent: Int = DEFAULT_SIZE,
    val quranReadingMode: QuranReadingMode = QuranReadingMode.Verses,
    /** [QuranTranslation.AUTO], [QuranTranslation.NONE] or a catalog id. */
    val quranTranslationSelection: String = QuranTranslation.AUTO,
    val highlightColorCount: Int = HighlightPalette.DEFAULT_COUNT,
    val highlightColorOrder: String = HighlightPalette.defaultOrder,
    val savedGroupByDate: Boolean = false,
    /** Shows English with hadith; `null` until chosen, which follows the device languages. */
    val hadithEnglishEnabled: Boolean? = null,
    /** `auto`, `none` or a language code (Swift `supplicationTranslation.v2`). */
    val supplicationTranslation: String = SupplicationTranslation.AUTO,
) {
    /** Whether hadith show English: the choice, else whether English comes before Arabic in [languages]. */
    fun showsHadithEnglish(languages: List<Locale>) =
        hadithEnglishEnabled ?: SupplicationTranslation.prefersEnglish(languages)

    val highlightColors: List<HighlightColor> get() = HighlightPalette.colors(highlightColorOrder, highlightColorCount)

    /** The values iOS would accept; anything else is replaced with its default. */
    fun validated(): ReadingPreferences {
        val defaults = ReadingPreferences()
        return copy(
            readingSizePercent = readingSizePercent.takeIf { it in SIZES } ?: defaults.readingSizePercent,
            quranTranslationSelection =
                quranTranslationSelection.takeIf(QuranTranslation::isValidSelection)
                    ?: defaults.quranTranslationSelection,
            highlightColorCount = highlightColorCount.takeIf { it in 1..12 } ?: defaults.highlightColorCount,
            highlightColorOrder =
                highlightColorOrder.takeIf(HighlightPalette::validOrder) ?: defaults.highlightColorOrder,
            supplicationTranslation =
                supplicationTranslation.takeIf(::isValidSupplicationTranslation) ?: defaults.supplicationTranslation,
        )
    }

    fun encode(): String =
        buildJsonObject {
            put(SIZE, readingSizePercent)
            put(MODE, quranReadingMode.id)
            put(TRANSLATION, quranTranslationSelection)
            put(COLOR_COUNT, highlightColorCount)
            put(COLOR_ORDER, highlightColorOrder)
            put(GROUP_BY_DATE, savedGroupByDate)
            hadithEnglishEnabled?.let { put(HADITH_ENGLISH, it) }
            put(SUPPLICATION_TRANSLATION, supplicationTranslation)
        }.toString()

    companion object {
        const val DEFAULT_SIZE = 100
        val SIZES = 80..160
        const val SIZE_STEP = 10

        private const val SIZE = "readingSizePercent"
        private const val MODE = "quranReadingMode"
        private const val TRANSLATION = "quranTranslationSelection.v2"
        private const val COLOR_COUNT = "highlightColorCount"
        private const val COLOR_ORDER = "highlightColorOrder"
        private const val GROUP_BY_DATE = "savedGroupByDate"
        private const val HADITH_ENGLISH = "hadithEnglishEnabled.v2"
        private const val SUPPLICATION_TRANSLATION = "supplicationTranslation.v2"

        /** Swift: `auto`, `none` or an ISO language code. */
        fun isValidSupplicationTranslation(value: String) =
            value == SupplicationTranslation.AUTO || value == SupplicationTranslation.NONE ||
                value in Locale.getISOLanguages()

        /** Each key is checked like Swift `ReadingPreferencesSync.valid`; strings and booleans must have their JSON type. */
        fun decode(text: String): ReadingPreferences {
            val json =
                runCatching {
                    Json
                        .parseToJsonElement(
                            text,
                        ).jsonObject
                }.getOrElse { return ReadingPreferences() }
            val defaults = ReadingPreferences()
            return ReadingPreferences(
                readingSizePercent = json.integer(SIZE)?.takeIf { it in SIZES } ?: defaults.readingSizePercent,
                quranReadingMode =
                    json.string(MODE)?.let { id -> QuranReadingMode.entries.firstOrNull { it.id == id } }
                        ?: defaults.quranReadingMode,
                quranTranslationSelection =
                    json.string(TRANSLATION)?.takeIf(QuranTranslation::isValidSelection)
                        ?: defaults.quranTranslationSelection,
                highlightColorCount = json.integer(COLOR_COUNT)?.takeIf { it in 1..12 } ?: defaults.highlightColorCount,
                highlightColorOrder =
                    json.string(COLOR_ORDER)?.takeIf(HighlightPalette::validOrder) ?: defaults.highlightColorOrder,
                savedGroupByDate = json.boolean(GROUP_BY_DATE) ?: defaults.savedGroupByDate,
                hadithEnglishEnabled = json.boolean(HADITH_ENGLISH),
                supplicationTranslation =
                    json.string(SUPPLICATION_TRANSLATION)?.takeIf(::isValidSupplicationTranslation)
                        ?: defaults.supplicationTranslation,
            )
        }

        private fun JsonObject.primitive(key: String): JsonPrimitive? = this[key] as? JsonPrimitive

        private fun JsonObject.string(key: String) = primitive(key)?.takeIf { it.isString }?.contentOrNull

        private fun JsonObject.integer(key: String) = primitive(key)?.takeIf { !it.isString }?.intOrNull

        private fun JsonObject.boolean(key: String) = primitive(key)?.takeIf { !it.isString }?.booleanOrNull
    }
}

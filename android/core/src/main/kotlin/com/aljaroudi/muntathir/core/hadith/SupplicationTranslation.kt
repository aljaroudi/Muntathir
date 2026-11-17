package com.aljaroudi.muntathir.core.hadith

import java.util.Locale

/** One translation of a supplication. Port of Swift `SupplicationTranslation`. */
data class SupplicationTranslation(
    val language: String,
    val edition: String,
    val text: String,
) {
    val id: String get() = "$language:$edition"

    /** The highlight block name. */
    val block: String get() = "translation:$id"

    val isRightToLeft: Boolean get() = Locale.forLanguageTag(language).language in RIGHT_TO_LEFT

    companion object {
        const val AUTO = "auto"
        const val NONE = "none"

        private val RIGHT_TO_LEFT = setOf("ar", "fa", "ur", "he", "iw", "ps", "sd", "ug", "yi", "dv", "ckb")

        /** Whether English comes before Arabic in [languages]; neither means Arabic. */
        fun prefersEnglish(languages: List<Locale>): Boolean {
            for (locale in languages) {
                when (locale.language) {
                    "ar" -> return false
                    "en" -> return true
                }
            }
            return false
        }

        /** [NONE], an explicit `language:edition` id or language, or [AUTO]: the first app language's translation. */
        fun selected(
            translations: List<SupplicationTranslation>,
            selection: String,
            languages: List<Locale>,
        ): SupplicationTranslation? {
            if (selection == NONE) return null
            if (selection != AUTO) return translations.firstOrNull { it.id == selection || it.language == selection }
            for (locale in languages) {
                if (locale.language == "ar") return null
                translations
                    .firstOrNull {
                        Locale
                            .forLanguageTag(
                                it.language,
                            ).language == locale.language
                    }?.let { return it }
            }
            return null
        }
    }
}

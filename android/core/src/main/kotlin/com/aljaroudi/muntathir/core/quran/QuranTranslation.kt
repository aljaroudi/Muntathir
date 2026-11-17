package com.aljaroudi.muntathir.core.quran

import java.util.Locale

/** A Quran translation. English is bundled; the others come from one downloadable pack. Swift `QuranTranslation`. */
data class QuranTranslation(
    /** BCP 47 language tag, e.g. `zh-Hant`. */
    val language: String,
    val translator: String,
    val id: String,
) {
    val isRightToLeft: Boolean get() = Locale.forLanguageTag(language).language in setOf("ar", "fa", "ur", "he")

    companion object {
        val catalog: List<QuranTranslation> =
            listOf(
                QuranTranslation("zh-Hans", "马坚", "zh.jian"),
                QuranTranslation("zh-Hant", "马坚", "zh.majian"),
                QuranTranslation("en", "Ali Quli Qara’i", "en.qarai"),
                QuranTranslation("de", "Bubenheim & Elyas", "de.bubenheim"),
                QuranTranslation("ru", "Кулиев", "ru.kuliev"),
                QuranTranslation("es", "Bornez", "es.bornez"),
                QuranTranslation("fa", "فولادوند", "fa.fooladvand"),
                QuranTranslation("fr", "Hamidullah", "fr.hamidullah"),
                QuranTranslation("id", "Kementerian Agama", "id.indonesian"),
                QuranTranslation("it", "Piccardo", "it.piccardo"),
                QuranTranslation("ms", "Basmeih", "ms.basmeih"),
                QuranTranslation("tr", "Diyanet Vakfı", "tr.vakfi"),
                QuranTranslation("ur", "جوادی", "ur.jawadi"),
            )

        const val BUNDLED_ID = "en.qarai"

        /** Selection values besides a catalog id. */
        const val AUTO = "auto"
        const val NONE = ""

        val downloadable: List<QuranTranslation> get() = catalog.filter { it.id != BUNDLED_ID }

        fun of(id: String): QuranTranslation? = catalog.firstOrNull { it.id == id }

        fun isValidSelection(value: String): Boolean = value == AUTO || value == NONE || of(value) != null

        /** The best match for [locale]: same language and script, then same language; none for Arabic. */
        fun preferred(
            available: List<QuranTranslation>,
            locale: Locale,
        ): QuranTranslation? {
            if (locale.language == "ar") return null
            val script = script(locale)
            return available.firstOrNull {
                val candidate = Locale.forLanguageTag(it.language)
                candidate.language == locale.language && script(candidate) == script
            } ?: available.firstOrNull { Locale.forLanguageTag(it.language).language == locale.language }
        }

        /**
         * The translation for a [selection]: an explicit id, none, or for [AUTO] the first preferred language with
         * a translation. Arabic is itself supported, so an Arabic preference stops the search.
         */
        fun resolve(
            selection: String,
            languages: List<Locale>,
        ): QuranTranslation? {
            if (selection != AUTO) return of(selection)
            for (locale in languages) {
                if (locale.language == "ar") return null
                preferred(catalog, locale)?.let { return it }
            }
            return null
        }

        /** Like Foundation, a bare Chinese locale implies its likely script (Traditional for TW, HK and MO). */
        private fun script(locale: Locale): String {
            if (locale.script.isNotEmpty() || locale.language != "zh") return locale.script
            return if (locale.country in setOf("TW", "HK", "MO")) "Hant" else "Hans"
        }
    }
}

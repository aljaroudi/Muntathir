package com.aljaroudi.muntathir.core.quran

import kotlinx.serialization.Serializable

@Serializable
data class QuranSurah(
    val id: Int,
    val arabic: String,
    val transliteration: String,
)

data class Ayah(
    val surah: Int,
    val number: Int,
    /** Tanzil text; saved highlights refer to it. */
    val text: String,
    val translations: Map<String, String> = emptyMap(),
) {
    val id: String get() = "$surah:$number"
}

/** One page of the 15-line Madani mushaf. Words are QPC Hafs text for the KFGQPC font. */
data class QuranPage(
    val number: Int,
    val lines: List<Line>,
    /** Keyed by the verse's global index. */
    val verses: Map<Int, Ayah>,
) {
    data class Word(
        /** Global verse index. */
        val index: Int,
        /** 1-based word position in the verse. */
        val word: Int,
        val text: String,
    )

    data class Line(
        val number: Int,
        val kind: Kind,
        val centered: Boolean,
        val surah: Int,
        val words: List<Word> = emptyList(),
    ) {
        enum class Kind(
            val id: String,
        ) {
            Ayah("ayah"),
            SurahName("surah_name"),
            Basmallah("basmallah"),
            ;

            companion object {
                fun of(id: String) = entries.firstOrNull { it.id == id } ?: Ayah
            }
        }
    }

    companion object {
        const val COUNT = 604
    }
}

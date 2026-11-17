package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.text.QuranSearchText
import kotlinx.serialization.Serializable

@Serializable
data class QuranSurah(
    val id: Int,
    val arabic: String,
    val transliteration: String,
) {
    /** The Arabic name in an Arabic interface, otherwise the transliteration. */
    fun title(language: String): String = if (language == "ar") arabic else transliteration

    /** Swift `QuranSurah.matches`: a number matches the id; otherwise the Arabic name or transliteration. */
    fun matches(query: String): Boolean {
        QuranSearchText.number(query)?.let { return id == it }
        val normalized = QuranSearchText.fold(QuranSearchText.normalize(query))
        if (QuranSearchText.normalize(arabic).contains(normalized)) return true
        val key = nameKey(query)
        return key.isNotEmpty() && nameKey(transliteration).contains(key)
    }

    private fun nameKey(name: String): String =
        QuranSearchText
            .fold(name)
            .filter(Char::isLetter)
            .replace("aa", "a")
            .replace("ii", "i")
            .replace("uu", "u")
}

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
    val juz: Int = 1,
    /** 1…240; the hizb is `(hizbQuarter + 3) / 4`. */
    val hizbQuarter: Int = 1,
    /** Global indices of prostration verses on the page. */
    val sajdas: Set<Int> = emptySet(),
) {
    /** The surah of the first verse line, else of the first line. */
    val surah: Int get() = lines.firstOrNull { it.kind == Line.Kind.Ayah }?.surah ?: lines.firstOrNull()?.surah ?: 1

    val hizb: Int get() = (hizbQuarter + 3) / 4

    data class Word(
        /** Global verse index. */
        val index: Int,
        /** 1-based word position in the verse. */
        val word: Int,
        val text: String,
    ) {
        val id: String get() = "$index:$word"
    }

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

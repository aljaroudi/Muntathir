package com.aljaroudi.muntathir.core.text

import java.text.Normalizer

/**
 * Port of `shared/lexicon/normalize.py` and the dictionary readers' clitic fallback; the Swift
 * `DictionaryReader` has the same functions. `shared/fixtures/lexicon-normalize.json` holds the
 * cases all three must agree on.
 */
object LexiconSpelling {
    private val marks = Regex("[\u0610-\u061A\u0640\u064B-\u0670\u06D6-\u06ED]")
    private val nonLetters = Regex("[^\u0621-\u063A\u0641-\u064A\u0671\u06A9\u06CC]")
    private val madda = Regex("(?U)ءا(?=\\w)")
    private val spelling = mapOf('ٱ' to 'ا', 'ة' to 'ه', 'ک' to 'ك', 'ی' to 'ي')
    private val hamza = mapOf('أ' to 'ا', 'إ' to 'ا', 'آ' to 'ا', 'ى' to 'ي', 'ؤ' to 'و', 'ئ' to 'ي')
    private val pronouns = listOf("ه", "ها", "هما", "هم", "هن", "ك", "كما", "كم", "كن", "ي", "نا", "ني")

    /** A word as the pack's `words.spelling` keys it: no vowels or marks, standard spelling for Uthmani forms, hamza seats kept. */
    fun spell(text: String): String =
        letters(text)
            .replace(nonLetters, "")
            .map { spelling[it] ?: it }
            .joinToString("")

    /** [spell] with hamza seats and alef maqsura folded, as `words.norm` keys it. */
    fun normalize(text: String): String = spell(text).map { hamza[it] ?: it }.joinToString("")

    private fun letters(text: String): String {
        // Uthmani: alef maqsura carrying a superscript alef is just the maqsura; any other
        // superscript alef is a written alef (السمٰوٰت -> السماوات), and ءا is آ (ءامن، قرءان).
        val folded =
            Normalizer
                .normalize(text, Normalizer.Form.NFKC)
                .replace("ىٰ", "ى")
                .replace("\u0670", "ا")
        return folded.replace(marks, "").replace(madda, "آ")
    }

    /**
     * Readings of a word with its clitics removed, longest first: conjunction, preposition or
     * article in front, pronoun behind. The article never takes a pronoun, and stems keep three letters.
     */
    fun stems(word: String): List<String> {
        val found = mutableListOf<String>()
        for (conjunction in listOf("", "و", "ف")) {
            if (!word.startsWith(conjunction)) continue
            val rest = word.removePrefix(conjunction)
            for (attached in listOf("", "ب", "ك", "ل", "ال", "بال", "كال", "لل")) {
                if (!rest.startsWith(attached)) continue
                var stem = rest.removePrefix(attached)
                // ل before the article drops its alef: للذين = ل + الذين.
                if (attached == "لل") {
                    stem = "ال$stem"
                } else if (attached.endsWith("ال") && stem.startsWith("ال")) {
                    continue
                }
                if (conjunction.isNotEmpty() || attached.isNotEmpty()) found += stem
                if (attached.endsWith("ال") || attached == "لل" || stem.startsWith("ال")) continue
                for (pronoun in pronouns) {
                    if (stem.endsWith(pronoun)) found += stem.removeSuffix(pronoun)
                }
            }
        }
        return found.filter { it.length >= 3 }.distinct().sortedByDescending { it.length }
    }
}

package com.aljaroudi.muntathir.core.text

import java.util.TreeMap

/** Index terms with the number of verses holding each. */
class QuranVocabulary(
    terms: Map<String, Int>,
) {
    private val docs = TreeMap(terms)

    /** Verses holding the term, or any term starting with it when [prefix]. */
    fun weight(
        spelling: String,
        prefix: Boolean,
    ): Int =
        if (!prefix) {
            docs[spelling] ?: 0
        } else {
            docs
                .tailMap(spelling, true)
                .entries
                .takeWhile { it.key.startsWith(spelling) }
                .sumOf { it.value }
        }
}

/**
 * Typed Arabic to the spelling the Quran word index holds.
 *
 * The index folds the Uthmani text ([QuranSearchText.normalize]): the superscript alef, small ya and
 * other marks are deleted, so words that standard spelling writes with a long vowel lose it:
 * الصلاة is indexed as الصلوه, الكتاب as الكتب, النبيين as النبين, آمنوا as ءامنوا. Typing the standard
 * spelling finds nothing. [resolve] rewrites a typed key to a spelling the index really contains, so it
 * never invents a match. Port of Swift `QuranSpelling` and shared/search/quran_spelling.py;
 * shared/fixtures/quran-spelling.json holds the cases all three must agree on.
 */
object QuranSpelling {
    /** What one alef may stand for in Uthmani spelling: itself, nothing (superscript alef), و or وا (الصلوٰة, الربوٰا), ءا (ءامنوا). Fewest edits first. */
    private val alefs = listOf("ا", "", "و", "وا", "ءا")
    private const val MAX_ALEFS = 3
    private const val MAX_DELETIONS = 6
    private const val MIN_LETTERS = 2
    private val seats = mapOf('و' to 'ؤ', 'ي' to 'ئ', 'ئ' to 'ء', 'ؤ' to 'ء')

    /** Spellings the index may hold for a typed key, with the edits each takes; includes the key itself. */
    fun candidates(key: String): Map<String, Int> {
        val found = mutableMapOf(key to 0)

        fun add(
            spelling: String,
            edits: Int,
        ) {
            found[spelling] = minOf(edits, found[spelling] ?: edits)
        }
        if (key.none { it in '؀'..'ۿ' }) return found
        // A leading alef is a madda (آمنوا = ءامنوا) unless it is the article's.
        val article = key.startsWith("ال")
        val positions = key.indices.filter { key[it] == 'ا' && (it > 0 || !article) }
        val medial = positions.size - if (key.startsWith("ا") && !article) 1 else 0
        val options =
            when {
                medial <= MAX_ALEFS -> alefs
                medial <= MAX_DELETIONS -> alefs.take(2)
                else -> alefs.take(1)
            }
        val choice = IntArray(positions.size)
        while (true) {
            val spelling = StringBuilder()
            var edits = 0
            var last = 0
            var valid = true
            for ((slot, position) in positions.withIndex()) {
                val pick = choice[slot]
                // Only a madda can open a word; the others need a letter before them.
                if (position == 0 && options[pick] != "ا" && options[pick] != "ءا") valid = false
                spelling.append(key, last, position).append(options[pick])
                if (pick != 0) edits++
                last = position + 1
            }
            spelling.append(key, last, key.length)
            if (valid) add(spelling.toString(), edits)
            var slot = positions.size - 1
            while (slot >= 0) {
                choice[slot]++
                if (choice[slot] < options.size) break
                choice[slot] = 0
                slot--
            }
            if (slot < 0) break
        }
        // A doubled ya is one ya plus the small ya the fold deletes (النبيين).
        for ((spelling, edits) in found.entries.toList()) {
            if ("يي" in spelling) add(spelling.replace("يي", "ي"), edits + 1)
        }
        // Typed without the hamza seat that Uthmani spelling keeps (المومنين, الملايكة), or with a seat
        // where the mushaf writes the hamza alone (إسرائيل = اسرءيل).
        for ((spelling, edits) in found.entries.toList()) {
            for ((index, char) in spelling.withIndex()) {
                val seat = seats[char] ?: continue
                add(spelling.substring(0, index) + seat + spelling.substring(index + 1), edits + 1)
            }
        }
        return found.filter { it.key.length >= MIN_LETTERS || it.key == key }
    }

    /**
     * The key if the index holds it, else the spelling it holds with the fewest edits, then the most
     * typed letters kept (replacing an alef beats deleting it), then the most verses.
     */
    fun resolve(
        key: String,
        vocabulary: QuranVocabulary,
        prefix: Boolean = false,
    ): String {
        if (vocabulary.weight(key, prefix) > 0) return key
        return candidates(key)
            .mapNotNull { (spelling, edits) ->
                vocabulary.weight(spelling, prefix).takeIf { it > 0 }?.let {
                    Triple(edits, spelling.length, it) to
                        spelling
                }
            }.minWithOrNull(
                compareBy<Pair<Triple<Int, Int, Int>, String>>(
                    { it.first.first },
                    { -it.first.second },
                    { -it.first.third },
                ).thenBy { it.second },
            )?.second ?: key
    }

    /** Query terms in the spelling the Arabic index holds. */
    fun resolve(
        terms: List<String>,
        vocabulary: QuranVocabulary,
    ): List<String> = terms.map { resolve(it, vocabulary) }
}

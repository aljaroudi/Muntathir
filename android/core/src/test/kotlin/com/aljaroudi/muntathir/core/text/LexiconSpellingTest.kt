package com.aljaroudi.muntathir.core.text

import com.aljaroudi.muntathir.core.Fixtures
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LexiconSpellingTest {
    @Test
    fun spellingMatchesTheLexiconBuild() {
        val words =
            Json
                .parseToJsonElement(
                    Fixtures.text("lexicon-normalize.json"),
                ).jsonObject
                .getValue("words")
                .jsonArray
        assertTrue(words.size > 20)
        for (word in words.map { it.jsonObject }) {
            val text = word.getValue("text").jsonPrimitive.content
            assertEquals(word.getValue("spell").jsonPrimitive.content, LexiconSpelling.spell(text), text)
            assertEquals(word.getValue("normalize").jsonPrimitive.content, LexiconSpelling.normalize(text), text)
        }
    }

    @Test
    fun stemsFollowCliticGrammar() {
        assertEquals(listOf("الكتاب", "كتاب"), LexiconSpelling.stems("والكتاب"))
        assertEquals("الذين", LexiconSpelling.stems("للذين").first())
        assertTrue("أصحاب" in LexiconSpelling.stems("بأصحابه"))
        // The article takes no pronoun, and stems keep three letters.
        assertFalse("الكتاب" in LexiconSpelling.stems("الكتابه"))
        assertTrue(LexiconSpelling.stems("وله").isEmpty())
    }
}

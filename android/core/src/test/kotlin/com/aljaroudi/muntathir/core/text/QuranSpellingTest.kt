package com.aljaroudi.muntathir.core.text

import com.aljaroudi.muntathir.core.Fixtures
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class QuranSpellingTest {
    @Test
    fun resolvesLikeTheReferenceImplementation() {
        val fixture = Json.parseToJsonElement(Fixtures.text("quran-spelling.json")).jsonObject
        val vocabulary =
            QuranVocabulary(
                fixture.getValue("vocabulary").jsonArray.associate {
                    it.jsonObject
                        .getValue("term")
                        .jsonPrimitive.content to
                        it.jsonObject
                            .getValue("docs")
                            .jsonPrimitive.int
                },
            )
        val cases = fixture.getValue("cases").jsonArray.map { it.jsonObject }
        assertTrue(cases.size > 40)
        for (item in fixture.getValue("fold").jsonArray.map { it.jsonObject }) {
            val text = item.getValue("text").jsonPrimitive.content
            assertEquals(item.getValue("key").jsonPrimitive.content, QuranSearchText.normalize(text), text)
        }
        for (item in cases) {
            val typed = item.getValue("typed").jsonPrimitive.content
            val resolved =
                QuranSpelling.resolve(
                    QuranSearchText.normalize(typed),
                    vocabulary,
                    item.getValue("prefix").jsonPrimitive.boolean,
                )
            assertEquals(item.getValue("resolved").jsonPrimitive.content, resolved, typed)
        }
        for (item in fixture.getValue("candidates").jsonArray.map { it.jsonObject }) {
            val key = item.getValue("key").jsonPrimitive.content
            val expected = item.getValue("spellings").jsonObject.mapValues { it.value.jsonPrimitive.int }
            assertEquals(expected, QuranSpelling.candidates(key), key)
        }
    }

    @Test
    fun nonArabicAndUnknownTermsStayAsTyped() {
        val vocabulary = QuranVocabulary(mapOf("الصلوه" to 55, "ءامنوا" to 254))
        assertEquals(
            listOf("ءامنوا", "mercy", "كمبيوتر"),
            QuranSpelling.resolve(listOf("امنوا", "mercy", "كمبيوتر"), vocabulary),
        )
    }
}

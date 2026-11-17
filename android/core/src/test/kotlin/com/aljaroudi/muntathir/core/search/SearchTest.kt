package com.aljaroudi.muntathir.core.search

import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.core.text.SearchHistory
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull

/** Ports of Swift `SearchHistoryTests` and the Quran cases of `SemanticSearchTests`. */
class SearchTest {
    @Test
    fun historyOrdersAndSeparatesAreas() {
        var history = SearchHistory()
        history = history.recording("  mercy ", SearchArea.Quran).recording("patience", SearchArea.Quran)
        history = history.recording("mercy", SearchArea.Quran).recording("   ", SearchArea.Quran)
        history = history.recording("hadith", SearchArea.Hadith)
        assertEquals(listOf("mercy", "patience"), history.queries(SearchArea.Quran))
        assertEquals(listOf("hadith"), history.queries(SearchArea.Hadith))
        assertEquals(listOf("mercy"), history.removing("patience", SearchArea.Quran).queries(SearchArea.Quran))
        assertEquals(emptyList(), history.clearing(SearchArea.Quran).queries(SearchArea.Quran))
        assertEquals(listOf("hadith"), history.clearing(SearchArea.Quran).queries(SearchArea.Hadith))
    }

    @Test
    fun historyKeepsTwentyMostRecentQueries() {
        val history = (1..25).fold(SearchHistory()) { result, index -> result.recording("q$index", SearchArea.Quran) }
        assertEquals((25 downTo 6).map { "q$it" }, history.queries(SearchArea.Quran))
    }

    @Test
    fun directQuranReferenceHasNoSimilarity() {
        val result = SemanticSearchClient.result("""{"kind":"quran","chapter":2,"verse":255,"score":null}""")
        assertEquals("quran:2:255", result.id)
        assertNull(result.score)
        val hadith =
            SemanticSearchClient.result(
                """{"kind":"hadith","book":"alkafi-1","chapter":"1.json","number":1,"score":0.74}""",
            )
        assertEquals(SemanticSearchResult.Reference.Hadith("alkafi-1", "1.json", 1), hadith.reference)
        assertEquals(0.74, hadith.score)
    }

    @Test
    fun invalidResponsesAreRejected() {
        for (json in listOf(
            """{"kind":"quran","chapter":0,"verse":1,"score":0.5}""",
            """{"kind":"quran","chapter":2,"verse":1,"score":2}""",
            """{"kind":"unknown","score":0.5}""",
            """{"kind":"quran","chapter":"2","verse":1}""",
        )) {
            assertFailsWith<SemanticSearchException>(json) { SemanticSearchClient.result(json) }
        }
        assertFailsWith<SemanticSearchException> {
            SemanticSearchClient.decode("""{"results":[{"kind":"quran","chapter":2,"verse":255},{"kind":"x"}]}""")
        }
    }

    @Test
    fun requestEncodesScopeAndOmitsAbsentFilters() {
        fun body(json: String) = Json.parseToJsonElement(json).jsonObject
        val scoped = body(SemanticSearchClient.requestBody("patience", "hadith", listOf("v1"), "1.json"))
        assertEquals(listOf("v1"), scoped["sources"]?.jsonArray?.map { (it as JsonPrimitive).content })
        assertEquals("1.json", (scoped["chapter"] as JsonPrimitive).content)
        assertEquals(listOf("hadith"), scoped["kinds"]?.jsonArray?.map { (it as JsonPrimitive).content })
        assertEquals("20", (scoped["limit"] as JsonPrimitive).content)
        val unscoped = body(SemanticSearchClient.requestBody("patience", "quran", null, null))
        assertFalse("sources" in unscoped || "chapter" in unscoped)
    }

    @Test
    fun endpointMustBeTheHttpsSearchPath() {
        assertEquals("https://example.com/v1/search", SemanticSearchClient.endpoint("https://example.com/v1/search"))
        for (value in listOf(
            null,
            "http://example.com/v1/search",
            "https://example.com/v1/search/",
            "https:///v1/search",
            "nonsense",
        )) {
            assertNull(SemanticSearchClient.endpoint(value), value)
        }
    }

    @Test
    fun clientRejectsFailedResponses(): Unit =
        runBlocking {
            val ok =
                SemanticSearchClient("https://example.com/v1/search") { _, _ ->
                    200 to
                        """{"results":[{"kind":"quran","chapter":2,"verse":255}]}"""
                }
            assertEquals("quran:2:255", ok.search("x", "quran").single().id)
            val failing = SemanticSearchClient("https://example.com/v1/search") { _, _ -> 503 to "" }
            assertFailsWith<SemanticSearchException> { failing.search("x", "quran") }
        }
}

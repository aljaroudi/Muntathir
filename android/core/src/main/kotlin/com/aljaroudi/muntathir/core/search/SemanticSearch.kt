package com.aljaroudi.muntathir.core.search

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.net.URI

/** A smart-search hit. Port of Swift `SemanticSearchResult`. */
data class SemanticSearchResult(
    val reference: Reference,
    /** Cosine similarity; `null` for direct references. */
    val score: Double?,
) {
    sealed interface Reference {
        data class Quran(
            val chapter: Int,
            val verse: Int,
        ) : Reference

        data class Hadith(
            val book: String,
            val chapter: String,
            val number: Int,
        ) : Reference

        data class Figure(
            val id: String,
        ) : Reference

        data class Dua(
            val id: String,
            val passage: Int?,
            val locator: String? = null,
        ) : Reference

        data class Rulings(
            val authority: String,
            val language: String,
            val id: String,
        ) : Reference
    }

    val id: String
        get() =
            when (val reference = reference) {
                is Reference.Quran -> "quran:${reference.chapter}:${reference.verse}"
                is Reference.Hadith -> "hadith:${reference.book}:${reference.chapter}:${reference.number}"
                is Reference.Rulings -> "rulings:${reference.authority}:${reference.language}:${reference.id}"
                is Reference.Figure -> "figure:${reference.id}"
                is Reference.Dua -> "dua:${reference.id}:${reference.passage?.toString().orEmpty()}"
            }
}

class SemanticSearchException(
    message: String,
) : Exception(message)

/** Posts a JSON body and returns the status and body. The app uses Ktor; tests use a fake. */
fun interface SemanticSearchTransport {
    suspend fun post(
        url: String,
        body: String,
    ): Pair<Int, String>
}

/** The `/v1/search` API. Port of Swift `SemanticSearchClient`; nothing leaves the device until the user asks. */
class SemanticSearchClient(
    val endpoint: String,
    private val transport: SemanticSearchTransport,
) {
    suspend fun search(
        query: String,
        kind: String? = null,
        sources: List<String>? = null,
        chapter: String? = null,
        languages: List<String>? = null,
    ): List<SemanticSearchResult> {
        val (status, body) = transport.post(endpoint, requestBody(query, kind, sources, chapter, languages))
        if (status != 200) throw SemanticSearchException("HTTP $status")
        return decode(body)
    }

    companion object {
        const val LIMIT = 20
        const val MAX_QUERY_LENGTH = 512

        /** A valid endpoint: `https`, a host, and exactly the `/v1/search` path. */
        fun endpoint(value: String?): String? {
            val uri = value?.let { runCatching { URI(it) }.getOrNull() } ?: return null
            return value.takeIf { uri.scheme == "https" && !uri.host.isNullOrEmpty() && uri.path == "/v1/search" }
        }

        /** The request body; absent filters are omitted. */
        fun requestBody(
            query: String,
            kind: String?,
            sources: List<String>?,
            chapter: String?,
            languages: List<String>? = null,
        ): String =
            buildJsonObject {
                put("query", query)
                kind?.let { put("kinds", buildJsonArray { add(JsonPrimitive(it)) }) }
                sources?.let { put("sources", JsonArray(it.map(::JsonPrimitive))) }
                chapter?.let { put("chapter", it) }
                languages?.let { put("languages", JsonArray(it.map(::JsonPrimitive))) }
                put("limit", LIMIT)
            }.toString()

        /** `{"results": [...]}`; any invalid result rejects the whole response. */
        fun decode(body: String): List<SemanticSearchResult> {
            val root =
                runCatching { Json.parseToJsonElement(body).jsonObject }.getOrNull()
                    ?: throw SemanticSearchException("Invalid response")
            val results = root["results"] as? JsonArray ?: throw SemanticSearchException("Missing results")
            return results.map { element ->
                result(element as? JsonObject ?: throw SemanticSearchException("Invalid result"))
            }
        }

        fun result(json: String): SemanticSearchResult = result(Json.parseToJsonElement(json).jsonObject)

        private fun result(values: JsonObject): SemanticSearchResult {
            fun string(key: String): String =
                (values[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
                    ?: throw SemanticSearchException("Missing $key")

            fun int(key: String): Int =
                (values[key] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
                    ?: throw SemanticSearchException("Missing $key")

            val score =
                when (val raw = values["score"]) {
                    null, JsonNull -> {
                        null
                    }

                    else -> {
                        (raw as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
                            ?: throw SemanticSearchException("Invalid score")
                    }
                }
            if (score != null && (!score.isFinite() || score !in -1.000001..1.000001)) {
                throw SemanticSearchException("Invalid cosine similarity")
            }
            val reference =
                when (string("kind")) {
                    "quran" -> {
                        val chapter = int("chapter")
                        val verse = int("verse")
                        if (chapter !in 1..114 ||
                            verse !in 1..286
                        ) {
                            throw SemanticSearchException("Invalid Quran reference")
                        }
                        SemanticSearchResult.Reference.Quran(chapter, verse)
                    }

                    "hadith" -> {
                        val book = string("book")
                        val chapter = string("chapter")
                        val number = int("number")
                        if (book.isEmpty() || chapter.isEmpty() ||
                            number < 0
                        ) {
                            throw SemanticSearchException("Invalid Hadith reference")
                        }
                        SemanticSearchResult.Reference.Hadith(book, chapter, number)
                    }

                    "rulings" -> {
                        val authority = string("authority")
                        val language = string("language")
                        val id = string("id")
                        if (authority.isEmpty() || language.isEmpty() || id.isEmpty()) {
                            throw SemanticSearchException("Invalid rulings reference")
                        }
                        SemanticSearchResult.Reference.Rulings(authority, language, id)
                    }

                    "figure" -> {
                        SemanticSearchResult.Reference.Figure(string("id"))
                    }

                    "dua" -> {
                        val passage =
                            if (values["passage"].let { it == null || it == JsonNull }) {
                                null
                            } else {
                                int(
                                    "passage",
                                )
                            }
                        SemanticSearchResult.Reference.Dua(
                            string("id"),
                            passage,
                            if (values.containsKey("locator")) string("locator") else null,
                        )
                    }

                    else -> {
                        throw SemanticSearchException("Unknown content kind")
                    }
                }
            return SemanticSearchResult(reference, score)
        }
    }
}

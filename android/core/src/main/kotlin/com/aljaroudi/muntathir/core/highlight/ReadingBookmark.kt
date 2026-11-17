package com.aljaroudi.muntathir.core.highlight

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put

/** A ruling's identity on its authority's site. Swift `Rulings.ID`. */
data class RulingID(
    val authority: String,
    val language: String,
    val siteID: String,
)

/** A bookmarked verse, narration or ruling. Port of Swift `ReadingBookmark`. */
data class ReadingBookmark(
    val source: String,
    val isHadith: Boolean,
    val excerpt: String,
    val reference: String,
    val ruling: RulingID? = null,
    /** Epoch milliseconds. */
    val createdAt: Long = System.currentTimeMillis(),
    val modifiedAt: Long = createdAt,
) {
    enum class Kind { Quran, Hadith, Ruling }

    val kind: Kind get() =
        if (ruling != null) {
            Kind.Ruling
        } else if (isHadith) {
            Kind.Hadith
        } else {
            Kind.Quran
        }

    /** Stable per item; length prefixes keep ruling ids unambiguous even with punctuation in them. */
    val id: String
        get() =
            ruling?.let { ruling ->
                "ruling:" +
                    listOf(
                        ruling.authority,
                        ruling.language,
                        ruling.siteID,
                    ).joinToString("") { "${it.encodeToByteArray().size}:$it" }
            } ?: ((if (isHadith) "hadith:" else "quran:") + source)

    /** `isHadith` is omitted for rulings so older readers can't mistake them for Quran bookmarks. */
    fun encode(): String =
        buildJsonObject {
            put("source", source)
            if (ruling == null) put("isHadith", isHadith)
            ruling?.let {
                put(
                    "ruling",
                    buildJsonObject {
                        put("authority", it.authority)
                        put("language", it.language)
                        put("siteID", it.siteID)
                    },
                )
            }
            put("excerpt", excerpt)
            put("reference", reference)
            put("createdAt", createdAt)
            put("modifiedAt", modifiedAt)
        }.toString()

    companion object {
        /** `isHadith` is required unless a ruling is present (then it's false). */
        fun decode(json: String): ReadingBookmark {
            val values = Json.parseToJsonElement(json).jsonObject
            val ruling =
                (values["ruling"] as? JsonObject)?.let {
                    RulingID(it.string("authority"), it.string("language"), it.string("siteID"))
                }
            return ReadingBookmark(
                source = values.string("source"),
                isHadith = if (ruling == null) values.getValue("isHadith").jsonPrimitive.boolean else false,
                excerpt = values.string("excerpt"),
                reference = values.string("reference"),
                ruling = ruling,
                createdAt = values.getValue("createdAt").jsonPrimitive.long,
                modifiedAt = values.getValue("modifiedAt").jsonPrimitive.long,
            )
        }

        private fun JsonObject.string(key: String): String =
            (getValue(key) as JsonPrimitive).takeIf { it.isString }?.content
                ?: throw IllegalArgumentException("$key must be a string")
    }
}

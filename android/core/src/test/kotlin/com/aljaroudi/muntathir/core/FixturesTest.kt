package com.aljaroudi.muntathir.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals

class FixturesTest {
    @Test
    fun sharedFixturesAreReadable() {
        val feed = Json.parseToJsonElement(Fixtures.text("corrections-v1.json")).jsonObject
        assertEquals(1, feed.getValue("schemaVersion").jsonPrimitive.int)
        for (name in listOf("Tehran-Tehran.json", "Singapore-Singapore.json", "London-MoonsightingCommittee.json")) {
            Json.parseToJsonElement(Fixtures.text(name))
        }
    }
}

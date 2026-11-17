package com.aljaroudi.muntathir.core.figures

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.figures.FigureLibrary.SiblingDegree
import com.aljaroudi.muntathir.core.figures.FigureLibraryException.Failure
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Ports `FigureLibraryTests`, plus the production dataset as bundled. */
class FigureLibraryTest {
    private val production = Fixtures.repository("shared/figures/figures.json").readText()
    private val example = Fixtures.repository("apple/MuntathirTests/figure-example.json").readText()

    private fun productionLibrary() = FigureLibrary(production, EventLibrary.bundled().events)

    private fun exampleObject() = FigureLibrary.json.parseToJsonElement(example).jsonObject

    private fun JsonObject.with(
        key: String,
        value: JsonElement,
    ) = JsonObject(this + (key to value))

    private fun JsonObject.without(key: String) = JsonObject(this - key)

    private fun JsonObject.list(key: String): MutableList<JsonObject> =
        getValue(key)
            .jsonArray
            .map {
                it.jsonObject
            }.toMutableList()

    private fun JsonObject.with(
        key: String,
        values: List<JsonObject>,
    ) = with(key, JsonArray(values))

    private val en = Locale.forLanguageTag("en")

    @Test
    fun productionDataRetainsDateAlternativesAndSearchesAliases() {
        val library = productionLibrary()
        val prophet = assertNotNull(library.byID["prophet-muhammad"])
        val arabic = assertNotNull(prophet.displayNames["ar"])
        val english = assertNotNull(prophet.displayNames["en"])
        assertEquals(arabic, prophet.title(Locale.forLanguageTag("ar-SA")))
        assertEquals(english, prophet.title(Locale.forLanguageTag("fr-FR")))
        assertTrue(library.search("مُحَمَّد", Locale.forLanguageTag("ar")).any { it.id == prophet.id })
        assertEquals(prophet.id, library.search("MUHAMMAD", en).first().id)
        assertEquals(setOf(FigureClaimStatus.Accepted), prophet.birthDates.map { it.status }.toSet())
        assertTrue(library.events[prophet.id].orEmpty().any { it.id == "prophet-khadija-marriage" })
    }

    @Test
    fun searchIgnoresTatweelAndArabicMarks() {
        val library = productionLibrary()
        assertTrue(library.search("مـحـمّـد", Locale.forLanguageTag("ar")).any { it.id == "prophet-muhammad" })
        assertTrue(library.search("  abbas ", en).any { it.id == "abbas-ibn-ali" })
    }

    @Test
    fun productionDataUsesSimplifiedNames() {
        val prophet = assertNotNull(productionLibrary().byID["prophet-muhammad"])
        val ar = Locale.forLanguageTag("ar")
        assertEquals(listOf("محمد"), prophet.names(Figure.NameKind.Personal, ar))
        assertEquals(listOf("محمد بن عبد الله"), prophet.names(Figure.NameKind.Full, ar))
    }

    @Test
    fun exampleDerivesFullAndHalfSiblingsAndGroupsChildren() {
        val library = FigureLibrary(example, verifiedOnly = false)
        val id = "example-child-a"
        val claim = assertNotNull(library.parents[id]?.first())
        val siblings = library.siblings(id, claim)
        assertEquals(listOf("example-child-b"), siblings[SiblingDegree.Full]?.map { it.id })
        assertEquals(listOf("example-child-c"), siblings[SiblingDegree.Half]?.map { it.id })
        assertEquals(2, library.partners["example-father"]?.size)
        assertEquals(listOf(2, 1), library.childGroups("example-father").map { it.size })
    }

    @Test
    fun unknownParentAndConflictingAccountsStaySeparate() {
        var dataset = exampleObject()
        val parentages = dataset.list("parentages")
        parentages[2] = parentages[2].with("mother_id", JsonNull).without("union_id")
        dataset = dataset.with("parentages", parentages)
        val unknown = FigureLibrary(dataset.toString(), verifiedOnly = false)
        val first = assertNotNull(unknown.parents["example-child-a"]?.first())
        assertEquals(
            listOf("example-child-c"),
            unknown.siblings(first.childId, first)[SiblingDegree.Unknown]?.map { it.id },
        )

        parentages +=
            parentages[2]
                .with(
                    "id",
                    JsonPrimitive("alternate-parentage"),
                ).with("mother_id", JsonPrimitive("example-mother-a"))
        dataset = dataset.with("parentages", parentages)
        val conflict = FigureLibrary(dataset.toString(), verifiedOnly = false)
        assertEquals(2, conflict.childGroups("example-father").flatten().size)
        assertEquals(
            3,
            conflict.childGroups("example-father", mapOf("example-child-c" to "alternate-parentage")).flatten().size,
        )

        parentages[2] = parentages[2].with("father_id", JsonPrimitive("missing-person"))
        val invalid = dataset.with("parentages", parentages).toString()
        assertEquals(
            Failure.InvalidRelationships,
            assertFailsWith<FigureLibraryException> { FigureLibrary(invalid, verifiedOnly = false) }.failure,
        )
    }

    /** Swift `bundledStoreLoadsWithoutNetwork`, on the file the app bundles. */
    @Test
    fun bundledDatasetLoadsVerifiedPeople() {
        val library = productionLibrary()
        assertTrue(library.people.isNotEmpty())
        assertTrue(library.people.all { it.verified == true })
        assertEquals("Karbala", library.byID["abbas-ibn-ali"]?.deathPlace?.get("en"))
    }

    @Test
    fun unverifiedPeopleAndTheirRelationshipsAreExcluded() {
        assertTrue(FigureLibrary(example).people.isEmpty())
        val people = exampleObject().list("people").map { it.with("verified", JsonPrimitive(true)) }.toMutableList()
        people[0] = people[0].with("verified", JsonPrimitive(false))
        val excluded = people[0].getValue("id").jsonPrimitive.content
        val library = FigureLibrary(exampleObject().with("people", people).toString())
        assertNull(library.byID[excluded])
        assertTrue(
            library.parents.values
                .flatten()
                .all { it.childId != excluded && excluded !in it.parentIDs },
        )
        assertTrue(
            library.partners.values
                .flatten()
                .all { excluded !in it.partnerIds },
        )
    }

    @Test
    fun claimNotesAcceptLocalizedAndLegacyTextAndCitationsCanBeAbsent() {
        val base =
            """{"calendar":"hijri","era":"AH","precision":"exact","start":{"year":61,"month":1,"day":10},""" +
                """"original":"61 AH","status":"accepted","notes":NOTES}"""
        for (notes in listOf("""{"ar":"ملاحظة","en":"Note"}""", "\"Note\"")) {
            val date = FigureLibrary.json.decodeFromString<FigureDate>(base.replace("NOTES", notes))
            assertTrue(date.citations.isEmpty())
            assertEquals("Note", date.notes?.values?.get("en"))
        }
    }

    @Test
    fun namesAcceptCamelCaseFullNames() {
        val json =
            """{"id":"test","display_names":{},"names":{"ar":{"name":"أ","fullName":"أ ب","laqab":["ج"]}},""" +
                """"birth_dates":[],"death_dates":[]}"""
        val person = FigureLibrary.json.decodeFromString<Figure>(json)
        val ar = Locale.forLanguageTag("ar")
        assertEquals(listOf("أ ب"), person.names(Figure.NameKind.Full, ar))
        assertEquals(listOf("ج"), person.names(Figure.NameKind.Laqab, en))
    }

    @Test
    fun browserSectionsPreservePublishedFigureOrder() {
        val library = productionLibrary()
        val sections = library.browserSections("", en)
        assertEquals(
            listOf(
                "infallibles",
                "otherInfallibles",
                "messengers",
                "prophetRelatives",
                "companions",
                "otherCompanions",
            ),
            sections.map { it.id },
        )
        assertEquals(
            listOf(
                listOf(
                    "prophet-muhammad",
                    "ali-ibn-abi-talib",
                    "fatima-al-zahra",
                    "hasan-ibn-ali",
                    "husayn-ibn-ali",
                    "ali-zayn-al-abidin",
                    "muhammad-al-baqir",
                    "jafar-al-sadiq",
                    "musa-al-kadhim",
                    "muhammad-al-jawad",
                    "ali-al-hadi",
                    "hasan-al-askari",
                    "muhammad-al-mahdi",
                ),
                listOf("zaynab-bint-ali", "abbas-ibn-ali", "ali-al-akbar", "fatima-al-masuma"),
                listOf("prophet-ibrahim", "prophet-isa", "prophet-musa"),
                listOf(
                    "abd-al-muttalib",
                    "abdullah-ibn-abd-al-muttalib",
                    "amina-bint-wahb",
                    "abu-talib",
                    "khadija-bint-khuwaylid",
                    "hamza-ibn-abd-al-muttalib",
                    "umm-kulthum-bint-ali",
                    "umm-al-banin",
                    "ruqayya-bint-al-husayn",
                    "sukayna-bint-al-husayn",
                    "qasim-ibn-al-hasan",
                    "qasim-ibn-al-kadhim",
                    "muslim-ibn-aqil",
                ),
                listOf("salman-al-muhammadi", "abu-dharr-al-ghifari", "miqdad-ibn-al-aswad", "ammar-ibn-yasir"),
                listOf("hani-ibn-urwa", "jabir-ibn-abdullah"),
            ),
            sections.map { section -> section.figures.map { it.id } },
        )

        val results = library.browserSections("abbas ibn ali", en)
        assertEquals(listOf("otherInfallibles"), results.map { it.id })
        assertEquals(listOf("abbas-ibn-ali"), results.flatMap { it.figures }.map { it.id })
    }

    @Test
    fun datasetsWithoutBrowserGroupsUseOneSection() {
        val library = FigureLibrary(example, verifiedOnly = false)
        val sections = library.browserSections("", en)
        assertEquals(listOf("all"), sections.map { it.id })
        assertEquals(library.people.map { it.id }, sections.flatMap { it.figures }.map { it.id })
    }

    @Test
    fun invalidBrowserGroupsAreRejected() {
        val ids = FigureLibrary(example, verifiedOnly = false).people.map { it.id }

        fun group(
            id: String,
            figures: List<String>,
        ) = buildJsonObject {
            put("id", id)
            put("figure_ids", buildJsonArray { figures.forEach { add(JsonPrimitive(it)) } })
        }
        val problems =
            mapOf(
                "duplicate group" to listOf(group("group", ids), group("group", emptyList())),
                "duplicate figure" to listOf(group("group", ids + ids[0])),
                "unknown figure" to listOf(group("group", ids.drop(1) + "missing-figure")),
                "unassigned figure" to listOf(group("group", ids.drop(1))),
            )
        for ((problem, groups) in problems) {
            val invalid = exampleObject().with("browser_groups", groups).toString()
            assertEquals(
                Failure.InvalidBrowserGroups,
                assertFailsWith<FigureLibraryException>(problem) { FigureLibrary(invalid) }.failure,
                problem,
            )
        }
    }

    @Test
    fun unsupportedVersionsAreRejected() {
        val invalid = exampleObject().with("schema_version", JsonPrimitive(2)).toString()
        assertEquals(
            Failure.UnsupportedVersion,
            assertFailsWith<FigureLibraryException> { FigureLibrary(invalid) }.failure,
        )
    }

    @Test
    fun optionalPlacesDecodeAndLocalizeWithoutChangingLegacyRecords() {
        val people = exampleObject().list("people")
        people[0] =
            people[0]
                .with(
                    "birth_place",
                    buildJsonObject {
                        put("en", "Birthplace")
                        put("ar", "مكان الولادة")
                    },
                ).with("death_place", buildJsonObject { put("en", "Deathplace") })
        val library = FigureLibrary(exampleObject().with("people", people).toString(), verifiedOnly = false)
        val person = library.people.first()
        assertEquals("مكان الولادة", person.birthPlace?.let { Figure.localized(it, Locale.forLanguageTag("ar")) })
        assertEquals("Deathplace", person.deathPlace?.get("en"))
        assertNull(library.people.last().birthPlace)
    }

    @Test
    fun ageEstimatesRespectEraBoundariesAndMissingDates() {
        fun person(
            birth: String,
            death: String,
        ): Figure =
            FigureLibrary.json.decodeFromString(
                """{"id":"test","display_names":{},"names":{},"birth_dates":$birth,"death_dates":$death}""",
            )

        fun date(
            year: Int,
            month: Int? = null,
            day: Int? = null,
            era: String = "AH",
            calendar: String = "hijri",
        ): String {
            var point = "\"year\":$year"
            if (month != null) point += ",\"month\":$month"
            if (day != null) point += ",\"day\":$day"
            return """[{"calendar":"$calendar","era":"$era","precision":"approximate","start":{$point},""" +
                """"original":"estimate","status":"accepted"}]"""
        }
        assertEquals(FigureAge(35), person(date(26), date(61)).age)
        assertEquals(FigureAge(63), person(date(53, era = "BH"), date(11)).age)
        assertEquals(FigureAge(81), person(date(85, era = "BH"), date(4, era = "BH")).age)
        assertEquals(
            FigureAge(1),
            person(date(1, era = "BCE", calendar = "gregorian"), date(1, era = "CE", calendar = "gregorian")).age,
        )
        assertNull(person("[]", date(61)).age)
        assertNull(person(date(255), "[]").age)
        assertNull(person(date(61), date(26)).age)
        assertNull(person(date(26), date(680, era = "CE", calendar = "gregorian")).age)

        assertEquals(FigureAge(35), person(date(26, month = 12, day = 20), date(61)).age)
        assertEquals(FigureAge(1, 1), person(date(26, month = 12, day = 20), date(28, month = 1)).age)
        assertEquals(FigureAge(1, 0), person(date(26, month = 12, day = 20), date(28, month = 1, day = 19)).age)
        assertEquals(FigureAge(1, 1), person(date(26, month = 12, day = 20), date(28, month = 1, day = 20)).age)
        assertNull(person(date(26, month = 12), date(26, month = 11)).age)
        assertNull(person(date(26, month = 12, day = 20), date(26, month = 12, day = 19)).age)
    }
}

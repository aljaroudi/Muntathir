package com.aljaroudi.muntathir.core.figures

import com.aljaroudi.muntathir.core.calendar.IslamicEvent
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.text.Normalizer
import java.util.Locale

/** One person in `shared/figures/figures.json`. Port of Swift `Figure`. */
@Serializable
data class Figure(
    val id: String,
    val verified: Boolean? = null,
    @SerialName("display_names") val displayNames: Map<String, String>,
    val names: Map<String, Names>,
    @SerialName("birth_place") val birthPlace: Map<String, String>? = null,
    @SerialName("death_place") val deathPlace: Map<String, String>? = null,
    @SerialName("birth_dates") val birthDates: List<FigureDate>,
    @SerialName("death_dates") val deathDates: List<FigureDate>,
    val notes: Map<String, String>? = null,
) {
    enum class NameKind(
        val key: String,
    ) {
        Personal("name"),
        Full("full_name"),
        Surname("surname"),
        Kunya("kunya"),
        Laqab("laqab"),
        Nisba("nisba"),
        Nickname("nickname"),
        Title("title"),
    }

    /** Names of one language by kind; `name` and `full_name` (or `fullName`) are single strings, others arrays. */
    @Serializable(with = NamesSerializer::class)
    data class Names(
        val values: Map<String, List<String>>,
    ) {
        operator fun get(kind: NameKind): List<String> = values[kind.key].orEmpty()

        val aliases: List<String> get() = values.values.flatten()
    }

    /** Swift `age`: an estimate at the precision shared by the recorded dates. */
    val age: FigureAge?
        get() {
            val births = birthDates.filter { it.status == FigureClaimStatus.Accepted }
            val deaths = deathDates.filter { it.status == FigureClaimStatus.Accepted }
            for (birth in births.ifEmpty { birthDates }) {
                for (death in deaths.ifEmpty { deathDates }) {
                    if (birth.calendar != death.calendar) continue
                    val years = death.signedYear - birth.signedYear
                    if (years < 0) continue
                    val birthMonth = birth.start.month
                    val deathMonth = death.start.month
                    if (birthMonth == null || deathMonth == null) return FigureAge(years)
                    var months = years * 12 + deathMonth - birthMonth
                    val birthDay = birth.start.day
                    val deathDay = death.start.day
                    if (birthDay != null && deathDay != null && deathDay < birthDay) months -= 1
                    if (months < 0) continue
                    return FigureAge(months / 12, months % 12)
                }
            }
            return null
        }

    fun title(locale: Locale): String = localized(displayNames, locale) ?: id

    fun names(
        kind: NameKind,
        locale: Locale,
    ): List<String> =
        languageKeys(names, locale)
            .map {
                names[it]?.get(kind).orEmpty()
            }.firstOrNull { it.isNotEmpty() }
            .orEmpty()

    companion object {
        fun <T> localized(
            values: Map<String, T>,
            locale: Locale,
        ): T? = languageKeys(values, locale).firstNotNullOfOrNull { values[it] }

        /** Exact tag, language-script, language, `en`, `ar`, then every key in order. */
        private fun languageKeys(
            values: Map<String, *>,
            locale: Locale,
        ): Sequence<String> {
            val language =
                when (val code = locale.language) {
                    "" -> "en"
                    "in" -> "id"
                    "iw" -> "he"
                    else -> code
                }
            val exact = locale.toLanguageTag()
            val script = locale.script.takeIf { it.isNotEmpty() }?.let { "$language-$it" }
            return sequenceOf(exact) + listOfNotNull(script) + sequenceOf(language, "en", "ar") + values.keys.sorted()
        }
    }
}

/** Years and, when both dates have months, months. Swift `DateComponents(year:month:)`. */
data class FigureAge(
    val years: Int,
    val months: Int? = null,
)

/** Claim notes by language; a legacy plain string means English. Swift `FigureNotes`. */
@Serializable(with = FigureNotesSerializer::class)
data class FigureNotes(
    val values: Map<String, String>,
)

@Serializable
enum class FigureClaimStatus {
    @SerialName("accepted")
    Accepted,

    @SerialName("disputed")
    Disputed,

    @SerialName("unreviewed")
    Unreviewed,
}

@Serializable
data class FigureCitation(
    @SerialName("source_id") val sourceId: String,
    val locator: String,
    val quote: String? = null,
)

/** A birth or death claim. Equality ignores evidence (citations and notes), like Swift. */
@Serializable
class FigureDate(
    val calendar: CalendarKind,
    val era: Era,
    val precision: Precision,
    val start: Point,
    val end: Point? = null,
    val original: String,
    val status: FigureClaimStatus,
    val citations: List<FigureCitation> = emptyList(),
    val notes: FigureNotes? = null,
) {
    @Serializable
    enum class CalendarKind {
        @SerialName("gregorian")
        Gregorian,

        @SerialName("julian")
        Julian,

        @SerialName("hijri")
        Hijri,
    }

    @Serializable
    enum class Era {
        CE,
        BCE,
        AH,
        BH,
    }

    @Serializable
    enum class Precision {
        @SerialName("exact")
        Exact,

        @SerialName("approximate")
        Approximate,

        @SerialName("range")
        Range,
    }

    @Serializable
    data class Point(
        val year: Int,
        val month: Int? = null,
        val day: Int? = null,
    )

    /** The start year on one axis: there is no year zero, so 1 BH/BCE is 0. */
    internal val signedYear: Int get() = if (era == Era.BH || era == Era.BCE) 1 - start.year else start.year

    private val identity get() = listOf(calendar, era, precision, start, end, original, status)

    override fun equals(other: Any?): Boolean = other is FigureDate && identity == other.identity

    override fun hashCode(): Int = identity.hashCode()
}

/** One claim about a child's parent pair. Swift `FigureParentage`. */
@Serializable
data class FigureParentage(
    val id: String,
    @SerialName("child_id") val childId: String,
    @SerialName("father_id") val fatherId: String? = null,
    @SerialName("mother_id") val motherId: String? = null,
    @SerialName("union_id") val unionId: String? = null,
    val kind: Kind,
    val status: FigureClaimStatus,
    val citations: List<FigureCitation>,
    val notes: FigureNotes? = null,
) {
    @Serializable
    enum class Kind {
        @SerialName("biological")
        Biological,

        @SerialName("adoptive")
        Adoptive,

        @SerialName("foster")
        Foster,
    }

    val parentIDs: List<String> get() = listOfNotNull(fatherId, motherId)

    val isDefault: Boolean get() = kind == Kind.Biological && status == FigureClaimStatus.Accepted

    fun otherParent(id: String): String? = if (fatherId == id) motherId else fatherId
}

/** A marriage or reported partnership. Swift `FigureUnion`. */
@Serializable
data class FigureUnion(
    val id: String,
    @SerialName("partner_ids") val partnerIds: List<String>,
    val kind: Kind,
    val status: FigureClaimStatus,
    val citations: List<FigureCitation>,
    val notes: FigureNotes? = null,
) {
    @Serializable
    enum class Kind {
        @SerialName("marriage")
        Marriage,

        @SerialName("reported-partnership")
        ReportedPartnership,
    }
}

class FigureLibraryException(
    val failure: Failure,
) : Exception(failure.name) {
    enum class Failure { UnsupportedVersion, InvalidRelationships, InvalidBrowserGroups }
}

/**
 * The figures dataset, validated and limited to verified people (and the relationships among them).
 * Port of Swift `FigureLibrary`; throws [FigureLibraryException] or a [SerializationException].
 */
class FigureLibrary(
    text: String,
    events: List<IslamicEvent> = emptyList(),
    verifiedOnly: Boolean = true,
) {
    enum class SiblingDegree { Full, Half, Unknown }

    data class BrowserSection(
        val id: String,
        val figures: List<Figure>,
    )

    @Serializable
    private data class BrowserGroup(
        val id: String,
        @SerialName("figure_ids") val figureIds: List<String>,
    )

    @Serializable
    private data class Source(
        val id: String,
        val title: String,
        val author: String? = null,
        val edition: String? = null,
        val url: String? = null,
        val notes: String? = null,
    )

    @Serializable
    private data class Dataset(
        @SerialName("schema_version") val schemaVersion: Int,
        val people: List<Figure>,
        val parentages: List<FigureParentage>,
        val unions: List<FigureUnion>,
        val sources: List<Source>,
        @SerialName("browser_groups") val browserGroups: List<BrowserGroup>? = null,
    )

    val people: List<Figure>
    private val browserGroups: List<BrowserGroup>
    val byID: Map<String, Figure>
    val parents: Map<String, List<FigureParentage>>
    val children: Map<String, List<FigureParentage>>
    val partners: Map<String, List<FigureUnion>>
    val events: Map<String, List<IslamicEvent>>
    private val searchTerms: Map<String, List<String>>

    /** [searchTerms] folded for the last search's locale, so typing doesn't refold every name. */
    @Volatile private var foldedTerms: Pair<Locale, Map<String, List<String>>>? = null

    init {
        val dataset = json.decodeFromString<Dataset>(text)
        if (dataset.schemaVersion != 1) fail(FigureLibraryException.Failure.UnsupportedVersion)
        val ids = dataset.people.map { it.id }.toSet()
        val unionIDs = dataset.unions.map { it.id }.toSet()
        val valid =
            ids.size == dataset.people.size &&
                unionIDs.size == dataset.unions.size &&
                dataset.parentages
                    .map { it.id }
                    .toSet()
                    .size == dataset.parentages.size &&
                dataset.parentages.all { claim ->
                    claim.childId in ids &&
                        claim.parentIDs.isNotEmpty() &&
                        claim.childId !in claim.parentIDs &&
                        claim.parentIDs.all { it in ids } &&
                        (claim.unionId?.let { it in unionIDs } ?: true)
                } &&
                dataset.unions.all { union ->
                    union.partnerIds.size == 2 && union.partnerIds.toSet().size == 2 &&
                        union.partnerIds.all { it in ids }
                }
        if (!valid) fail(FigureLibraryException.Failure.InvalidRelationships)
        browserGroups =
            dataset.browserGroups?.also { groups ->
                val assigned = groups.flatMap { it.figureIds }
                if (groups.map { it.id }.toSet().size != groups.size ||
                    assigned.size != ids.size ||
                    assigned.toSet() != ids
                ) {
                    fail(FigureLibraryException.Failure.InvalidBrowserGroups)
                }
            } ?: listOf(BrowserGroup("all", dataset.people.map { it.id }))
        people = dataset.people.filter { !verifiedOnly || it.verified == true }
        val published = people.map { it.id }.toSet()
        val unions = dataset.unions.filter { union -> union.partnerIds.all { it in published } }
        val publishedUnions = unions.map { it.id }.toSet()
        val parentages =
            dataset.parentages.filter { claim ->
                claim.childId in published &&
                    claim.parentIDs.all { it in published } &&
                    (claim.unionId?.let { it in publishedUnions } ?: true)
            }
        byID = people.associateBy { it.id }
        parents = parentages.groupBy { it.childId }
        children =
            parentages
                .flatMap { claim -> claim.parentIDs.map { it to claim } }
                .groupBy({ it.first }, { it.second })
        partners =
            unions
                .flatMap { union -> union.partnerIds.map { it to union } }
                .groupBy({ it.first }, { it.second })
        this.events =
            events
                .sortedWith(compareBy<IslamicEvent>({ it.month }, { it.day }, { it.id }))
                .flatMap { event -> event.figureIDs.filter { it in published }.map { it to event } }
                .groupBy({ it.first }, { it.second })
        val citations =
            people.flatMap { person -> (person.birthDates + person.deathDates).flatMap { it.citations } } +
                parentages.flatMap { it.citations } +
                unions.flatMap { it.citations }
        val sourceIDs = dataset.sources.map { it.id }.toSet()
        if (!citations.all { it.sourceId in sourceIDs }) fail(FigureLibraryException.Failure.InvalidRelationships)
        searchTerms =
            people.associate { figure ->
                figure.id to figure.displayNames.values + figure.names.values.flatMap { it.aliases }
            }
    }

    /** The browser groups in published order, each with its figures matching [query]; empty groups are dropped. */
    fun browserSections(
        query: String,
        locale: Locale,
    ): List<BrowserSection> {
        val matches = search(query, locale).map { it.id }.toSet()
        return browserGroups.mapNotNull { group ->
            val figures = group.figureIds.filter { it in matches }.mapNotNull { byID[it] }
            if (figures.isEmpty()) null else BrowserSection(group.id, figures)
        }
    }

    /** Case- and diacritic-insensitive matches over display names and aliases; everyone for a blank query. */
    fun search(
        query: String,
        locale: Locale,
    ): List<Figure> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return people
        val needle = fold(trimmed, locale)
        val folded =
            foldedTerms?.takeIf { it.first == locale }?.second
                ?: searchTerms
                    .mapValues { (_, terms) -> terms.map { fold(it, locale) } }
                    .also { foldedTerms = locale to it }
        return people.filter { person -> folded[person.id].orEmpty().any { it.contains(needle) } }
    }

    /** Siblings by degree from the selected parentage [account]; only default claims count. */
    fun siblings(
        id: String,
        account: FigureParentage?,
    ): Map<SiblingDegree, List<Figure>> {
        if (account == null) return emptyMap()
        val candidates =
            account.parentIDs
                .flatMap { parent -> children[parent].orEmpty().filter { it.isDefault }.map { it.childId } }
                .toSet() - id
        val result = linkedMapOf<SiblingDegree, MutableList<Figure>>()
        for (candidate in people) {
            if (candidate.id !in candidates) continue
            val claims = parents[candidate.id].orEmpty().filter { it.isDefault }
            val other = claims.singleOrNull() ?: continue
            val shared = account.parentIDs.toSet() intersect other.parentIDs.toSet()
            if (shared.isEmpty()) continue
            val degree =
                when {
                    shared.size == 2 -> SiblingDegree.Full
                    account.parentIDs.size == 2 && other.parentIDs.size == 2 -> SiblingDegree.Half
                    else -> SiblingDegree.Unknown
                }
            result.getOrPut(degree) { mutableListOf() } += candidate
        }
        return result
    }

    /**
     * Default child claims grouped by the other parent, in claim order. A child with several default accounts
     * appears only under the one chosen in [choices] (child id → parentage id).
     */
    fun childGroups(
        id: String,
        choices: Map<String, String> = emptyMap(),
    ): List<List<FigureParentage>> {
        val claims =
            children[id].orEmpty().filter { claim ->
                if (!claim.isDefault) return@filter false
                val accounts = parents[claim.childId].orEmpty().filter { it.isDefault }
                accounts.size == 1 || choices[claim.childId] == claim.id
            }
        val groups = mutableListOf<MutableList<FigureParentage>>()
        for (claim in claims) {
            val group = groups.firstOrNull { it.first().otherParent(id) == claim.otherParent(id) }
            if (group != null) group += claim else groups += mutableListOf(claim)
        }
        return groups
    }

    companion object {
        internal val json = Json { ignoreUnknownKeys = true }

        private fun fail(failure: FigureLibraryException.Failure): Nothing = throw FigureLibraryException(failure)

        /** Tatweel stretches Arabic letters and carries no meaning for search. */
        private const val TATWEEL = 'ـ'
        private val marks = Regex("\\p{Mn}+")

        /** Foundation's `.caseInsensitive` + `.diacriticInsensitive`: NFD without combining marks, then lowercase. */
        private fun fold(
            text: String,
            locale: Locale,
        ): String =
            marks
                .replace(Normalizer.normalize(text, Normalizer.Form.NFD), "")
                .replace(TATWEEL.toString(), "")
                .lowercase(locale)
    }
}

private object NamesSerializer : KSerializer<Figure.Names> {
    private val delegate = MapSerializer(String.serializer(), JsonElement.serializer())
    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun deserialize(decoder: Decoder): Figure.Names {
        val input = decoder as? JsonDecoder ?: throw SerializationException("Names need JSON")
        val values = mutableMapOf<String, List<String>>()
        for ((key, element) in input.decodeJsonElement() as? JsonObject ?: throw SerializationException("Names")) {
            val name = if (key == "fullName") "full_name" else key
            values[name] =
                if (name == "name" || name == "full_name") {
                    listOf(element.string())
                } else {
                    (element as? JsonArray ?: throw SerializationException("$key must be an array")).map { it.string() }
                }
        }
        return Figure.Names(values)
    }

    private fun JsonElement.string(): String {
        val primitive = this as? JsonPrimitive
        if (primitive == null || !primitive.isString) throw SerializationException("Expected a string")
        return primitive.content
    }

    override fun serialize(
        encoder: Encoder,
        value: Figure.Names,
    ) = MapSerializer(String.serializer(), ListSerializer(String.serializer())).serialize(encoder, value.values)
}

private object FigureNotesSerializer : KSerializer<FigureNotes> {
    private val delegate = MapSerializer(String.serializer(), String.serializer())
    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun deserialize(decoder: Decoder): FigureNotes {
        val input = decoder as? JsonDecoder ?: throw SerializationException("Notes need JSON")
        val element = input.decodeJsonElement()
        if (element is JsonPrimitive && element.isString) return FigureNotes(mapOf("en" to element.content))
        return FigureNotes(input.json.decodeFromJsonElement(delegate, element))
    }

    override fun serialize(
        encoder: Encoder,
        value: FigureNotes,
    ) = delegate.serialize(encoder, value.values)
}

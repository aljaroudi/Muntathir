package com.aljaroudi.muntathir.ui.figures

import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.figures.Figure
import com.aljaroudi.muntathir.core.figures.FigureDate
import com.aljaroudi.muntathir.core.figures.FigureLibrary
import com.aljaroudi.muntathir.core.figures.FigureLibrary.SiblingDegree
import com.aljaroudi.muntathir.data.library
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.FigureProfileRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import java.util.Locale

@get:StringRes
internal val Figure.NameKind.label: Int
    get() =
        when (this) {
            Figure.NameKind.Personal -> R.string.personal_names
            Figure.NameKind.Full -> R.string.name
            Figure.NameKind.Surname -> R.string.surnames
            Figure.NameKind.Kunya -> R.string.kunyas
            Figure.NameKind.Laqab -> R.string.laqabs
            Figure.NameKind.Nisba -> R.string.nisbas
            Figure.NameKind.Nickname -> R.string.nicknames
            Figure.NameKind.Title -> R.string.titles
        }

@get:StringRes
internal val SiblingDegree.label: Int
    get() =
        when (this) {
            SiblingDegree.Full -> R.string.full_siblings
            SiblingDegree.Half -> R.string.half_siblings
            SiblingDegree.Unknown -> R.string.siblings
        }

private const val LAQABS_SHOWN = 3

/** Swift `FigureProfile` (detail pane): names, places, dates, age, notes, relatives and observances. */
@Composable
fun FigureProfileScreen(
    route: FigureProfileRoute,
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
    viewModel: FigureLibraryViewModel = hiltViewModel(),
) {
    val load by viewModel.library.collectAsStateWithLifecycle()
    val locale = currentLocale()
    val figure = load.library?.byID?.get(route.id)
    // Like iOS, the profile has no family tree for now (hard to read with several spouses).
    ScreenScaffold(figure?.title(locale) ?: stringResource(R.string.figures), onBack = onBack) { padding ->
        FigureGate(load, padding) { library ->
            if (figure == null) {
                FiguresUnavailable(padding)
                return@FigureGate
            }
            var laqabsExpanded by rememberSaveable(figure.id) { mutableStateOf(false) }
            LazyColumn(Modifier.fillMaxSize().testTag("figure-profile-${figure.id}"), contentPadding = padding) {
                profile(figure, library, locale, laqabsExpanded, { laqabsExpanded = !laqabsExpanded }) {
                    open(FigureProfileRoute(it))
                }
            }
        }
    }
}

private fun LazyListScope.profile(
    figure: Figure,
    library: FigureLibrary,
    locale: Locale,
    laqabsExpanded: Boolean,
    onToggleLaqabs: () -> Unit,
    onOpen: (String) -> Unit,
) {
    val id = figure.id
    for (kind in Figure.NameKind.entries) {
        if (kind == Figure.NameKind.Personal) continue
        val names = figure.names(kind, locale).distinct().sorted()
        if (names.isEmpty()) continue
        val hasMore = kind == Figure.NameKind.Laqab && names.size > LAQABS_SHOWN
        header("names-${kind.key}", kind.label)
        names.take(if (hasMore && !laqabsExpanded) LAQABS_SHOWN else names.size).forEach { name ->
            item(key = "names-${kind.key}-$name") { ListItem(headlineContent = { Text(name) }) }
        }
        if (hasMore) {
            item(key = "laqabs-toggle") {
                TextButton(onClick = onToggleLaqabs, modifier = Modifier.testTag("figure-laqabs-toggle")) {
                    Text(stringResource(if (laqabsExpanded) R.string.show_fewer_laqabs else R.string.show_more_laqabs))
                }
            }
        }
    }
    place("birth-place", R.string.place_of_birth, figure.birthPlace, locale)
    dates("birth-dates", R.string.birth_dates, figure.birthDates, locale)
    place("death-place", R.string.place_of_death, figure.deathPlace, locale)
    dates("death-dates", R.string.death_dates, figure.deathDates, locale)
    figure.age?.let { age ->
        item(key = "age") {
            ListItem(
                headlineContent = { Text(stringResource(R.string.estimated_age)) },
                trailingContent = { Text(formattedAge(age, locale), style = MaterialTheme.typography.bodyLarge) },
                modifier = Modifier.testTag("figure-age"),
            )
        }
    }
    figure.notes?.let { Figure.localized(it, locale) }?.let { notes ->
        header("notes", R.string.notes)
        item(key = "notes-text") { ListItem(headlineContent = { Text(notes) }) }
    }

    fun relative(
        key: String,
        relativeID: String?,
        @StringRes role: Int? = null,
    ) {
        val person = relativeID?.let { library.byID[it] } ?: return
        item(key = key) {
            ListItem(
                overlineContent = role?.let { label -> @Composable { Text(stringResource(label)) } },
                headlineContent = { Text(person.title(locale)) },
                modifier = Modifier.clickable { onOpen(person.id) }.testTag("figure-relative-${person.id}"),
            )
        }
    }

    val parents = library.parents[id].orEmpty()
    if (parents.isNotEmpty()) {
        header("parents", R.string.parents)
        parents.forEach { claim ->
            relative("parents-${claim.id}-father", claim.fatherId, R.string.father)
            relative("parents-${claim.id}-mother", claim.motherId, R.string.mother)
        }
    }
    val unions = library.partners[id].orEmpty()
    if (unions.isNotEmpty()) {
        header("spouses", R.string.spouses)
        unions.forEach { union -> relative("spouse-${union.id}", union.partnerIds.firstOrNull { it != id }) }
    }
    val primary = parents.filter { it.isDefault }
    val siblings = library.siblings(id, primary.singleOrNull())
    for (degree in SiblingDegree.entries) {
        val people = siblings[degree] ?: continue
        header("siblings-$degree", degree.label)
        people.forEach { relative("siblings-$degree-${it.id}", it.id) }
    }
    val groups = library.childGroups(id)
    groups.forEach { claims ->
        val first = claims.first()
        val other = first.otherParent(id)?.let { library.byID[it] }
        item(key = "children-${first.id}") {
            SectionHeader(
                if (other !=
                    null
                ) {
                    stringResource(R.string.children_with_x, other.title(locale))
                } else {
                    stringResource(R.string.children)
                },
            )
        }
        claims.forEach { relative("children-${first.id}-${it.id}", it.childId) }
    }
    val defaultClaims = groups.flatten().map { it.id }.toSet()
    val otherClaims = library.children[id].orEmpty().filter { it.id !in defaultClaims }
    if (otherClaims.isNotEmpty()) {
        header("other-parentages", R.string.other_parentage_reports)
        otherClaims.forEach { claim ->
            relative("other-${claim.id}-child", claim.childId)
            relative("other-${claim.id}-parent", claim.otherParent(id), R.string.other_parent)
        }
    }
    library.events[id]?.let { events ->
        header("observances", R.string.related_observances)
        events.forEach { event ->
            item(key = "observance-${event.id}") {
                ListItem(
                    headlineContent = { Text(event.title(locale)) },
                    supportingContent = { Text(hijriDay(event.day, event.month, locale)) },
                )
            }
        }
    }
}

private fun LazyListScope.header(
    key: String,
    @StringRes title: Int,
) = item(key = "header-$key") { SectionHeader(stringResource(title)) }

private fun LazyListScope.place(
    key: String,
    @StringRes title: Int,
    places: Map<String, String>?,
    locale: Locale,
) {
    val place = places?.let { Figure.localized(it, locale) } ?: return
    header(key, title)
    item(key = "$key-text") { ListItem(headlineContent = { Text(place) }) }
}

private fun LazyListScope.dates(
    key: String,
    @StringRes title: Int,
    dates: List<FigureDate>,
    locale: Locale,
) {
    if (dates.isEmpty()) return
    header(key, title)
    // Equal claims (ignoring evidence) are one row, like Swift's `ForEach(id: \.self)`.
    dates.distinct().forEachIndexed { index, date ->
        item(key = "$key-$index") { ListItem(headlineContent = { FigureDateText(date, locale) }) }
    }
}

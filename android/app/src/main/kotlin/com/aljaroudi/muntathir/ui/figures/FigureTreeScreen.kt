package com.aljaroudi.muntathir.ui.figures

import androidx.annotation.StringRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.figures.FigureClaimStatus
import com.aljaroudi.muntathir.core.figures.FigureLibrary
import com.aljaroudi.muntathir.core.figures.FigureLibrary.SiblingDegree
import com.aljaroudi.muntathir.core.figures.FigureParentage
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.FigureProfileRoute
import com.aljaroudi.muntathir.ui.navigation.FigureTreeRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import java.util.Locale

/** iOS accessibility text sizes start around this scale; the tree becomes one column without lines. */
private const val LARGE_FONT_SCALE = 1.5f

/**
 * Swift `FigureFamilyTree` (detail pane): parents above the focus, siblings and spouses beside it, children
 * below. Tapping a relative refocuses the tree; the bar opens the focused profile or returns to the original.
 */
@Composable
fun FigureTreeScreen(
    route: FigureTreeRoute,
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
    viewModel: FigureLibraryViewModel = hiltViewModel(),
) {
    val load by viewModel.library.collectAsStateWithLifecycle()
    var focus by rememberSaveable(route.id) { mutableStateOf(route.id) }
    // Child id → chosen parentage id, for children with several accepted accounts.
    var choices by rememberSaveable(route.id) { mutableStateOf(HashMap<String, String>()) }
    ScreenScaffold(R.string.family_tree, onBack = onBack) { padding ->
        FigureGate(load, padding) { library ->
            if (library.byID[route.id] == null) {
                FiguresUnavailable(padding)
                return@FigureGate
            }
            Column(Modifier.padding(padding).fillMaxSize()) {
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    FamilyTree(
                        library,
                        focus,
                        choices,
                        onChoose = { child, report -> choices = HashMap(choices).apply { put(child, report) } },
                        onFocus = { focus = it },
                    )
                }
                Surface(tonalElevation = 3.dp, modifier = Modifier.fillMaxWidth()) {
                    Column(
                        Modifier.padding(12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        FilledTonalButton(
                            onClick = { open(FigureProfileRoute(focus)) },
                            modifier = Modifier.testTag("family-view-profile"),
                        ) { Text(stringResource(R.string.view_profile)) }
                        if (focus != route.id) {
                            TextButton(
                                onClick = { focus = route.id },
                                modifier = Modifier.testTag("family-back-to-original"),
                            ) { Text(stringResource(R.string.back_to_original_figure)) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FamilyTree(
    library: FigureLibrary,
    id: String,
    choices: Map<String, String>,
    onChoose: (child: String, report: String) -> Unit,
    onFocus: (String) -> Unit,
) {
    val locale = currentLocale()
    val large = LocalDensity.current.fontScale >= LARGE_FONT_SCALE
    val accounts = library.parents[id].orEmpty().filter { it.isDefault }
    val account = accounts.singleOrNull() ?: accounts.firstOrNull { it.id == choices[id] }
    val siblings = library.siblings(id, account)
    val partners = library.partners[id].orEmpty().filter { it.status == FigureClaimStatus.Accepted }
    val children = library.childGroups(id, choices)

    // Node bounds in the tree's own coordinates, for the connectors drawn behind.
    val bounds = remember(id, choices) { mutableStateMapOf<String, Rect>() }
    val nodes = remember(id, choices) { mutableMapOf<String, LayoutCoordinates>() }
    val tree = remember(id, choices) { arrayOfNulls<LayoutCoordinates>(1) }

    fun measure(
        key: String,
        node: LayoutCoordinates,
    ) {
        val root = tree[0]?.takeIf { it.isAttached } ?: return
        if (!node.isAttached) return
        val rect = root.localBoundingBoxOf(node)
        if (bounds[key] != rect) bounds[key] = rect
    }
    val nodeModifier: (String) -> Modifier = { key ->
        Modifier.onGloballyPositioned {
            nodes[key] = it
            measure(key, it)
        }
    }
    val line = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
    val node: @Composable (String?, String, Int?) -> Unit = { personID, key, role ->
        TreeNode(library, personID, id, role, locale, nodeModifier(key), onFocus)
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val width = maxWidth
        val scroll = Modifier.verticalScroll(rememberScrollState())
        Box(if (large) scroll else scroll.horizontalScroll(rememberScrollState())) {
            Column(
                Modifier
                    .widthIn(min = width)
                    .onGloballyPositioned { coordinates ->
                        tree[0] = coordinates
                        nodes.forEach { (key, node) -> measure(key, node) }
                    }.drawBehind { if (!large) connectors(bounds, line) }
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                if (accounts.size > 1) ReportChooser(library, accounts, locale) { onChoose(id, it) }
                if (account != null) {
                    TreeGroup(R.string.parents, large) {
                        account.fatherId?.let { node(it, "father", R.string.father) }
                        account.motherId?.let { node(it, "mother", R.string.mother) }
                    }
                }
                Lane(large, spacing = if (large) 16 else 24) {
                    for (degree in SiblingDegree.entries) {
                        val relatives = siblings[degree] ?: continue
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Caption(stringResource(degree.label))
                            relatives.forEach { node(it.id, "sibling-${it.id}", null) }
                        }
                    }
                    node(id, "focus", null)
                    if (partners.isNotEmpty()) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Caption(stringResource(R.string.spouses))
                            partners.forEach { union ->
                                node(union.partnerIds.firstOrNull { it != id }, "partner-${union.id}", null)
                            }
                        }
                    }
                }
                children.forEach { claims ->
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        claims.first().otherParent(id)?.let { library.byID[it] }?.let { other ->
                            Caption(stringResource(R.string.children_with_x, other.title(locale)), secondary = true)
                        }
                        Lane(large, spacing = 8) {
                            claims.forEach { node(it.childId, "child-${it.id}", null) }
                        }
                    }
                }
            }
        }
    }
}

/** Swift's connectors: side lines to siblings and spouses, elbows up to parents and down to children. */
private fun DrawScope.connectors(
    bounds: Map<String, Rect>,
    color: Color,
) {
    val focus = bounds["focus"] ?: return
    val branch = 12.dp.toPx()
    val path = Path()
    for ((key, card) in bounds) {
        if (key == "focus") continue
        if (key.startsWith("sibling-") || key.startsWith("partner-")) {
            val onLeft = card.center.x < focus.center.x
            path.moveTo(if (onLeft) focus.left else focus.right, focus.center.y)
            path.lineTo(if (onLeft) card.right else card.left, card.center.y)
        } else {
            val above = card.center.y < focus.center.y
            val start = Offset(focus.center.x, if (above) focus.top else focus.bottom)
            val end = Offset(card.center.x, if (above) card.bottom else card.top)
            val branchY = if (above) start.y - branch else start.y + branch
            path.moveTo(start.x, start.y)
            path.lineTo(start.x, branchY)
            path.lineTo(end.x, branchY)
            path.lineTo(end.x, end.y)
        }
    }
    drawPath(path, color, style = Stroke(1.dp.toPx()))
}

/** A row of nodes, or a column at large text sizes. */
@Composable
private fun Lane(
    large: Boolean,
    spacing: Int,
    content: @Composable () -> Unit,
) {
    if (large) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(spacing.dp),
        ) { content() }
    } else {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(spacing.dp),
        ) { content() }
    }
}

@Composable
private fun TreeGroup(
    @StringRes label: Int,
    large: Boolean,
    content: @Composable () -> Unit,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Caption(stringResource(label))
        Lane(large, spacing = 8, content)
    }
}

@Composable
private fun Caption(
    text: String,
    secondary: Boolean = false,
) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = if (secondary) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun TreeNode(
    library: FigureLibrary,
    personID: String?,
    focusID: String,
    @StringRes role: Int?,
    locale: Locale,
    modifier: Modifier,
    onFocus: (String) -> Unit,
) {
    val person = personID?.let { library.byID[it] }
    val isFocus = personID == focusID
    val shape = RoundedCornerShape(12.dp)
    val colors = MaterialTheme.colorScheme
    val border = BorderStroke(1.dp, if (isFocus) colors.primary else colors.outlineVariant)
    val action =
        if (person != null && !isFocus) {
            Modifier.clickable(role = Role.Button) { onFocus(person.id) }.testTag("family-node-${person.id}")
        } else {
            Modifier
        }
    Column(
        modifier
            .widthIn(max = 200.dp)
            .heightIn(min = 48.dp)
            .background(colors.surface, shape)
            .border(border, shape)
            .then(action)
            .padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
    ) {
        role?.let { Caption(stringResource(it), secondary = true) }
        if (person != null) {
            if (isFocus) {
                Text(
                    person.title(locale),
                    style = MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.semantics { heading() },
                )
            } else {
                Text(
                    person.title(locale),
                    style = MaterialTheme.typography.bodyLarge,
                    color = colors.primary,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/** Swift's "Choose a parentage report" menu, one entry per accepted account ("Father / Mother"). */
@Composable
private fun ReportChooser(
    library: FigureLibrary,
    accounts: List<FigureParentage>,
    locale: Locale,
    onChoose: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(onClick = { expanded = true }, Modifier.testTag("family-choose-report")) {
            Text(stringResource(R.string.choose_a_parentage_report))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            accounts.forEach { report ->
                val label = report.parentIDs.mapNotNull { library.byID[it]?.title(locale) }.joinToString(" / ")
                DropdownMenuItem(
                    text = { Text(label) },
                    onClick = {
                        expanded = false
                        onChoose(report.id)
                    },
                )
            }
        }
    }
}

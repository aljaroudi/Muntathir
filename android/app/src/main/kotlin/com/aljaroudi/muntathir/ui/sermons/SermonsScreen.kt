package com.aljaroudi.muntathir.ui.sermons

import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.res.ResourcesCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.sqlite.SQLiteException
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.figures.Figure
import com.aljaroudi.muntathir.core.highlight.HighlightRange
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.SearchMatch
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.data.BundledContentSql
import com.aljaroudi.muntathir.data.FigureLoad
import com.aljaroudi.muntathir.data.FigureStore
import com.aljaroudi.muntathir.data.library
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SearchField
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.FigureProfileRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import com.aljaroudi.muntathir.ui.navigation.SermonRoute
import com.aljaroudi.muntathir.ui.quran.ReadingOptionsMenu
import com.aljaroudi.muntathir.ui.quran.ReadingSizeSheet
import com.aljaroudi.muntathir.ui.reader.HighlightDraft
import com.aljaroudi.muntathir.ui.reader.HighlightTextView
import com.aljaroudi.muntathir.ui.reader.ReaderDialogs
import com.aljaroudi.muntathir.ui.reader.ReadingTextStyle
import com.aljaroudi.muntathir.ui.reader.applyReadingStyle
import com.aljaroudi.muntathir.ui.reader.readingDisplay
import com.aljaroudi.muntathir.ui.reader.toAnnotatedString
import com.aljaroudi.muntathir.ui.settings.ReadingSettingsViewModel
import com.aljaroudi.muntathir.ui.theme.HadithFont
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.util.Locale
import javax.inject.Inject

private data class Sermon(
    val id: String,
    val title: String,
    val speakerId: String,
    val segments: List<Segment>,
    val editions: List<Edition>,
)

private data class Segment(
    val id: String,
    val section: String,
    val kind: String,
    val text: String,
)

private data class Edition(
    val id: String,
    val language: String,
    val kind: String,
    val credit: String? = null,
    val aligned: Map<String, String>,
)

private fun loadSermons(context: Context): List<Sermon> {
    val file = File(context.cacheDir, "sermons.db")
    val installed = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime
    if (!file.isFile || file.lastModified() < installed) {
        val temp = File.createTempFile("sermons-", ".db", context.cacheDir)
        try {
            context.assets.open("sermons/sermons.db").use { input -> temp.outputStream().use(input::copyTo) }
            if (!temp.renameTo(file)) throw IOException("Could not install sermon database")
        } finally {
            temp.delete()
        }
    }
    return BundledContentSql.Driver.open(file, writable = false).use { db ->
        db.query("SELECT id, title, speaker_id FROM sermon ORDER BY id", emptyList()) { row ->
            val id = row.text(0)
            val segments =
                db.query("SELECT id, section, kind, text FROM segment WHERE sermon = ? ORDER BY position", listOf(id)) {
                    Segment(it.text(0), it.text(1), it.text(2), it.text(3))
                }
            val editions =
                db.query(
                    "SELECT id, language, kind, credit FROM edition WHERE sermon = ? ORDER BY position",
                    listOf(id),
                ) { item ->
                    val key = item.text(0)
                    val aligned =
                        db
                            .query(
                                "SELECT segment, text FROM translation WHERE sermon = ? AND edition = ?",
                                listOf(id, key),
                            ) {
                                it.text(0) to it.text(1)
                            }.toMap()
                    Edition(key, item.text(1), item.text(2), item.textOrNull(3), aligned)
                }
            Sermon(id, row.text(1), row.text(2), segments, editions)
        }
    }
}

private fun nativeName(language: String): String {
    if (language == "zh-CN") return "简体中文"
    val locale = Locale.forLanguageTag(language)
    return locale.getDisplayName(locale)
}

@Composable
private fun Edition.label(): String =
    when (kind) {
        "literal" -> stringResource(R.string.literal)
        "simplified" -> stringResource(R.string.simplified)
        else -> credit.orEmpty()
    }

/** The figure library, for resolving each sermon's speaker. */
@HiltViewModel
class SermonFiguresViewModel
    @Inject
    constructor(
        store: FigureStore,
        val user: QuranUserStore,
    ) : ViewModel() {
        val library: StateFlow<FigureLoad> = store.state
    }

@Composable
fun SermonsScreen(
    id: String? = null,
    onBack: (() -> Unit)?,
    onOpen: (String) -> Unit = {},
    open: (Route) -> Unit = {},
    settings: ReadingSettingsViewModel = hiltViewModel(),
    figures: SermonFiguresViewModel = hiltViewModel(),
    destination: SermonRoute? = null,
) {
    val context = LocalContext.current.applicationContext
    val sermons by produceState<List<Sermon>?>(null, context) {
        value =
            withContext(Dispatchers.IO) {
                try {
                    loadSermons(context)
                } catch (_: IOException) {
                    emptyList()
                } catch (_: SQLiteException) {
                    emptyList()
                }
            }
    }
    val reading by settings.state.collectAsStateWithLifecycle()
    val library =
        figures.library
            .collectAsStateWithLifecycle()
            .value.library
    val sermon = sermons?.firstOrNull { it.id == id }
    var selection by rememberSaveable(destination) { mutableStateOf(destination?.edition) }
    var collectionQuery by rememberSaveable { mutableStateOf("") }
    var saved by rememberSaveable { mutableStateOf(false) }
    var finding by rememberSaveable { mutableStateOf(false) }
    var readerQuery by rememberSaveable(destination) { mutableStateOf(destination?.query.orEmpty()) }
    val highlights by figures.user.highlights.collectAsStateWithLifecycle()
    var editing by remember { mutableStateOf<HighlightDraft?>(null) }
    var overlapping by remember { mutableStateOf(emptyList<ReadingHighlight>()) }
    var showEditions by rememberSaveable(id) { mutableStateOf(false) }
    var sizing by rememberSaveable { mutableStateOf(false) }
    BackHandler(enabled = saved) { saved = false }
    val edition = sermon?.editions?.firstOrNull { it.id == selection }
    ScreenScaffold(sermon?.title ?: stringResource(if (saved) R.string.saved else R.string.sermons),
        onBack = if (saved) ({ saved = false }) else onBack, actions = {
        if (sermon != null) {
            IconButton(modifier = Modifier.testTag("sermon-edition"), onClick = { showEditions = true }) {
                val label = edition?.let { nativeName(it.language) + " · " + it.label() } ?: "العربية"
                Icon(Icons.Outlined.Translate, stringResource(R.string.translations) + " · " + label)
            }
            TextButton(onClick = {
                finding = !finding
                if (!finding) readerQuery = ""
            }) { Text(stringResource(R.string.find_in_sermon)) }
            ReadingOptionsMenu(onTextSize = { sizing = true })
        }
    }) { padding ->
        val modifier = Modifier.fillMaxSize().padding(padding)
        when {
            sermons == null -> {
                Box(modifier, contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            }

            sermons.isNullOrEmpty() || (id != null && sermon == null) -> {
                Text(stringResource(R.string.sermons_unavailable), modifier.padding(16.dp))
            }

            sermon != null -> {
                Reader(
                    sermon,
                    library?.byID?.get(sermon.speakerId),
                    modifier,
                    edition,
                    reading.readingSizePercent,
                    open,
                    destination?.segment,
                    destination?.highlight,
                    readerQuery,
                    finding,
                    { readerQuery = it },
                    highlights,
                    { editing = HighlightDraft(listOf(it), existing = false) },
                    { hits ->
                        if (hits.size == 1) editing = HighlightDraft(hits, existing = true)
                        else overlapping = hits
                    },
                )
                if (showEditions) EditionsDialog(sermon, edition, { showEditions = false }, { selection = it })
            }

            else -> {
                val terms = remember(collectionQuery) { QuranSearchText.queryTerms(collectionQuery) }
                val results = remember(sermons, terms) {
                    if (terms.isEmpty()) emptyList()
                    else sermons.orEmpty().flatMap { sermon ->
                        sermon.matches(terms, sermon.editions)
                            .distinctBy { it.segment to it.block }
                            .map { sermon to it }
                    }
                }
                LazyColumn(modifier) {
                    if (saved) {
                        items(highlights.filter { it.source.startsWith("sermon/") }, key = { it.id }) { highlight ->
                            val parts = highlight.source.split('/')
                            if (parts.size == 3) {
                                ListItem(
                                    headlineContent = { Text(highlight.excerpt) },
                                    supportingContent = { Text(highlight.note.ifBlank { highlight.reference }) },
                                    trailingContent = {
                                        TextButton(onClick = { editing = HighlightDraft(listOf(highlight), existing = true) }) {
                                            Text(stringResource(R.string.edit_highlight))
                                        }
                                    },
                                    modifier = Modifier.clickable {
                                        open(SermonRoute(parts[1], parts[2], highlight.block.takeUnless { it == "arabic" }, highlight = highlight.id))
                                    },
                                )
                            }
                        }
                    } else {
                        item {
                            SearchField(
                                query = collectionQuery,
                                onQuery = { collectionQuery = it },
                                onSubmit = {},
                                placeholder = stringResource(R.string.search_sermons),
                            )
                        }
                        item {
                            ListItem(headlineContent = { Text(stringResource(R.string.saved)) },
                                modifier = Modifier.clickable { saved = true })
                        }
                        items(sermons.orEmpty().filter { terms.isEmpty() || SearchMatch.ranges(it.title, terms).isNotEmpty() }, key = { it.id }) {
                            val speaker = library?.byID?.get(it.speakerId)
                            ListItem(
                                headlineContent = { Text(it.title) },
                                supportingContent = speaker?.let { figure -> { Text(figure.title(currentLocale())) } },
                                modifier = Modifier.clickable { onOpen(it.id) },
                            )
                        }
                        if (terms.isNotEmpty() && results.isEmpty() && sermons.orEmpty().none { SearchMatch.ranges(it.title, terms).isNotEmpty() }) {
                            item { Text(stringResource(R.string.no_results), Modifier.padding(16.dp)) }
                        }
                        items(results, key = { (sermon, match) -> "${sermon.id}/${match.segment}/${match.block}" }) { (sermon, match) ->
                            val translation = sermon.editions.firstOrNull { it.id == match.block }
                            ListItem(
                                headlineContent = { Text(sermon.title + " · " + (translation?.let { nativeName(it.language) + " · " + it.label() } ?: "العربية")) },
                                supportingContent = { Text(SearchMatch.preview(SearchMatch.text(match.text, collectionQuery), compact = true).toAnnotatedString()) },
                                modifier = Modifier.clickable { open(SermonRoute(sermon.id, match.segment, translation?.id, collectionQuery)) },
                            )
                        }
                    }
                }
            }
        }
    }
    ReaderDialogs(
        editing = editing,
        choosing = overlapping,
        bookmarkFailed = false,
        colors = reading.highlightColors,
        onSave = figures.user::save,
        onDelete = figures.user::delete,
        onEdit = {
            overlapping = emptyList()
            editing = HighlightDraft(listOf(it), existing = true)
        },
        onClose = {
            overlapping = emptyList()
            editing = null
        },
        onDismissBookmarkFailure = {},
    )
    if (sizing) {
        ReadingSizeSheet(reading.readingSizePercent, currentLocale(), { percent ->
            settings.update {
                it.copy(readingSizePercent = percent)
            }
        }) {
            sizing =
                false
        }
    }
}

private data class SermonMatch(val segment: String, val block: String, val text: String, val range: TextRange)

private fun Sermon.matches(terms: List<String>, editions: List<Edition>): List<SermonMatch> =
    if (terms.isEmpty()) emptyList() else segments.flatMap { segment ->
        val blocks = listOf("arabic" to segment.text) + editions.mapNotNull { edition ->
            edition.aligned[segment.id]?.let { edition.id to it }
        }
        blocks.flatMap { (block, text) ->
            SearchMatch.ranges(text, terms).distinct().sortedBy { it.location }.map {
                SermonMatch(segment.id, block, text, it)
            }
        }
    }

/** Swift `SermonReader`: a centered header, then each Arabic passage with its translation set apart by an accent bar. */
@Composable
private fun Reader(
    sermon: Sermon,
    speaker: Figure?,
    modifier: Modifier,
    edition: Edition?,
    percent: Int,
    open: (Route) -> Unit,
    initialSegment: String?,
    focusedHighlight: String?,
    query: String,
    finding: Boolean,
    onQuery: (String) -> Unit,
    highlights: List<ReadingHighlight>,
    create: (ReadingHighlight) -> Unit,
    edit: (List<ReadingHighlight>) -> Unit,
) {
    val matches = remember(sermon, edition, query) {
        sermon.matches(QuranSearchText.queryTerms(query), listOfNotNull(edition))
    }
    val listState = rememberLazyListState()
    var matchIndex by remember(query, edition) { mutableStateOf(0) }
    val active = matches.getOrNull(matchIndex).takeIf { finding }
    LaunchedEffect(initialSegment, sermon) {
        val index = sermon.segments.indexOfFirst { it.id == initialSegment }
        if (index >= 0) listState.scrollToItem(index + 1)
    }
    LaunchedEffect(active) {
        val target = active?.segment
        val index = sermon.segments.indexOfFirst { it.id == target }
        if (index >= 0) listState.scrollToItem(index + 1)
    }
    val arabicSize = ReadingTextStyle.arabicSize(percent)
    val headingSize = arabicSize * 1.3f
    val heading = TextStyle(
        fontFamily = HadithFont,
        fontSize = headingSize.sp,
        lineHeight = (headingSize * 1.5f).sp,
    )
    val bodySize = ReadingTextStyle.bodySize(percent)
    val accent = MaterialTheme.colorScheme.primary
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        if (finding) {
            SearchField(query, onQuery, onSubmit = {}, placeholder = stringResource(R.string.find_in_sermon))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (matches.isEmpty()) "0" else "${matchIndex + 1} / ${matches.size}")
                TextButton(enabled = matches.isNotEmpty(), onClick = { matchIndex = (matchIndex + matches.size - 1) % matches.size }) {
                    Text(stringResource(R.string.previous_sermon_match))
                }
                TextButton(enabled = matches.isNotEmpty(), onClick = { matchIndex = (matchIndex + 1) % matches.size }) {
                    Text(stringResource(R.string.next_sermon_match))
                }
            }
        }
        LazyColumn(
            state = listState,
            modifier = Modifier.widthIn(max = 640.dp).fillMaxWidth().testTag("sermon-passages"),
            contentPadding = PaddingValues(20.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            item(key = "header") { Header(sermon, speaker, heading, accent, open) }
            items(sermon.segments, key = { it.id }) { segment ->
                val source = "sermon/${sermon.id}/${segment.id}"
                val saved = highlights.filter { it.source == source }
                Column(modifier = Modifier.testTag(segment.id), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    val isHeading = segment.kind == "heading"
                    Passage(
                        text = segment.text,
                        language = "ar",
                        sizeSp = if (isHeading) headingSize else arabicSize,
                        source = source,
                        block = "arabic",
                        reference = sermon.title,
                        query = query,
                        highlights = saved,
                        create = create,
                        edit = edit,
                        modifier = if (isHeading) Modifier.padding(top = 12.dp).semantics { heading() } else Modifier,
                        color = when (segment.kind) {
                            "heading" -> accent
                            "note" -> MaterialTheme.colorScheme.onSurfaceVariant
                            else -> Color.Unspecified
                        },
                        centered = isHeading,
                        active = active?.takeIf { it.segment == segment.id && it.block == "arabic" }?.range,
                        focusedHighlight = focusedHighlight,
                    )
                    edition?.let { selected ->
                        selected.aligned[segment.id]?.let {
                            Passage(
                                text = it,
                                language = selected.language,
                                sizeSp = bodySize,
                                source = source,
                                block = selected.id,
                                reference = sermon.title,
                                query = query,
                                highlights = saved,
                                create = create,
                                edit = edit,
                                focusedHighlight = focusedHighlight,
                                active = active?.takeIf { it.segment == segment.id && it.block == selected.id }?.range,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                bar = accent.copy(alpha = 0.35f),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Header(
    sermon: Sermon,
    speaker: Figure?,
    style: TextStyle,
    accent: Color,
    open: (Route) -> Unit,
) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Column(
            Modifier.fillMaxWidth().padding(vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(sermon.title, Modifier.semantics { heading() }, style = style, textAlign = TextAlign.Center)
            speaker?.let { figure ->
                Text(
                    figure.title(currentLocale()),
                    Modifier
                        .clickable(role = Role.Button) { open(FigureProfileRoute(figure.id)) }
                        .testTag("sermon-speaker"),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    textAlign = TextAlign.Center,
                )
            }
            Box(
                Modifier
                    .padding(
                        top = 6.dp,
                    ).size(width = 44.dp, height = 3.dp)
                    .background(accent.copy(alpha = 0.5f), CircleShape),
            )
        }
    }
}

@Composable
private fun EditionsDialog(
    sermon: Sermon,
    edition: Edition?,
    dismiss: () -> Unit,
    select: (String?) -> Unit,
) {
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(stringResource(R.string.translations)) },
        text = {
            LazyColumn(Modifier.testTag("sermon-editions")) {
                item {
                    EditionRow("العربية", edition == null, Modifier.testTag("edition-arabic")) {
                        select(null)
                        dismiss()
                    }
                }
                sermon.editions.groupBy { it.language }.toSortedMap().forEach { (language, editions) ->
                    item {
                        Text(
                            nativeName(language),
                            Modifier.padding(top = 16.dp, bottom = 4.dp),
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    items(editions, key = { it.id }) { choice ->
                        EditionRow(choice.label(), choice.id == edition?.id, Modifier.testTag("edition-${choice.id}")) {
                            select(choice.id)
                            dismiss()
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = dismiss) { Text(stringResource(android.R.string.cancel)) }
        },
    )
}

@Composable
private fun EditionRow(
    label: String,
    selected: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(label) },
        leadingContent = { RadioButton(selected = selected, onClick = null) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = modifier.selectable(selected = selected, role = Role.RadioButton, onClick = onClick),
    )
}

/** Lays out text in its own direction; [bar] draws a start-side accent bar that sets translations apart from the Arabic. */
@Composable
private fun Passage(
    text: String,
    language: String,
    sizeSp: Float,
    source: String,
    block: String,
    reference: String,
    query: String,
    highlights: List<ReadingHighlight>,
    create: (ReadingHighlight) -> Unit,
    edit: (List<ReadingHighlight>) -> Unit,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    centered: Boolean = false,
    bar: Color? = null,
    active: TextRange? = null,
    focusedHighlight: String? = null,
) {
    val rtl = TextUtils.getLayoutDirectionFromLocale(Locale.forLanguageTag(language)) == View.LAYOUT_DIRECTION_RTL
    CompositionLocalProvider(LocalLayoutDirection provides if (rtl) LayoutDirection.Rtl else LayoutDirection.Ltr) {
        Box(modifier.fillMaxWidth().drawBehind {
            if (bar != null) {
                val x = if (rtl) size.width - 1.dp.toPx() else 1.dp.toPx()
                drawLine(bar, Offset(x, 0f), Offset(x, size.height), 2.dp.toPx(), StrokeCap.Round)
            }
        }.padding(start = if (bar != null) 14.dp else 0.dp)) {
            val styled = remember(text, query) { SearchMatch.text(text, query) }
            val display = styled.readingDisplay()
            val foreground = if (color == Color.Unspecified) MaterialTheme.colorScheme.onSurface else color
            val focus = highlights.firstOrNull { it.id == focusedHighlight }?.ranges(text, block).orEmpty()
            val activeColor = MaterialTheme.colorScheme.secondaryContainer.toArgb()
            AndroidView(
                factory = { HighlightTextView(it) },
                modifier = Modifier.fillMaxWidth(),
                update = { view ->
                    view.applyReadingStyle(sizeSp, if (language == "ar") ResourcesCompat.getFont(view.context, R.font.lateef_regular) else null)
                    view.gravity = if (centered) Gravity.CENTER_HORIZONTAL else Gravity.START
                    view.textDirection = if (rtl) View.TEXT_DIRECTION_RTL else View.TEXT_DIRECTION_LTR
                    view.setTextColor(foreground.toArgb())
                    view.onOpenHighlights = edit
                    view.onHighlight = { selected ->
                        val ranges = selected.mapNotNull { HighlightRange.of(display?.sourceRange(it) ?: it, text) }
                        if (ranges.isNotEmpty()) {
                            create(ReadingHighlight(source, true, block, ranges, ranges.joinToString(" … ") { it.quote }, reference))
                        }
                    }
                    view.render(display?.text ?: styled, highlights, block, layoutKey = Triple(sizeSp, active, focus),
                        rangesOf = { highlight ->
                            highlight.ranges(text, block).map { display?.displayRange(it) ?: it }
                        }, decorate = { text ->
                            for (match in focus + listOfNotNull(active)) {
                                val range = display?.displayRange(match) ?: match
                                text.setSpan(android.text.style.UnderlineSpan(), range.location, range.end, 0)
                                if (match == active) {
                                    text.setSpan(android.text.style.BackgroundColorSpan(activeColor), range.location, range.end, 0)
                                }
                            }
                        })
                },
            )
        }
    }
}

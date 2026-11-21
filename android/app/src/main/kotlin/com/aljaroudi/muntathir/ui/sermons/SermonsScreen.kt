package com.aljaroudi.muntathir.ui.sermons

import android.content.Context
import android.text.TextUtils
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
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
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.sqlite.SQLiteException
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.figures.Figure
import com.aljaroudi.muntathir.data.BundledContentSql
import com.aljaroudi.muntathir.data.FigureLoad
import com.aljaroudi.muntathir.data.FigureStore
import com.aljaroudi.muntathir.data.library
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.FigureProfileRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import com.aljaroudi.muntathir.ui.quran.ReadingOptionsMenu
import com.aljaroudi.muntathir.ui.quran.ReadingSizeSheet
import com.aljaroudi.muntathir.ui.reader.ReadingTextStyle
import com.aljaroudi.muntathir.ui.reader.readingDisplay
import com.aljaroudi.muntathir.ui.settings.ReadingSettingsViewModel
import com.aljaroudi.muntathir.ui.theme.HadithFont
import com.aljaroudi.muntathir.ui.theme.ReaderBodyFont
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
    val library = figures.library.collectAsStateWithLifecycle().value.library
    val sermon = sermons?.firstOrNull { it.id == id }
    var selection by rememberSaveable(id) { mutableStateOf<String?>(null) }
    var showEditions by rememberSaveable(id) { mutableStateOf(false) }
    var sizing by rememberSaveable { mutableStateOf(false) }
    val edition = sermon?.editions?.firstOrNull { it.id == selection }
    ScreenScaffold(sermon?.title ?: stringResource(R.string.sermons), onBack = onBack, actions = {
        if (sermon != null) {
            IconButton(modifier = Modifier.testTag("sermon-edition"), onClick = { showEditions = true }) {
                val label = edition?.let { nativeName(it.language) + " · " + it.label() } ?: "العربية"
                Icon(Icons.Outlined.Translate, stringResource(R.string.translations) + " · " + label)
            }
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
                Reader(sermon, library?.byID?.get(sermon.speakerId), modifier, edition, reading.readingSizePercent, open)
                if (showEditions) EditionsDialog(sermon, edition, { showEditions = false }, { selection = it })
            }

            else -> {
                LazyColumn(modifier) {
                    items(sermons.orEmpty(), key = { it.id }) {
                        val speaker = library?.byID?.get(it.speakerId)
                        ListItem(
                            headlineContent = { Text(it.title) },
                            supportingContent = speaker?.let { figure -> { Text(figure.title(currentLocale())) } },
                            modifier = Modifier.clickable { onOpen(it.id) },
                        )
                    }
                }
            }
        }
    }
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

/** Swift `SermonReader`: a centered header, then each Arabic passage with its translation set apart by an accent bar. */
@Composable
private fun Reader(
    sermon: Sermon,
    speaker: Figure?,
    modifier: Modifier,
    edition: Edition?,
    percent: Int,
    open: (Route) -> Unit,
) {
    val arabicSize = ReadingTextStyle.arabicSize(percent)
    val arabic =
        TextStyle(
            fontFamily = HadithFont,
            fontSize = arabicSize.sp,
            lineHeight =
                (
                    arabicSize *
                        ReadingTextStyle.LINE_HEIGHT
                ).sp,
        )
    val heading = arabic.copy(fontSize = (arabicSize * 1.3f).sp, lineHeight = (arabicSize * 1.3f * 1.5f).sp)
    val bodySize = ReadingTextStyle.bodySize(percent)
    val body =
        TextStyle(
            fontFamily = ReaderBodyFont,
            fontSize = bodySize.sp,
            lineHeight =
                (
                    bodySize *
                        ReadingTextStyle.LINE_HEIGHT
                ).sp,
        )
    val accent = MaterialTheme.colorScheme.primary
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        SelectionContainer {
            LazyColumn(
                modifier = Modifier.widthIn(max = 640.dp).fillMaxWidth().testTag("sermon-passages"),
                contentPadding = PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(28.dp),
            ) {
                item(key = "header") { Header(sermon, speaker, heading, accent, open) }
                items(sermon.segments, key = { it.id }) { segment ->
                    Column(modifier = Modifier.testTag(segment.id), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        if (segment.kind == "heading") {
                            Passage(
                                segment.text.readingDisplay(),
                                "ar",
                                heading,
                                Modifier.padding(top = 12.dp).semantics { heading() },
                                color = accent,
                                centered = true,
                            )
                        } else {
                            Passage(
                                segment.text.readingDisplay(),
                                "ar",
                                arabic,
                                color =
                                    if (segment.kind ==
                                        "note"
                                    ) {
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    } else {
                                        Color.Unspecified
                                    },
                            )
                        }
                        edition?.let { selected ->
                            selected.aligned[segment.id]?.let {
                                Passage(
                                    it,
                                    selected.language,
                                    body,
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
    style: TextStyle,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    centered: Boolean = false,
    bar: Color? = null,
) {
    val rtl = TextUtils.getLayoutDirectionFromLocale(Locale.forLanguageTag(language)) == View.LAYOUT_DIRECTION_RTL
    CompositionLocalProvider(LocalLayoutDirection provides if (rtl) LayoutDirection.Rtl else LayoutDirection.Ltr) {
        Row(modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (bar != null) Box(Modifier.width(2.dp).fillMaxHeight().background(bar, CircleShape))
            Text(
                text,
                Modifier.weight(1f),
                style = style,
                color = color,
                textAlign = if (centered) TextAlign.Center else TextAlign.Start,
            )
        }
    }
}

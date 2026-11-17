package com.aljaroudi.muntathir.ui.hadith

import android.content.ClipData
import android.content.Intent
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.FormatSize
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.res.ResourcesCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.hadith.HadithBlock
import com.aljaroudi.muntathir.core.hadith.HadithDetail
import com.aljaroudi.muntathir.core.hadith.SupplicationTranslation
import com.aljaroudi.muntathir.core.highlight.HighlightColor
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.core.text.HadithParagraph
import com.aljaroudi.muntathir.core.text.HadithText
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.quran.ReadingSizeSheet
import com.aljaroudi.muntathir.ui.reader.ReaderDialogs
import com.aljaroudi.muntathir.ui.reader.ReaderText
import com.aljaroudi.muntathir.ui.reader.ReadingTextStyle
import com.aljaroudi.muntathir.ui.reader.rememberTextActions
import com.aljaroudi.muntathir.ui.reader.trackReading
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.time.Duration.Companion.milliseconds

/** Swift `HadithDetailView`: the narration's book, text, translations and gradings, with previous and next. */
@OptIn(FlowPreview::class)
@Composable
fun HadithDetailScreen(
    viewModel: HadithDetailViewModel,
    onBack: (() -> Unit)?,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val reading by viewModel.reading.collectAsStateWithLifecycle()
    val showEnglish by viewModel.showEnglish.collectAsStateWithLifecycle()
    val highlights by viewModel.highlights.collectAsStateWithLifecycle()
    val bookmarks by viewModel.bookmarks.collectAsStateWithLifecycle()
    var sizing by rememberSaveable { mutableStateOf(false) }
    var picking by rememberSaveable { mutableStateOf(false) }
    val locale = currentLocale()
    val loaded = state as? DetailState.Loaded
    val detail = loaded?.detail
    val supplication = detail?.narration?.isSupplication ?: viewModel.route.supplication
    val number = detail?.narration?.displayNumber
    val title =
        when {
            number != null && supplication -> stringResource(R.string.supplication_x, number)
            number != null -> stringResource(R.string.narration_x, number)
            supplication -> stringResource(R.string.supplications)
            else -> stringResource(R.string.hadith)
        }
    ScreenScaffold(
        title,
        onBack = onBack,
        actions = {
            if (detail != null) {
                val bookmarked = bookmarks.any { it.isHadith && it.source == detail.narration.source?.key }
                IconButton(onClick = { viewModel.toggleBookmark(detail) }, Modifier.testTag("hadith-bookmark")) {
                    Icon(
                        if (bookmarked) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                        stringResource(if (bookmarked) R.string.remove_bookmark else R.string.bookmark),
                    )
                }
                DetailMenu(
                    viewModel,
                    detail,
                    showEnglish,
                    onTranslation = { picking = true },
                    onTextSize = { sizing = true },
                )
            }
        },
    ) { padding ->
        val scroll = rememberScrollState(viewModel.initialOffset)
        LaunchedEffect(scroll) {
            snapshotFlow { scroll.value }.debounce(300.milliseconds).collect(viewModel::saveOffset)
        }
        LibraryGate(viewModel.library, supplications = supplication, padding = padding) {
            when (val current = state) {
                DetailState.Loading -> {
                    LoadingState(stringResource(R.string.loading_hadith), Modifier.padding(padding))
                }

                DetailState.Failed -> {
                    EmptyState(
                        stringResource(
                            if (supplication) R.string.unable_to_load_supplications else R.string.unable_to_load_hadith,
                        ),
                        Modifier.padding(padding),
                        message = stringResource(R.string.please_try_again),
                        onAction = viewModel::retry,
                    )
                }

                is DetailState.Loaded -> {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .trackReading(
                                if (supplication) {
                                    ProgressActivityKind.SupplicationReading
                                } else {
                                    ProgressActivityKind.HadithReading
                                },
                                enabled = !sizing,
                                save = viewModel::record,
                            ).verticalScroll(scroll)
                            .padding(padding),
                        contentAlignment = androidx.compose.ui.Alignment.TopCenter,
                    ) {
                        DetailContent(
                            viewModel,
                            current.detail,
                            showEnglish,
                            reading.readingSizePercent,
                            highlights,
                            locale,
                        )
                    }
                }
            }
        }
    }
    if (sizing) ReadingSizeSheet(reading.readingSizePercent, locale, viewModel::setSize) { sizing = false }
    if (picking && loaded != null) {
        SupplicationTranslationDialog(
            languages = loaded.translationLanguages,
            selection = reading.supplicationTranslation,
            onSelect = {
                viewModel.setTranslation(it)
                picking = false
            },
            onDismiss = { picking = false },
        )
    }
    DetailDialogs(viewModel, reading.highlightColors)
}

@Composable
private fun DetailContent(
    viewModel: HadithDetailViewModel,
    detail: HadithDetail,
    showEnglish: Boolean,
    sizePercent: Int,
    highlights: List<ReadingHighlight>,
    locale: Locale,
) {
    val narration = detail.narration
    val context = LocalContext.current
    val lateef = remember { ResourcesCompat.getFont(context, R.font.lateef_regular) }
    Column(
        Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        if (narration.isSupplication) {
            Text(
                narration.chapter.chapterTitle(locale),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.testTag("supplication-title").semantics { heading() },
            )
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    narration.chapter.bookTitle(locale),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.testTag("hadith-detail-book"),
                )
                detail.authorName(locale).takeIf { it.isNotEmpty() }?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                narration.chapter.chapterTitle(locale).takeIf { it.isNotEmpty() }?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.testTag("hadith-detail-chapter"),
                    )
                }
            }
            HorizontalDivider()
        }

        @Composable
        fun Block(
            paragraphs: List<HadithParagraph>,
            block: String,
            rightToLeft: Boolean = false,
        ) {
            val text = HadithText.canonical(paragraphs)
            val arabic = block == HadithBlock.ARABIC
            ReaderText(
                text = text,
                block = block,
                sizeSp =
                    if (arabic) {
                        ReadingTextStyle.arabicSize(
                            sizePercent,
                        )
                    } else {
                        ReadingTextStyle.bodySize(sizePercent)
                    },
                typeface = if (arabic) lateef else null,
                rightToLeft = arabic || rightToLeft,
                modifier = Modifier.fillMaxWidth().testTag("hadith-text-$block"),
                highlights = highlights,
                onHighlight = { viewModel.select(detail, block, text.text, it) },
                canHighlight = { narration.source != null },
                onOpenHighlights = viewModel::openHighlights,
            )
        }
        if (narration.arabic.isNotEmpty()) Block(detail.arabicText, HadithBlock.ARABIC)
        if (!narration.isSupplication && showEnglish && narration.englishNarrator.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    stringResource(R.string.narrator),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Block(detail.narratorText, HadithBlock.NARRATOR)
            }
        }
        if (!narration.isSupplication && showEnglish && narration.english.isNotEmpty()) {
            Block(detail.englishText, HadithBlock.ENGLISH)
        }
        narration.translation?.let { translation ->
            Block(
                HadithText.highlighted(translation.text, QuranSearchText.terms(viewModel.route.query)),
                translation.block,
                translation.isRightToLeft,
            )
        }
        val gradings = detail.gradings.filter { it.status == "judgment" && it.judgment(locale).isNotEmpty() }
        if (gradings.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    stringResource(R.string.grading),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.semantics { heading() },
                )
                for (grading in gradings) {
                    Column(
                        Modifier.semantics(mergeDescendants = true) {},
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(grading.judgment(locale), style = MaterialTheme.typography.titleSmall)
                        grading.grader(locale).takeIf { it.isNotEmpty() }?.let {
                            Text(
                                it,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        grading.reference(locale).takeIf { it.isNotEmpty() }?.let {
                            Text(
                                it,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
        if (!narration.isSupplication) {
            Row {
                TextButton(
                    onClick = { viewModel.open(detail.previousID) },
                    enabled = detail.previousID != null,
                    modifier = Modifier.testTag("hadith-previous"),
                ) { Text(stringResource(R.string.previous)) }
                Spacer(Modifier.weight(1f))
                TextButton(
                    onClick = { viewModel.open(detail.nextID) },
                    enabled = detail.nextID != null,
                    modifier = Modifier.testTag("hadith-next"),
                ) { Text(stringResource(R.string.next)) }
            }
        }
    }
}

/** Swift `HadithActions`: copy, share, translations and text size. */
@Composable
private fun DetailMenu(
    viewModel: HadithDetailViewModel,
    detail: HadithDetail,
    showEnglish: Boolean,
    onTranslation: () -> Unit,
    onTextSize: () -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val actions = rememberTextActions()
    val supplication = detail.narration.isSupplication
    val locale = currentLocale()
    Box {
        IconButton(onClick = { open = true }, Modifier.testTag("hadith-actions")) {
            Icon(
                Icons.Outlined.MoreVert,
                stringResource(if (supplication) R.string.supplication_actions else R.string.hadith_actions),
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            val content = viewModel.share(detail)
            DropdownMenuItem(
                text = { Text(stringResource(R.string.copy_text)) },
                leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                onClick = {
                    open = false
                    actions.copy(content.reference, content.text)
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.share)) },
                leadingIcon = { Icon(Icons.Outlined.Share, null) },
                onClick = {
                    open = false
                    actions.share(content.text)
                },
            )
            HorizontalDivider()
            if (supplication) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.translation)) },
                    leadingIcon = { Icon(Icons.Outlined.Translate, null) },
                    onClick = {
                        open = false
                        onTranslation()
                    },
                    modifier = Modifier.testTag("supplication-translation-picker"),
                )
            } else {
                DropdownMenuItem(
                    text = { Text(Locale.ENGLISH.getDisplayLanguage(locale)) },
                    leadingIcon = { Checkbox(checked = showEnglish, onCheckedChange = null) },
                    onClick = { viewModel.setEnglish(!showEnglish) },
                    modifier = Modifier.testTag("hadith-translation-english"),
                )
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.text_size)) },
                leadingIcon = { Icon(Icons.Outlined.FormatSize, null) },
                onClick = {
                    open = false
                    onTextSize()
                },
                modifier = Modifier.testTag("reading-size"),
            )
        }
    }
}

/** Swift `SupplicationTranslationPicker`: Auto, None, or one of the supplications' languages. */
@Composable
fun SupplicationTranslationDialog(
    languages: List<String>,
    selection: String,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val locale = currentLocale()
    val options =
        listOf(
            SupplicationTranslation.AUTO to stringResource(R.string.auto),
            SupplicationTranslation.NONE to stringResource(R.string.none),
        ) +
            languages.map { it to Locale.forLanguageTag(it).getDisplayLanguage(locale) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.translation)) },
        text = {
            Column {
                for ((value, label) in options) {
                    ListItem(
                        headlineContent = { Text(label) },
                        leadingContent = { RadioButton(selected = value == selection, onClick = null) },
                        modifier =
                            Modifier
                                .selectable(selected = value == selection) { onSelect(value) }
                                .testTag("supplication-translation-$value"),
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun DetailDialogs(
    viewModel: HadithDetailViewModel,
    colors: List<HighlightColor>,
) {
    val editing by viewModel.editing.collectAsStateWithLifecycle()
    val choosing by viewModel.choosing.collectAsStateWithLifecycle()
    val bookmarkFailed by viewModel.bookmarkFailed.collectAsStateWithLifecycle()
    ReaderDialogs(
        editing,
        choosing,
        bookmarkFailed,
        colors,
        onSave = viewModel::save,
        onDelete = viewModel::delete,
        onEdit = viewModel::edit,
        onClose = viewModel::closeEditor,
        onDismissBookmarkFailure = viewModel::dismissBookmarkFailure,
    )
}

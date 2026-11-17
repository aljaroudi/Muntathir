package com.aljaroudi.muntathir.ui.quran

import android.icu.text.NumberFormat
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.FormatSize
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.QuranReadingMode
import com.aljaroudi.muntathir.core.app.ReadingPreferences
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.quran.QuranReference
import com.aljaroudi.muntathir.core.quran.QuranTranslation
import com.aljaroudi.muntathir.core.text.SearchMatch
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.components.plus
import com.aljaroudi.muntathir.ui.reader.ReaderText
import com.aljaroudi.muntathir.ui.reader.ReadingTextStyle
import com.aljaroudi.muntathir.ui.reader.quranTypeface
import java.util.Locale

/** Swift `QuranReadingView`: one surah as verses, or the mushaf, keeping the position across modes. */
@Composable
fun QuranReaderScreen(
    viewModel: QuranReaderViewModel,
    onBack: (() -> Unit)?,
) {
    val reading by viewModel.reading.collectAsStateWithLifecycle()
    val catalog by viewModel.catalog.collectAsStateWithLifecycle()
    val chapter by viewModel.chapter.collectAsStateWithLifecycle()
    val position by viewModel.position.collectAsStateWithLifecycle()
    val locale = currentLocale()
    var juz by remember { mutableIntStateOf(0) }
    var sizing by rememberSaveable { mutableStateOf(false) }
    val surahs = catalog?.surahs.orEmpty()
    val surahTitle = surahs.getOrNull(position.surah - 1)?.title(locale.language).orEmpty()
    val mode = reading.quranReadingMode
    val title =
        if (mode == QuranReadingMode.Mushaf &&
            juz > 0
        ) {
            "$surahTitle · ${stringResource(R.string.juz_x, juz)}"
        } else {
            surahTitle
        }
    ScreenScaffold(
        title = title,
        onBack = onBack,
        actions = {
            ReaderMenu(
                mode = mode,
                onMode = { viewModel.setMode(it) },
                onTextSize = { sizing = true }.takeIf { mode == QuranReadingMode.Verses },
            )
        },
    ) { padding ->
        // Switching modes rebuilds the reader at the current position.
        key(mode) {
            when (mode) {
                QuranReadingMode.Verses -> {
                    VersesReader(
                        chapter = chapter,
                        initialVerse = position.verse,
                        query = viewModel.route.query,
                        sizePercent = reading.readingSizePercent,
                        surahNames = surahs.associate { it.id to it.arabic },
                        padding = padding,
                        onPosition = viewModel::setPosition,
                        onRetry = viewModel::retry,
                    )
                }

                QuranReadingMode.Mushaf -> {
                    if (surahs.isEmpty()) {
                        LoadingState(stringResource(R.string.loading_quran), Modifier.padding(padding))
                    } else {
                        MushafReader(
                            viewModel,
                            position,
                            surahs,
                            padding,
                            onPage = { juz = it.juz },
                            onPosition = viewModel::setPosition,
                        )
                    }
                }
            }
        }
    }
    if (sizing) {
        ReadingSizeSheet(reading.readingSizePercent, locale, viewModel::setSize) { sizing = false }
    }
}

/** Swift `QuranChapterView`: the surah's verses, opened at [initialVerse]; reports the topmost visible verse. */
@Composable
private fun VersesReader(
    chapter: ChapterState,
    initialVerse: Int,
    query: String?,
    sizePercent: Int,
    surahNames: Map<Int, String>,
    padding: PaddingValues,
    onPosition: (ReaderPosition) -> Unit,
    onRetry: () -> Unit,
) {
    when (chapter) {
        ChapterState.Loading -> {
            LoadingState(stringResource(R.string.loading_quran), Modifier.padding(padding))
        }

        ChapterState.Failed -> {
            EmptyState(stringResource(R.string.unable_to_load_quran), Modifier.padding(padding), onAction = onRetry)
        }

        is ChapterState.Loaded -> {
            key(chapter.surah) {
                val start = chapter.verses.indexOfFirst { it.number == initialVerse }.coerceAtLeast(0)
                val list = rememberLazyListState(initialFirstVisibleItemIndex = start)
                val report by rememberUpdatedState(onPosition)
                LaunchedEffect(list, chapter) {
                    snapshotFlow { list.firstVisibleItemIndex }.collect { index ->
                        chapter.verses.getOrNull(index)?.let { report(ReaderPosition(it.surah, it.number)) }
                    }
                }
                LazyColumn(
                    state = list,
                    contentPadding = padding + PaddingValues(bottom = 24.dp),
                    modifier = Modifier.fillMaxSize().testTag("quran-verses"),
                ) {
                    items(chapter.verses, key = { it.id }) { ayah ->
                        QuranVerseRow(
                            ayah = ayah,
                            translation = chapter.translation,
                            query = query,
                            sizePercent = sizePercent,
                            surahNames = surahNames,
                        )
                        HorizontalDivider(Modifier.padding(horizontal = 20.dp))
                    }
                }
            }
        }
    }
}

/** Swift `QuranVerseRow` (full mode): reference and actions, Arabic, then the translation. */
@Composable
fun QuranVerseRow(
    ayah: Ayah,
    translation: String?,
    query: String?,
    sizePercent: Int,
    surahNames: Map<Int, String>,
    modifier: Modifier = Modifier,
    actions: (@Composable (close: () -> Unit) -> Unit)? = null,
) {
    val locale = currentLocale()
    val reference = QuranReference.display(ayah.id, locale.language, surahNames)
    val translated = translation?.let { ayah.translations[it] }
    val verseLabel = stringResource(R.string.verse_x, reference)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            modifier
                .widthIn(
                    max = 640.dp,
                ).fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp)
                .testTag("quran-verse-${ayah.id}"),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    reference,
                    style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.semantics { contentDescription = verseLabel },
                )
                Spacer(Modifier.weight(1f))
                VerseActions(ayah, translated, reference, Modifier.testTag("verse-actions-${ayah.id}"), actions)
            }
            ReaderText(
                text = SearchMatch.text(ayah.text, query.orEmpty()),
                block = ARABIC_BLOCK,
                sizeSp = ReadingTextStyle.arabicSize(sizePercent),
                typeface = quranTypeface(),
                rightToLeft = true,
                modifier = Modifier.fillMaxWidth().testTag("quran-arabic-${ayah.id}"),
            )
            if (translation != null && translated != null) {
                ReaderText(
                    text = SearchMatch.text(translated, query.orEmpty()),
                    block = translation,
                    sizeSp = ReadingTextStyle.bodySize(sizePercent),
                    rightToLeft = QuranTranslation.of(translation)?.isRightToLeft == true,
                    modifier = Modifier.fillMaxWidth().testTag("quran-translation-${ayah.id}"),
                )
            }
        }
    }
}

const val ARABIC_BLOCK = "arabic"

/** Reading mode and text size. */
@Composable
private fun ReaderMenu(
    mode: QuranReadingMode,
    onMode: (QuranReadingMode) -> Unit,
    onTextSize: (() -> Unit)?,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, Modifier.testTag("quran-reading-options")) {
            Icon(Icons.Outlined.MoreVert, stringResource(R.string.reading_options))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            Text(
                stringResource(R.string.reading_mode),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            )
            for ((option, label) in listOf(
                QuranReadingMode.Verses to R.string.verses,
                QuranReadingMode.Mushaf to R.string.mushaf,
            )) {
                DropdownMenuItem(
                    text = { Text(stringResource(label)) },
                    leadingIcon = {
                        if (option ==
                            mode
                        ) {
                            Icon(Icons.Outlined.Check, null)
                        } else {
                            Spacer(Modifier.padding(12.dp))
                        }
                    },
                    onClick = {
                        open = false
                        onMode(option)
                    },
                    modifier = Modifier.testTag("reading-mode-${option.id}"),
                )
            }
            if (onTextSize != null) {
                HorizontalDivider()
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
}

/** Swift `ReadingSizeMenu`: smaller/larger in 10% steps (80–160%) and Reset. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadingSizeSheet(
    percent: Int,
    locale: Locale,
    onChange: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val sizes = ReadingPreferences.SIZES
    val step = ReadingPreferences.SIZE_STEP
    val value = remember(percent, locale) { NumberFormat.getPercentInstance(locale).format(percent / 100.0) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.text_size), style = MaterialTheme.typography.titleMedium)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                val decrease = stringResource(R.string.decrease_text_size)
                val increase = stringResource(R.string.increase_text_size)
                OutlinedIconButton(
                    onClick = { onChange((percent - step).coerceIn(sizes)) },
                    enabled = percent > sizes.first,
                    modifier =
                        Modifier.testTag("reading-size-decrease").semantics {
                            contentDescription = decrease
                            stateDescription = value
                        },
                ) { Text("A", fontSize = 18.sp) }
                Text(value, style = MaterialTheme.typography.titleLarge.copy(fontFeatureSettings = "tnum"))
                OutlinedIconButton(
                    onClick = { onChange((percent + step).coerceIn(sizes)) },
                    enabled = percent < sizes.last,
                    modifier =
                        Modifier.testTag("reading-size-increase").semantics {
                            contentDescription = increase
                            stateDescription = value
                        },
                ) { Text("A", fontSize = 30.sp) }
            }
            TextButton(
                onClick = { onChange(ReadingPreferences.DEFAULT_SIZE) },
                enabled = percent != ReadingPreferences.DEFAULT_SIZE,
                modifier = Modifier.testTag("reading-size-reset"),
            ) { Text(stringResource(R.string.reset)) }
        }
    }
}

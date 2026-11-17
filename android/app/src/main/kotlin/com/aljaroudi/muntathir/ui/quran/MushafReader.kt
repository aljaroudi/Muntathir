package com.aljaroudi.muntathir.ui.quran

import android.util.TypedValue
import android.view.View
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.SelfImprovement
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.quran.QuranPage
import com.aljaroudi.muntathir.core.quran.QuranPageText
import com.aljaroudi.muntathir.core.quran.QuranSurah
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.ui.components.EmptyState
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.LoadingState
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.reader.HighlightTextView
import com.aljaroudi.muntathir.ui.reader.quranTypeface

/** What a mushaf page offers its host: selection to highlight drafts, and saved highlights to draw. */
class MushafHighlights(
    val highlights: (QuranPageText) -> List<ReadingHighlight> = { emptyList() },
    val onSelect: (QuranPageText, List<TextRange>) -> Unit = { _, _ -> },
    val onOpen: (List<ReadingHighlight>) -> Unit = {},
)

/**
 * Swift `QuranMushafView`: 604 pages paged right to left (swiping right goes forward). Opens at the page of
 * [position], then reports the first verse of each settled page and its juz.
 */
@Composable
fun MushafReader(
    viewModel: QuranReaderViewModel,
    position: ReaderPosition,
    surahs: List<QuranSurah>,
    padding: PaddingValues,
    onPage: (QuranPage) -> Unit,
    onPosition: (ReaderPosition) -> Unit,
    modifier: Modifier = Modifier,
    highlights: MushafHighlights = MushafHighlights(),
) {
    var initialPage by rememberSaveable { mutableStateOf<Int?>(null) }
    var failed by remember { mutableStateOf(false) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(retry) {
        if (initialPage == null) {
            val number = viewModel.pageNumber(position)
            if (number == null) failed = true else initialPage = number
        }
    }
    val start = initialPage
    if (start == null) {
        if (failed) {
            EmptyState(stringResource(R.string.unable_to_load_quran), modifier.padding(padding), onAction = {
                failed = false
                retry++
            })
        } else {
            LoadingState(stringResource(R.string.loading_quran), modifier.padding(padding))
        }
        return
    }
    val pager = rememberPagerState(initialPage = start - 1) { QuranPage.COUNT }
    // The opening verse stands until the reader turns the page.
    var keepOpeningVerse by rememberSaveable { mutableStateOf(true) }
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        HorizontalPager(
            pager,
            modifier.fillMaxSize().padding(padding),
            beyondViewportPageCount = 1,
            key = { it },
        ) { index ->
            val number = index + 1
            MushafPage(
                viewModel,
                number,
                surahs,
                highlights,
                onLoaded = { page ->
                    if (pager.settledPage != index) return@MushafPage
                    onPage(page)
                    if (keepOpeningVerse && number == start) return@MushafPage
                    keepOpeningVerse = false
                    val first = page.verses.minByOrNull { it.key }?.value ?: return@MushafPage
                    onPosition(ReaderPosition(first.surah, first.number))
                },
                settled = pager.settledPage == index,
            )
        }
    }
}

@Composable
private fun MushafPage(
    viewModel: QuranReaderViewModel,
    number: Int,
    surahs: List<QuranSurah>,
    highlights: MushafHighlights,
    onLoaded: (QuranPage) -> Unit,
    settled: Boolean,
) {
    var retry by remember { mutableIntStateOf(0) }
    val state by produceState<Result<QuranPage>?>(null, number, retry) {
        value = viewModel.page(number)?.let { Result.success(it) } ?: Result.failure(IllegalStateException())
    }
    val page = state?.getOrNull()
    val loaded by rememberUpdatedState(onLoaded)
    LaunchedEffect(page, settled) { if (page != null && settled) loaded(page) }
    val locale = currentLocale()
    // Pages stay right to left (inherited from the pager), like a printed mushaf.
    run {
        when {
            state == null -> {
                LoadingState(stringResource(R.string.loading_quran))
            }

            page == null -> {
                EmptyState(stringResource(R.string.unable_to_load_quran), onAction = { retry++ })
            }

            else -> {
                Column(
                    Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 8.dp).testTag("quran-page-$number"),
                ) {
                    BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        val width = constraints.maxWidth
                        val height = constraints.maxHeight
                        val typeface = quranTypeface()
                        val text = remember(page, surahs) { QuranPageText(page, surahs) }
                        val layout =
                            remember(text, width, height, typeface) { MushafLayout(text, typeface, width, height) }
                        val saved = highlights.highlights(text)
                        val color = LocalContentColor.current.toArgb()
                        AndroidView(
                            factory = { context ->
                                HighlightTextView(context).apply {
                                    includeFontPadding = false
                                    textDirection = View.TEXT_DIRECTION_RTL
                                    setLineSpacing(0f, 1f)
                                }
                            },
                            update = { view ->
                                view.setTextColor(color)
                                view.typeface = typeface
                                view.setTextSize(TypedValue.COMPLEX_UNIT_PX, layout.fontSize)
                                view.canHighlight = { text.canHighlight(it) }
                                view.onHighlight = { highlights.onSelect(text, it) }
                                view.onOpenHighlights = highlights.onOpen
                                view.render(
                                    StyledText(layout.text),
                                    saved,
                                    "arabic",
                                    layoutKey = layout,
                                    rangesOf = text::displayRanges,
                                    decorate = layout::decorate,
                                )
                            },
                            modifier = Modifier.fillMaxWidth().testTag("quran-page-text-$number"),
                        )
                    }
                    MushafFooter(page, locale)
                }
            }
        }
    }
}

/** Juz, sajda mark and page number, hizb. */
@Composable
private fun MushafFooter(
    page: QuranPage,
    locale: java.util.Locale,
) {
    val style = MaterialTheme.typography.labelMedium
    val color = MaterialTheme.colorScheme.onSurfaceVariant
    CompositionLocalProvider(LocalContentColor provides color) {
        Row(
            Modifier.fillMaxWidth().height(40.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(R.string.juz_x, page.juz), style = style)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (page.sajdas.isNotEmpty()) {
                    Icon(Icons.Outlined.SelfImprovement, stringResource(R.string.prostration), Modifier.size(16.dp))
                }
                Text(Formats.number(page.number, locale), style = style)
            }
            Text(stringResource(R.string.hizb_x, page.hizb), style = style)
        }
    }
}

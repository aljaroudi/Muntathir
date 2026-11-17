package com.aljaroudi.muntathir.ui.hadith

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.hadith.Hadith
import com.aljaroudi.muntathir.core.text.SearchMatch
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.reader.ReadingTextStyle
import com.aljaroudi.muntathir.ui.reader.toAnnotatedString
import com.aljaroudi.muntathir.ui.theme.HadithFont
import java.util.Locale

/** Swift `HadithPreviewRow`: book, chapter, number, then the Arabic and (when shown) English previews. */
@Composable
fun HadithPreviewRow(
    narration: Hadith,
    searching: Boolean,
    showEnglish: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val locale = currentLocale()
    val arabic = narration.arabicPreview ?: StyledText(narration.arabic)
    val english = narration.englishPreview ?: StyledText(narration.english)
    val visible =
        SearchMatch.visibleBlocks(
            listOf(arabic, if (showEnglish) english else StyledText("")),
            preferred = if (locale.language == "ar" || !showEnglish) 0 else 1,
        )
    val lines = if (searching) 2 else 5
    Box(Modifier.fillMaxWidth().clickable(onClick = onClick), contentAlignment = Alignment.TopCenter) {
        Column(
            modifier
                .widthIn(max = 640.dp)
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp)
                .semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Caption(narration.chapter.bookTitle(locale))
            narration.chapter
                .chapterTitle(locale)
                .takeIf { it.isNotEmpty() }
                ?.let { Caption(it) }
            narration.displayNumber?.let {
                Text(Formats.number(it, locale), style = MaterialTheme.typography.titleMedium)
            }
            if (narration.arabic.isNotEmpty() && (!searching || 0 in visible)) {
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    Text(
                        (if (searching) SearchMatch.preview(arabic, compact = true) else arabic).toAnnotatedString(),
                        style = hadithArabicStyle(),
                        maxLines = lines,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            if (showEnglish && narration.english.isNotEmpty() && (!searching || 1 in visible)) {
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                    Text(
                        (if (searching) SearchMatch.preview(english, compact = true) else english).toAnnotatedString(),
                        style = MaterialTheme.typography.bodyLarge,
                        maxLines = lines,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.fillMaxWidth().testTag("hadith-preview-english-${narration.id}"),
                    )
                }
            }
        }
    }
}

@Composable
private fun Caption(text: String) =
    Text(text, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)

/** Lateef at the Arabic reading size, for previews. */
@Composable
fun hadithArabicStyle(): TextStyle =
    MaterialTheme.typography.bodyLarge.copy(
        fontFamily = HadithFont,
        fontSize = (ReadingTextStyle.ARABIC_SP * 0.85f).sp,
        lineHeight = (ReadingTextStyle.ARABIC_SP * 1.4f).sp,
    )

/** Swift `HadithTranslationPicker`: the English toggle, under a Translations button. */
@Composable
fun HadithTranslationMenu(
    showEnglish: Boolean,
    onChange: (Boolean) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val locale = currentLocale()
    Box {
        IconButton(onClick = { open = true }, Modifier.testTag("hadith-translation-picker")) {
            Icon(Icons.Outlined.Translate, stringResource(R.string.translations))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(Locale.ENGLISH.getDisplayLanguage(locale)) },
                leadingIcon = { Checkbox(checked = showEnglish, onCheckedChange = null) },
                onClick = { onChange(!showEnglish) },
                modifier = Modifier.testTag("hadith-translation-english"),
            )
        }
    }
}

package com.aljaroudi.muntathir.ui.reader

import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import com.aljaroudi.muntathir.core.text.ArabicDisplay
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.core.text.TextStyle

val LocalShowArabicDiacritics = compositionLocalOf { true }

@Composable
fun String.readingDisplay(): String =
    if (LocalShowArabicDiacritics.current) this else remember(this) { filterNot(ArabicDisplay::isMark) }

@Composable
fun StyledText.readingDisplay(): ArabicDisplay? =
    if (LocalShowArabicDiacritics.current) {
        null
    } else {
        remember(this) {
            if (text.any(ArabicDisplay::isMark)) ArabicDisplay(this) else null
        }
    }

/** Compose text for previews and lists; search matches are underlined and bold, never color alone. */
@Composable
fun StyledText.toAnnotatedString(): AnnotatedString = (readingDisplay()?.text ?: this).annotated()

private fun StyledText.annotated(): AnnotatedString =
    AnnotatedString
        .Builder(text)
        .apply {
            for (span in spans) {
                when (val style = span.style) {
                    TextStyle.Strong -> {
                        addStyle(SpanStyle(fontWeight = FontWeight.Bold), span.start, span.end)
                    }

                    TextStyle.Emphasis -> {
                        addStyle(SpanStyle(fontStyle = FontStyle.Italic), span.start, span.end)
                    }

                    TextStyle.Code -> {
                        addStyle(SpanStyle(fontFamily = FontFamily.Monospace), span.start, span.end)
                    }

                    TextStyle.Strikethrough -> {
                        addStyle(
                            SpanStyle(textDecoration = TextDecoration.LineThrough),
                            span.start,
                            span.end,
                        )
                    }

                    TextStyle.Match -> {
                        addStyle(
                            SpanStyle(textDecoration = TextDecoration.Underline),
                            span.start,
                            span.end,
                        )
                    }

                    is TextStyle.Link -> {
                        addLink(LinkAnnotation.Url(style.url), span.start, span.end)
                    }
                }
            }
        }.toAnnotatedString()

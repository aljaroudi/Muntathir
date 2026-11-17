package com.aljaroudi.muntathir.ui.reader

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.core.text.TextStyle

/** Compose text for previews and lists; search matches are underlined and bold, never color alone. */
fun StyledText.toAnnotatedString(): AnnotatedString =
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

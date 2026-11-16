package com.aljaroudi.muntathir.ui.today

import android.content.ClipData
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.core.quran.QuranReference
import com.aljaroudi.muntathir.data.QuranDatabase
import com.aljaroudi.muntathir.ui.theme.QuranFont
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.ceil

/** The translation to show beside Arabic: the bundled English, except in an Arabic interface (P3.3 adds the picker). */
fun dailyTranslation(
    ayah: Ayah,
    locale: Locale,
): String? = if (locale.language == "ar") null else ayah.translations[QuranDatabase.ENGLISH]

/** Swift `DailyAyahCard`. */
@Composable
fun DailyAyahCard(
    ayah: Ayah,
    surahNames: Map<Int, String>,
    onSky: Boolean,
    locale: Locale,
    modifier: Modifier = Modifier,
) {
    val reference = QuranReference.display(ayah.id, locale.language, surahNames)
    val translation = dailyTranslation(ayah, locale)
    val shape = RoundedCornerShape(28.dp)
    Box(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .border(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), shape),
    ) {
        if (onSky) {
            Box(
                Modifier.matchParentSize().background(skyCardColor(true)),
            )
        } else {
            AyahBackground(Modifier.matchParentSize())
        }
        CompositionLocalProvider(
            androidx.compose.material3.LocalContentColor provides MaterialTheme.colorScheme.onSurface,
        ) {
            Column(Modifier.padding(20.dp).widthIn(max = 640.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Icon(
                        Icons.AutoMirrored.Outlined.MenuBook,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        stringResource(R.string.daily_ayah),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 8.dp).weight(1f),
                    )
                    VerseMenu(ayah, translation, reference, locale)
                }
                SelectionContainer {
                    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        AyahArabic(ayah.text, Modifier.testTag("daily-ayah-text"))
                        translation?.let {
                            Text(
                                it,
                                textAlign = TextAlign.Center,
                                style = MaterialTheme.typography.bodyLarge,
                                modifier = Modifier.fillMaxWidth().testTag("daily-ayah-translation"),
                            )
                        }
                    }
                }
                Text(
                    reference,
                    style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.End,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

/** Arabic verse text, always right to left, in the Hafs font at the reading size (28 sp × 100% for now). */
@Composable
fun AyahArabic(
    text: String,
    modifier: Modifier = Modifier,
    size: Float = 28f,
) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Text(
            text,
            fontFamily = QuranFont,
            fontSize = size.sp,
            lineHeight = (size * 1.75f).sp,
            textAlign = TextAlign.Center,
            modifier = modifier.fillMaxWidth(),
        )
    }
}

/** Swift `VerseActions` for the daily card: copy and share as image (bookmarks arrive with P3.4). */
@Composable
private fun VerseMenu(
    ayah: Ayah,
    translation: String?,
    reference: String,
    locale: Locale,
) {
    var open by remember { mutableStateOf(false) }
    var sharing by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val copied = stringResource(R.string.text_copied)
    val text = listOfNotNull(ayah.text, translation, reference).joinToString("\n\n")
    Box {
        IconButton(onClick = { open = true }, Modifier.testTag("share-daily-ayah")) {
            Icon(Icons.Outlined.MoreVert, stringResource(R.string.actions_for_verse_x, reference))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.copy_text)) },
                leadingIcon = { Icon(Icons.Outlined.ContentCopy, null) },
                onClick = {
                    open = false
                    scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(reference, text))) }
                    // Android 13+ confirms copies itself.
                    if (Build.VERSION.SDK_INT <
                        Build.VERSION_CODES.TIRAMISU
                    ) {
                        Toast.makeText(context, copied, Toast.LENGTH_SHORT).show()
                    }
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.share_as_image)) },
                leadingIcon = { Icon(Icons.Outlined.Share, null) },
                onClick = {
                    open = false
                    sharing = true
                },
            )
        }
    }
    if (sharing) {
        ShareImage(
            name = "ayah-${ayah.surah}-${ayah.number}",
            fallbackText = text,
            onDone = { sharing = false },
        ) { AyahShareArtwork(ayah, translation, reference) }
    }
}

/** Swift `AyahShareArtwork` + `ShareArtwork`: 540 dp wide, light, on the ayah background. */
@Composable
fun AyahShareArtwork(
    ayah: Ayah,
    translation: String?,
    reference: String,
) {
    Box(Modifier.width(ShareImageSpec.WIDTH_DP.dp)) {
        AyahBackground(Modifier.matchParentSize(), dark = false)
        Column(
            Modifier.padding(40.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
            horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
        ) {
            AyahArabic(ayah.text, Modifier.padding(16.dp))
            translation?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyLarge,
                    color = Color(0xFF1C1B1F),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Text(
                reference,
                style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                color = Color(0xFF1C1B1F),
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f))
            Text(
                stringResource(R.string.muntathir),
                style = MaterialTheme.typography.titleSmall,
                color = Color(0xFF49454F),
            )
        }
    }
}

/** Swift `AyahBackground`: a wash, two glows, accent contours and a fixed paper grain. */
@Composable
fun AyahBackground(
    modifier: Modifier = Modifier,
    dark: Boolean = isSystemInDarkTheme(),
) {
    val accent = MaterialTheme.colorScheme.primary
    Canvas(modifier.clearAndSetSemantics {}) {
        val wash =
            if (dark) {
                listOf(Color(0.04f, 0.21f, 0.18f), Color(0.06f, 0.12f, 0.17f))
            } else {
                listOf(Color(0.77f, 0.89f, 0.82f), Color(0.98f, 0.93f, 0.81f))
            }
        val rtl = layoutDirection == LayoutDirection.Rtl
        val leading = if (rtl) size.width else 0f
        val trailing = size.width - leading
        drawRect(Brush.linearGradient(wash, Offset(leading, 0f), Offset(trailing, size.height)))
        drawRect(
            Brush.radialGradient(
                listOf(Color(0.29f, 0.70f, 0.55f, 0.32f * 0.7f), Color.Transparent),
                center = Offset(leading, 0f),
                radius = size.width * 0.85f,
            ),
        )
        drawRect(
            Brush.radialGradient(
                listOf(Color(0.88f, 0.70f, 0.36f, (if (dark) 0.16f else 0.3f) * 0.7f), Color.Transparent),
                center = Offset(trailing, size.height),
                radius = size.width * 0.7f,
            ),
        )
        val unit = density
        for (index in 0 until 4) {
            val inset = index * 22f * unit
            drawOval(
                accent.copy(alpha = if (dark) 0.14f else 0.09f),
                topLeft = Offset(size.width * 0.62f + inset, -size.height * 0.6f + inset),
                size = Size(size.width * 0.95f, size.height * 1.5f),
                style = Stroke(0.7f * unit),
            )
        }
        // Fixed positions keep the texture identical between renders.
        val dot = 0.4f * unit
        for (row in 0 until ceil(size.height / (4 * unit)).toInt()) {
            for (column in 0 until ceil(size.width / (4 * unit)).toInt()) {
                // 64-bit with truncating remainders, exactly like Swift's Int arithmetic.
                val seed = (row * 73_856_093L) xor (column * 19_349_663L)
                val x = (column * 4 + (seed % 17) / 5f) * unit
                val y = (row * 4 + ((seed / 17) % 17) / 5f) * unit
                val color = if (seed % 2 == 0L) Color.Black.copy(alpha = 0.08f) else Color.White.copy(alpha = 0.16f)
                drawCircle(color, dot, Offset(x + dot, y + dot))
            }
        }
    }
}

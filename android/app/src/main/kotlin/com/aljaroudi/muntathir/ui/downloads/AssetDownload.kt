package com.aljaroudi.muntathir.ui.downloads

import android.content.Context
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.components.currentLocale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.util.Locale
import kotlin.math.roundToLong

/** Swift `AssetDownloadSize`: estimated pack sizes in bytes, keyed by iOS pack id (e.g. `quran-translations`). */
object AssetDownloadSizes {
    const val QURAN_TRANSLATIONS = "quran-translations"

    fun estimate(
        context: Context,
        pack: String,
    ): Long? =
        runCatching {
            val text = context.assets.open("quran/AssetDownloadSizes.json").use { it.readBytes().decodeToString() }
            Json
                .parseToJsonElement(text)
                .jsonObject[pack]
                ?.jsonPrimitive
                ?.longOrNull
        }.getOrNull()
}

/** Swift `AssetSizeText`: decimal units rounded to a whole unit, e.g. "8 MB". */
fun formatBytes(
    bytes: Long,
    locale: Locale,
): String {
    val (unit, size) =
        when {
            bytes >= 1_000_000_000 -> MeasureUnit.GIGABYTE to 1_000_000_000.0
            bytes >= 1_000_000 -> MeasureUnit.MEGABYTE to 1_000_000.0
            bytes >= 1_000 -> MeasureUnit.KILOBYTE to 1_000.0
            else -> MeasureUnit.BYTE to 1.0
        }
    return android.icu.text.MeasureFormat
        .getInstance(locale, android.icu.text.MeasureFormat.FormatWidth.SHORT)
        .format(Measure((bytes / size).roundToLong(), unit))
}

/** Swift `AssetDownloadButton`: Download (or Try again) with the estimated size. */
@Composable
fun AssetDownloadButton(
    pack: String,
    retry: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val context = LocalContext.current
    val locale = currentLocale()
    val size = remember(pack, locale) { AssetDownloadSizes.estimate(context, pack)?.let { formatBytes(it, locale) } }
    val label = stringResource(if (retry) R.string.try_again else R.string.download)
    val estimated = size?.let { stringResource(R.string.estimated_size_x, it) }
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier =
            modifier.semantics {
                contentDescription = label
                estimated?.let { stateDescription = it }
            },
    ) {
        Icon(
            if (retry) Icons.Outlined.Refresh else Icons.Outlined.Download,
            null,
            Modifier.padding(end = ButtonDefaults.IconSpacing),
        )
        Text(size?.let { "≈ $it" } ?: label)
    }
}

/** Swift `AssetDownloadProgress`: preparing, downloading with a percentage when known, or installing. */
@Composable
fun AssetDownloadProgress(
    progress: Float?,
    installing: Boolean,
    preparing: Boolean,
    modifier: Modifier = Modifier,
) {
    val locale = currentLocale()
    val done = installing || (progress ?: 0f) >= 1f
    val label =
        stringResource(
            when {
                done -> R.string.installing
                preparing -> R.string.preparing_download
                else -> R.string.downloading
            },
        )
    Column(
        modifier.widthIn(max = 300.dp).fillMaxWidth().testTag("asset-download-progress"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        val fraction = progress?.takeIf { it.isFinite() && !done }?.coerceIn(0f, 1f)
        if (fraction != null) {
            LinearProgressIndicator(progress = { fraction }, Modifier.fillMaxWidth())
            Text(
                android.icu.text.NumberFormat
                    .getPercentInstance(locale)
                    .format(fraction.toDouble()),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            LinearProgressIndicator(Modifier.fillMaxWidth())
        }
    }
}

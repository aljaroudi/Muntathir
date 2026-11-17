package com.aljaroudi.muntathir.ui.today

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.core.content.FileProvider
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.android.awaitFrame
import kotlinx.coroutines.withContext
import java.io.File

/** Swift `ShareImageRenderer` limits: 540 dp at 2× (1080 px wide), at most 1920 px tall. */
object ShareImageSpec {
    const val WIDTH_DP = 540
    const val SCALE = 2f
    const val MAX_HEIGHT_PX = 1920
}

/**
 * Draws [artwork] off screen at 2× in the light theme, then opens the share sheet with a PNG. Artwork taller
 * than the limit (or a failed render) shares [fallbackText] and shows "Unable to create image".
 */
@Composable
fun ShareImage(
    name: String,
    fallbackText: String,
    onDone: () -> Unit,
    artwork: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val failure = stringResource(R.string.unable_to_create_image)
    val layer = rememberGraphicsLayer()
    val done by rememberUpdatedState(onDone)
    // Recorded but never drawn: the artwork is invisible and doesn't affect layout.
    Box(
        Modifier
            .layout { measurable, _ ->
                val placeable = measurable.measure(Constraints())
                layout(0, 0) { placeable.place(0, 0) }
            }.drawWithContent { layer.record { this@drawWithContent.drawContent() } },
    ) {
        CompositionLocalProvider(LocalDensity provides Density(ShareImageSpec.SCALE, 1f)) {
            MuntathirTheme(darkTheme = false, dynamicColor = false) {
                Box(Modifier.wrapContentSize()) { artwork() }
            }
        }
    }
    LaunchedEffect(Unit) {
        awaitFrame()
        awaitFrame()
        val image = runCatching { layer.toImageBitmap() }.getOrNull()
        val bitmap = image?.asAndroidBitmap()?.takeIf { it.height in 1..ShareImageSpec.MAX_HEIGHT_PX }
        if (bitmap == null) {
            Toast.makeText(context, failure, Toast.LENGTH_SHORT).show()
            share(context, Intent().putExtra(Intent.EXTRA_TEXT, fallbackText).setType("text/plain"))
        } else {
            val file = withContext(Dispatchers.IO) { save(context, bitmap, name) }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.share", file)
            val intent =
                Intent()
                    .putExtra(
                        Intent.EXTRA_STREAM,
                        uri,
                    ).setType("image/png")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // ClipData lets the share sheet show the image preview.
            intent.clipData = android.content.ClipData.newRawUri(null, uri)
            share(context, intent)
        }
        done()
    }
}

private fun save(
    context: Context,
    bitmap: Bitmap,
    name: String,
): File {
    val directory = File(context.cacheDir, "share").apply { mkdirs() }
    // One shared image at a time; older ones are no longer needed.
    directory.listFiles()?.forEach(File::delete)
    return File(
        directory,
        "$name.png",
    ).apply { outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } }
}

private fun share(
    context: Context,
    intent: Intent,
) {
    context.startActivity(Intent.createChooser(intent.setAction(Intent.ACTION_SEND), null))
}

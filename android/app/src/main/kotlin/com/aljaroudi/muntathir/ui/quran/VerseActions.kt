package com.aljaroudi.muntathir.ui.quran

import android.content.ClipData
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.quran.Ayah
import com.aljaroudi.muntathir.ui.today.AyahShareArtwork
import com.aljaroudi.muntathir.ui.today.ShareImage
import kotlinx.coroutines.launch

/**
 * Swift `VerseActions`: copy the verse (Arabic, translation, reference), share it as an image, and any [extra]
 * items such as Bookmark, after a divider.
 */
@Composable
fun VerseActions(
    ayah: Ayah,
    translation: String?,
    reference: String,
    modifier: Modifier = Modifier,
    extra: (@Composable (close: () -> Unit) -> Unit)? = null,
) {
    var open by remember { mutableStateOf(false) }
    var sharing by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val copied = stringResource(R.string.text_copied)
    val text = listOfNotNull(ayah.text, translation, reference).joinToString("\n\n")
    Box {
        IconButton(onClick = { open = true }, modifier) {
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
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
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
            if (extra != null) {
                HorizontalDivider()
                extra { open = false }
            }
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

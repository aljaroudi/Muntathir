package com.aljaroudi.muntathir.ui.reader

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.Clipboard
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.highlight.HighlightColor
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * A reader's highlight dialogs: the editor for [editing], Swift's "Highlights" chooser for overlapping
 * [choosing], and the bookmark failure alert.
 */
@Composable
fun ReaderDialogs(
    editing: HighlightDraft?,
    choosing: List<ReadingHighlight>,
    bookmarkFailed: Boolean,
    colors: List<HighlightColor>,
    onSave: suspend (List<ReadingHighlight>) -> Unit,
    onDelete: suspend (ReadingHighlight) -> Unit,
    onEdit: (ReadingHighlight) -> Unit,
    onClose: () -> Unit,
    onDismissBookmarkFailure: () -> Unit,
) {
    editing?.let { draft -> key(draft) { HighlightEditorSheet(draft, colors, onSave, onDelete, onClose) } }
    if (choosing.isNotEmpty()) {
        AlertDialog(
            onDismissRequest = onClose,
            title = { Text(stringResource(R.string.highlights)) },
            text = {
                Column {
                    for (highlight in choosing) {
                        ListItem(
                            headlineContent = { Text(highlight.note.ifBlank { highlight.excerpt }.take(60)) },
                            leadingContent = { HighlightSwatch(highlight.color, selected = false, size = 20) },
                            modifier = Modifier.clickable { onEdit(highlight) },
                        )
                    }
                }
            },
            confirmButton = { TextButton(onClick = onClose) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (bookmarkFailed) BookmarkFailedDialog(onDismissBookmarkFailure)
}

/** Swift's "Unable to save bookmark" alert. */
@Composable
fun BookmarkFailedDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.unable_to_save_bookmark)) },
        text = { Text(stringResource(R.string.please_try_again)) },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.ok)) } },
    )
}

/** Copy and share for reader text. */
class TextActions(
    private val context: Context,
    private val clipboard: Clipboard,
    private val scope: CoroutineScope,
) {
    fun copy(
        label: String,
        text: String,
    ) {
        scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(label, text))) }
        // Android 13+ confirms copies itself.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            Toast.makeText(context, context.getString(R.string.text_copied), Toast.LENGTH_SHORT).show()
        }
    }

    fun share(text: String) {
        val intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        context.startActivity(Intent.createChooser(intent, null))
    }
}

@Composable
fun rememberTextActions(): TextActions {
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    return remember(context, clipboard, scope) { TextActions(context, clipboard, scope) }
}

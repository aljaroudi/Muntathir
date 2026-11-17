package com.aljaroudi.muntathir.ui.reader

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.highlight.HighlightColor
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.highlight.serialName
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What the editor opens with: a new selection (one highlight per verse) or a saved highlight. */
data class HighlightDraft(
    val highlights: List<ReadingHighlight>,
    val existing: Boolean,
)

@get:StringRes
val HighlightColor.title: Int
    get() =
        when (this) {
            HighlightColor.Yellow -> R.string.yellow
            HighlightColor.Green -> R.string.green
            HighlightColor.Blue -> R.string.blue
            HighlightColor.Pink -> R.string.pink
            HighlightColor.Purple -> R.string.purple
            HighlightColor.Orange -> R.string.orange
            HighlightColor.Red -> R.string.red
            HighlightColor.Mint -> R.string.mint
            HighlightColor.Teal -> R.string.teal
            HighlightColor.Cyan -> R.string.pearl
            HighlightColor.Indigo -> R.string.indigo
            HighlightColor.Brown -> R.string.brown
        }

/**
 * Swift `HighlightEditor`: tapping a color saves (every selected verse takes it) and closes. A saved highlight
 * also has its note, saved as it's typed, and Delete. Failures offer Retry or Discard changes.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun HighlightEditorSheet(
    draft: HighlightDraft,
    colors: List<HighlightColor>,
    onSave: suspend (List<ReadingHighlight>) -> Unit,
    onDelete: suspend (ReadingHighlight) -> Unit,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    // Seeded once; later store updates never overwrite what's being edited.
    var current by remember { mutableStateOf(draft.highlights.first()) }
    var saved by remember { mutableStateOf(if (draft.existing) current else null) }
    var pending by remember { mutableStateOf<(suspend () -> Unit)?>(null) }
    var failed by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }

    fun run(
        dismiss: Boolean,
        action: suspend () -> Unit,
    ) {
        scope.launch {
            try {
                action()
                failed = false
                if (dismiss) onDismiss()
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Exception) {
                pending = action
                failed = true
            }
        }
    }

    fun save(
        value: ReadingHighlight,
        dismiss: Boolean,
    ) {
        if (value == saved) {
            if (dismiss) onDismiss()
            return
        }
        val batch = listOf(value) + draft.highlights.drop(1).map { it.copy(color = value.color, note = value.note) }
        run(dismiss) {
            onSave(batch)
            saved = value
        }
    }

    if (draft.existing) {
        // The note saves as it's typed, after a short pause.
        LaunchedEffect(current.note) {
            delay(400)
            save(current, dismiss = false)
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                for (color in colors) {
                    HighlightSwatch(color, selected = color == current.color) {
                        current = current.copy(color = color)
                        save(current, dismiss = true)
                    }
                }
            }
            if (draft.existing) {
                OutlinedTextField(
                    value = current.note,
                    onValueChange = { current = current.copy(note = it) },
                    placeholder = { Text(stringResource(R.string.add_note)) },
                    label = { Text(stringResource(R.string.highlight_note)) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 100.dp).testTag("highlight-note-editor"),
                )
                Row {
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { confirmingDelete = true }, Modifier.testTag("highlight-delete")) {
                        Icon(
                            Icons.Outlined.Delete,
                            stringResource(R.string.delete_highlight),
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }
        }
    }
    if (confirmingDelete) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text(stringResource(R.string.delete_this_highlight)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingDelete = false
                    run(dismiss = true) { onDelete(current) }
                }) { Text(stringResource(R.string.delete_highlight), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(
                    onClick = { confirmingDelete = false },
                ) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
    if (failed) {
        AlertDialog(
            onDismissRequest = {},
            title = { Text(stringResource(R.string.unable_to_save)) },
            text = { Text(stringResource(R.string.please_try_again)) },
            confirmButton = {
                TextButton(
                    onClick = { pending?.let { run(dismiss = true, it) } },
                ) { Text(stringResource(R.string.retry)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    failed = false
                    onDismiss()
                }) { Text(stringResource(R.string.discard_changes)) }
            },
        )
    }
}

/** Swift `HighlightSwatch`: a 36 dp circle in a 44 dp target, checked when selected. */
@Composable
fun HighlightSwatch(
    color: HighlightColor,
    selected: Boolean,
    modifier: Modifier = Modifier,
    size: Int = 36,
    onClick: (() -> Unit)? = null,
) {
    val label = stringResource(color.title)
    Box(
        modifier
            .size(44.dp)
            .then(
                if (onClick != null) {
                    Modifier.selectable(selected, role = Role.RadioButton, onClick = onClick)
                } else {
                    Modifier
                },
            ).semantics { contentDescription = label }
            .testTag("highlight-color-${color.serialName}"),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(size.dp)
                .clip(CircleShape)
                .background(Color(highlightSwatch(color)))
                .then(
                    if (selected) Modifier.border(2.dp, MaterialTheme.colorScheme.onSurface, CircleShape) else Modifier,
                ),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) {
                Icon(Icons.Outlined.Check, null, tint = if (highlightSwatchIsDark(color)) Color.White else Color.Black)
            }
        }
    }
}

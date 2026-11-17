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
import kotlinx.coroutines.Job
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

/** The editor's in-flight autosave, so a close, color change or delete can wait for it. */
private class Autosave {
    var job: Job? = null
}

/**
 * Swift `HighlightEditor`: tapping a color saves (every selected verse takes it) and closes. A saved highlight
 * also has its note, saved as it's typed, and Delete; closing it any way (back, swipe, tap outside) saves the
 * latest note first. Writes run one at a time; failures offer Retry or Discard changes.
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
    // A close, color change or delete is under way (or failed and awaiting Retry/Discard): autosave pauses and
    // the editor stops taking input until the sheet goes away.
    var closing by remember { mutableStateOf(false) }
    val autosave = remember { Autosave() }

    suspend fun write(value: ReadingHighlight) {
        if (value == saved) return
        onSave(listOf(value) + draft.highlights.drop(1).map { it.copy(color = value.color, note = value.note) })
        saved = value
    }

    /** Runs [action] and closes, or offers Retry/Discard. Only called once [closing] is set. */
    suspend fun attempt(action: suspend () -> Unit) {
        try {
            action()
            onDismiss()
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Exception) {
            pending = action
            failed = true
        }
    }

    /** The last write: waits for any running autosave so writes never overlap or land out of order. */
    fun close(action: suspend () -> Unit) {
        if (closing) return
        closing = true
        scope.launch {
            autosave.job?.join()
            attempt(action)
        }
    }

    // Reads `current` when it runs, so it always saves the latest draft.
    val saveLatest: suspend () -> Unit = { write(current) }

    if (draft.existing) {
        // The note saves as it's typed, after a short pause. Restarting on `closing` drops a pending pause.
        LaunchedEffect(current.note, closing) {
            if (closing) return@LaunchedEffect
            delay(400)
            autosave.job?.join()
            // A close may have started while this was waiting; it saves the latest draft itself.
            if (closing || current == saved) return@LaunchedEffect
            autosave.job =
                scope.launch {
                    try {
                        write(current)
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (_: Exception) {
                        // A waiting close retries and reports on its own.
                        if (!closing) {
                            closing = true
                            pending = { saveLatest() }
                            failed = true
                        }
                    }
                }
        }
    }

    ModalBottomSheet(
        onDismissRequest = {
            // A new highlight without a color is just discarded; once a color is saving, that save closes.
            when {
                draft.existing -> close(saveLatest)
                !closing -> onDismiss()
            }
        },
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                for (color in colors) {
                    HighlightSwatch(color, selected = color == current.color, enabled = !closing) {
                        current = current.copy(color = color)
                        close(saveLatest)
                    }
                }
            }
            if (draft.existing) {
                OutlinedTextField(
                    value = current.note,
                    onValueChange = { current = current.copy(note = it) },
                    enabled = !closing,
                    placeholder = { Text(stringResource(R.string.add_note)) },
                    label = { Text(stringResource(R.string.highlight_note)) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 100.dp).testTag("highlight-note-editor"),
                )
                Row {
                    Spacer(Modifier.weight(1f))
                    IconButton(
                        onClick = { confirmingDelete = true },
                        Modifier.testTag("highlight-delete"),
                        enabled = !closing,
                    ) {
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
                    close { onDelete(current) }
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
                    onClick = {
                        val action = pending ?: return@TextButton
                        failed = false
                        scope.launch { attempt(action) }
                    },
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
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
) {
    val label = stringResource(color.title)
    Box(
        modifier
            .size(44.dp)
            .then(
                if (onClick != null) {
                    Modifier.selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = onClick)
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

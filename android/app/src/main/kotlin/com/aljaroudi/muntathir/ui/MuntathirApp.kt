package com.aljaroudi.muntathir.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppError
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.ui.components.message
import com.aljaroudi.muntathir.ui.shell.AppShell
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

@HiltViewModel
class MainViewModel
    @Inject
    constructor(
        model: AppModel,
    ) : ViewModel() {
        val state: StateFlow<AppState> = model.state
        val errors: SharedFlow<AppError> = model.errors
    }

/** App root: the shell, plus Swift `ContentView`'s "Unable to update" alert for rejected changes. */
@Composable
fun MuntathirApp(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    AppShell(state.preferences.tabShortcuts, modifier)
    ErrorDialog(viewModel.errors)
}

@Composable
private fun ErrorDialog(errors: SharedFlow<AppError>) {
    var shown by rememberSaveable { mutableStateOf<Int?>(null) }
    LaunchedEffect(errors) { errors.collect { shown = it.message() } }
    val message = shown ?: return
    AlertDialog(
        onDismissRequest = { shown = null },
        confirmButton = { TextButton(onClick = { shown = null }) { Text(stringResource(R.string.ok)) } },
        title = { Text(stringResource(R.string.unable_to_update)) },
        text = { Text(stringResource(message)) },
    )
}

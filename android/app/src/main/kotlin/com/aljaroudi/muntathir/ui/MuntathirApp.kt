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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppError
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.data.QuranTranslations
import com.aljaroudi.muntathir.data.library.ContentLibraries
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.ui.components.message
import com.aljaroudi.muntathir.ui.navigation.OpenRequest
import com.aljaroudi.muntathir.ui.onboarding.OnboardingScreen
import com.aljaroudi.muntathir.ui.shell.AppShell
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class MainViewModel
    @Inject
    constructor(
        private val model: AppModel,
        private val locator: DeviceLocator,
        private val translations: QuranTranslations,
        private val libraries: ContentLibraries,
    ) : ViewModel() {
        val state: StateFlow<AppState> = model.state
        val errors: SharedFlow<AppError> = model.errors

        /** Kept until the shell shows it, so a request made during onboarding opens afterwards. */
        private val pendingOpen = MutableStateFlow<OpenRequest?>(null)
        val openRequest: StateFlow<OpenRequest?> = pendingOpen

        fun open(request: OpenRequest) {
            pendingOpen.value = request
        }

        fun opened() {
            pendingOpen.value = null
        }

        /** Swift scene-phase `.active`: follow the device to a new place while location access stays granted. */
        fun onForeground() {
            // Swift scene activation: finish interrupted translation downloads and follow language changes.
            translations.onForeground()
            // The supplications pack is fast-follow (iOS: essential), so it starts with the app.
            libraries.supplications
            libraries.onForeground()
            viewModelScope.launch {
                followDevice()
                // Swift launch refresh: the corrections feed on every activation.
                model.refreshFeed()
            }
        }

        fun onBackground() = libraries.onBackground()

        private suspend fun followDevice() {
            val current = model.state.value.device.liveLocation ?: return
            if (!locator.hasPermission()) return
            val fix = locator.locate() ?: return
            if (fix.timeZoneID != current.timeZoneID || distanceKm(fix, current) > MOVED_KM) model.applyLive(fix)
        }

        private fun distanceKm(
            a: SavedLocation,
            b: SavedLocation,
        ): Double {
            val results = FloatArray(1)
            android.location.Location.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude, results)
            return results[0] / 1000.0
        }

        private companion object {
            /** Prayer times shift by about a minute per 15–20 km; ignore jitter between fixes. */
            const val MOVED_KM = 5.0
        }
    }

/** App root: the shell, plus Swift `ContentView`'s "Unable to update" alert for rejected changes. */
@Composable
fun MuntathirApp(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val openRequest by viewModel.openRequest.collectAsStateWithLifecycle()
    LifecycleEventEffect(Lifecycle.Event.ON_START) { viewModel.onForeground() }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { viewModel.onBackground() }
    ReleaseNotesPrompt(state.device.onboardingCompleted)
    if (state.device.onboardingCompleted) {
        AppShell(state.preferences.tabShortcuts, modifier, openRequest = openRequest, onOpened = viewModel::opened)
    } else {
        OnboardingScreen(modifier)
    }
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

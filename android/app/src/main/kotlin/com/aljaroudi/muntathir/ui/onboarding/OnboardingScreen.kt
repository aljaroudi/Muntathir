package com.aljaroudi.muntathir.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.ModeNight
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.ui.components.rememberNotificationPermission
import com.aljaroudi.muntathir.ui.components.title
import com.aljaroudi.muntathir.ui.location.DeviceLocationSection
import com.aljaroudi.muntathir.ui.settings.AppLanguageRow
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class OnboardingViewModel
    @Inject
    constructor(
        private val model: AppModel,
    ) : ViewModel() {
        val state: StateFlow<AppState> = model.state

        fun move(by: Int) = viewModelScope.launch { model.moveOnboarding(by) }

        fun setMethod(method: PrayerMethod) = viewModelScope.launch { model.update { it.copy(prayerMethod = method) } }

        fun complete() = viewModelScope.launch { model.completeOnboarding() }
    }

/** Swift `OnboardingView`: five steps, persisted on every move so setup resumes after a restart. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingScreen(
    modifier: Modifier = Modifier,
    viewModel: OnboardingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val step = state.device.onboardingStep
    var requesting by rememberSaveable { mutableStateOf(false) }
    var denied by rememberSaveable { mutableStateOf(false) }
    val requestNotifications =
        rememberNotificationPermission { allowed ->
            requesting = false
            if (allowed) viewModel.complete() else denied = true
        }
    BackHandler(enabled = step > 0) { viewModel.move(-1) }
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.set_up_muntathir)) },
                navigationIcon = {
                    if (step > 0) {
                        IconButton(
                            onClick = { viewModel.move(-1) },
                            enabled = !requesting,
                            modifier = Modifier.testTag("onboarding-back"),
                        ) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back))
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                val count = DeviceState.STEPS.last + 1
                Text(
                    stringResource(R.string.step_x_of_x, "${step + 1}", "$count"),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                LinearProgressIndicator(progress = { (step + 1f) / count }, Modifier.fillMaxWidth())
                when (step) {
                    0 -> {
                        Welcome()
                    }

                    1 -> {
                        Heading(R.string.choose_your_app_language)
                        AppLanguageRow()
                    }

                    2 -> {
                        Heading(R.string.choose_your_location)
                        Text(stringResource(R.string.use_your_device_location_to_calculate_prayer_times))
                        DeviceLocationSection(hiltViewModel())
                    }

                    3 -> {
                        Heading(R.string.prayer_calculations)
                        Text(stringResource(R.string.choose_the_calculation_method_you_follow_you_can))
                        MethodPicker(state.preferences.prayerMethod, viewModel::setMethod)
                    }

                    else -> {
                        Heading(R.string.prayer_reminders)
                        Text(stringResource(R.string.enable_notifications_for_your_selected_prayers_y))
                        if (denied) {
                            Text(stringResource(R.string.notifications_are_disabled_enable_them_in_system))
                            Button(onClick = viewModel::complete, Modifier.testTag("onboarding-finish")) {
                                Text(stringResource(R.string.finish_setup))
                            }
                        } else {
                            Button(onClick = {
                                requesting = true
                                requestNotifications()
                            }, enabled = !requesting) { Text(stringResource(R.string.enable_notifications)) }
                            TextButton(
                                onClick = viewModel::complete,
                                enabled = !requesting,
                                modifier = Modifier.testTag("onboarding-finish"),
                            ) {
                                Text(stringResource(R.string.not_now))
                            }
                        }
                    }
                }
                if (step < DeviceState.STEPS.last) {
                    Button(
                        onClick = { viewModel.move(1) },
                        enabled = step != 2 || state.location?.isValid == true,
                        modifier = Modifier.testTag("onboarding-continue"),
                    ) { Text(stringResource(if (step == 0) R.string.get_started else R.string.continue_text)) }
                }
            }
        }
    }
}

@Composable
private fun Heading(text: Int) {
    Text(
        stringResource(text),
        style = MaterialTheme.typography.headlineMedium,
        modifier = Modifier.semantics { heading() },
    )
}

@Composable
private fun Welcome() {
    Icon(Icons.Outlined.ModeNight, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
    Text(
        stringResource(R.string.welcome_to_muntathir),
        style = MaterialTheme.typography.headlineLarge,
        modifier = Modifier.semantics { heading() },
    )
    Text(stringResource(R.string.a_companion_for_your_daily_worship))
    Feature(Icons.Outlined.WbSunny, R.string.prayer_times_for_your_location)
    Feature(Icons.Outlined.CalendarMonth, R.string.hijri_calendar_and_observances)
    Feature(Icons.Outlined.Explore, R.string.find_the_direction_of_qibla)
}

@Composable
private fun Feature(
    icon: ImageVector,
    text: Int,
) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(stringResource(text))
    }
}

@Composable
fun MethodPicker(
    selected: PrayerMethod,
    onSelect: (PrayerMethod) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.selectableGroup()) {
        PrayerMethod.entries.forEach { method ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .selectable(selected = method == selected, role = Role.RadioButton) { onSelect(method) }
                    .padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                RadioButton(selected = method == selected, onClick = null)
                Text(stringResource(method.title))
            }
        }
    }
}

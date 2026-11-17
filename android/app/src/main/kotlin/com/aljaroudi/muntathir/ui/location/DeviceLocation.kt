package com.aljaroudi.muntathir.ui.location

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.MyLocation
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.currentLocale
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class LocateStatus { Idle, Locating, Denied, Failed }

@HiltViewModel
class DeviceLocationViewModel
    @Inject
    constructor(
        private val model: AppModel,
        private val locator: DeviceLocator,
    ) : ViewModel() {
        val location: StateFlow<SavedLocation?> =
            model.state.map { it.location }.stateIn(viewModelScope, SharingStarted.Eagerly, model.state.value.location)

        private val mutableStatus = MutableStateFlow(LocateStatus.Idle)
        val status: StateFlow<LocateStatus> = mutableStatus.asStateFlow()

        fun onPermission(granted: Boolean) {
            if (!granted) {
                mutableStatus.value = LocateStatus.Denied
                return
            }
            if (mutableStatus.value == LocateStatus.Locating) return
            mutableStatus.value = LocateStatus.Locating
            viewModelScope.launch {
                val fix = locator.locate()
                mutableStatus.value =
                    if (fix != null && model.applyLive(fix)) LocateStatus.Idle else LocateStatus.Failed
            }
        }
    }

/**
 * Swift `LocationPicker`, GPS only: asks for coarse location, takes one fix and stores it on this device.
 * Shows the current place, progress and the iOS failure messages (without the city-search fallback).
 */
@Composable
fun DeviceLocationSection(
    viewModel: DeviceLocationViewModel,
    modifier: Modifier = Modifier,
) {
    val location by viewModel.location.collectAsStateWithLifecycle()
    val status by viewModel.status.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val permission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission(), viewModel::onPermission)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        FilledTonalButton(
            onClick = { permission.launch(Manifest.permission.ACCESS_COARSE_LOCATION) },
            enabled = status != LocateStatus.Locating,
            modifier = Modifier.testTag("use-device-location"),
        ) {
            if (status == LocateStatus.Locating) {
                CircularProgressIndicator(Modifier.size(ButtonDefaults.IconSize), strokeWidth = 2.dp)
            } else {
                Icon(Icons.Outlined.MyLocation, contentDescription = null, Modifier.size(ButtonDefaults.IconSize))
            }
            Text(
                stringResource(if (location == null) R.string.use_device_location else R.string.update_location),
                Modifier.padding(start = ButtonDefaults.IconSpacing),
            )
        }
        location?.let { location ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text(Formats.place(location, currentLocale()), Modifier.testTag("location-name"))
            }
        }
        when (status) {
            LocateStatus.Denied -> {
                Text(
                    stringResource(R.string.location_access_is_disabled_allow_it_in_settings),
                    color = MaterialTheme.colorScheme.error,
                )
                TextButton(onClick = {
                    context.startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", context.packageName, null),
                        ),
                    )
                }) { Text(stringResource(R.string.open_settings)) }
            }

            LocateStatus.Failed -> {
                Text(
                    stringResource(R.string.could_not_find_your_location_try_again),
                    color = MaterialTheme.colorScheme.error,
                )
            }

            else -> {
                Unit
            }
        }
    }
}

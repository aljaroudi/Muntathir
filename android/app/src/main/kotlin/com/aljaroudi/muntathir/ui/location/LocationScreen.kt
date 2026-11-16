package com.aljaroudi.muntathir.ui.location

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.components.ScreenScaffold

/** Location from Today's empty state or Settings. */
@Composable
fun LocationScreen(
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    ScreenScaffold(R.string.location, modifier, onBack) { padding ->
        Column(Modifier.padding(padding).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(stringResource(R.string.use_your_device_location_to_calculate_prayer_times))
            DeviceLocationSection(hiltViewModel())
            Text(
                stringResource(R.string.device_location_stays_on_this_device),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

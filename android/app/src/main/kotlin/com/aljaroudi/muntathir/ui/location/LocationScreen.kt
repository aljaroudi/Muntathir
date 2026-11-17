package com.aljaroudi.muntathir.ui.location

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
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
        DeviceLocationSection(hiltViewModel(), Modifier.padding(padding).padding(24.dp))
    }
}

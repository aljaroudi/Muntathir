package com.aljaroudi.muntathir.ui.qibla

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.shell.ComingSoonScreen

/** Swift `QiblaView` (P5.1). */
@Composable
fun QiblaScreen(onBack: (() -> Unit)?) {
    ComingSoonScreen(stringResource(R.string.qibla), onBack)
}

package com.aljaroudi.muntathir.ui.activity

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.shell.ComingSoonScreen

/** Swift `ActivityProgressView` (P5.5). */
@Composable
fun ActivityScreen(onBack: (() -> Unit)?) {
    ComingSoonScreen(stringResource(R.string.activity), onBack)
}

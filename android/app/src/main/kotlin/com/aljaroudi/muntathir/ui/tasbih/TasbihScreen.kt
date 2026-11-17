package com.aljaroudi.muntathir.ui.tasbih

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.shell.ComingSoonScreen

/** Swift `TasbihView` (P5.3). */
@Composable
fun TasbihScreen(onBack: (() -> Unit)?) {
    ComingSoonScreen(stringResource(R.string.tasbih), onBack)
}

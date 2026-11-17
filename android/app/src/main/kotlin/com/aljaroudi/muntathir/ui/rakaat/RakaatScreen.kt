package com.aljaroudi.muntathir.ui.rakaat

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.navigation.RakaatSessionRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import com.aljaroudi.muntathir.ui.shell.ComingSoonScreen

/** Swift `RakaatTrackerView` (P5.2): choose rakaat and prayer, then open a [RakaatSessionRoute]. */
@Composable
fun RakaatScreen(
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    ComingSoonScreen(stringResource(R.string.rakaat_tracker), onBack)
}

/** Swift `RakaatSessionView` (P5.2). */
@Composable
fun RakaatSessionScreen(
    route: RakaatSessionRoute,
    open: (Route) -> Unit,
    onBack: () -> Unit,
) {
    ComingSoonScreen(stringResource(R.string.rakaat_tracker), onBack)
}

package com.aljaroudi.muntathir.ui.figures

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.ui.navigation.FigurePickerRoute
import com.aljaroudi.muntathir.ui.navigation.FigureProfileRoute
import com.aljaroudi.muntathir.ui.navigation.FigureTreeRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import com.aljaroudi.muntathir.ui.shell.ComingSoonScreen

/** Swift `FigureBrowser` (P5.4), the list pane. */
@Composable
fun FiguresScreen(
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    ComingSoonScreen(stringResource(R.string.figures), onBack)
}

/** Swift `FigureProfile` (P5.4), a detail pane. */
@Composable
fun FigureProfileScreen(
    route: FigureProfileRoute,
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    ComingSoonScreen(stringResource(R.string.figures), onBack)
}

/** Swift `FigureFamilyTree` (P5.4), a detail pane. */
@Composable
fun FigureTreeScreen(
    route: FigureTreeRoute,
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    ComingSoonScreen(stringResource(R.string.figures), onBack)
}

/** Swift `ObservanceFigurePicker` (P5.4), a detail pane. */
@Composable
fun FigurePickerScreen(
    route: FigurePickerRoute,
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
) {
    ComingSoonScreen(stringResource(R.string.figures), onBack)
}

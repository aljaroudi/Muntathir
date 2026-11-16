package com.aljaroudi.muntathir.ui.shell

import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.navigation3.ListDetailSceneStrategy
import androidx.compose.material3.adaptive.navigation3.rememberListDetailSceneStrategy
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.ui.NavDisplay
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.ui.components.isTwoPane
import com.aljaroudi.muntathir.ui.location.LocationScreen
import com.aljaroudi.muntathir.ui.navigation.AppNavigator
import com.aljaroudi.muntathir.ui.navigation.CreditsRoute
import com.aljaroudi.muntathir.ui.navigation.DownloadsRoute
import com.aljaroudi.muntathir.ui.navigation.LocationRoute
import com.aljaroudi.muntathir.ui.navigation.MonthAdjustmentsRoute
import com.aljaroudi.muntathir.ui.navigation.SettingsRoute
import com.aljaroudi.muntathir.ui.navigation.TabsSettingsRoute
import com.aljaroudi.muntathir.ui.navigation.TodayRoute
import com.aljaroudi.muntathir.ui.navigation.ToolRoute
import com.aljaroudi.muntathir.ui.navigation.ToolsRoute
import com.aljaroudi.muntathir.ui.navigation.rememberAppNavigator
import com.aljaroudi.muntathir.ui.navigation.tabIcon
import com.aljaroudi.muntathir.ui.navigation.tabTitle
import com.aljaroudi.muntathir.ui.navigation.tabs
import com.aljaroudi.muntathir.ui.navigation.testTag
import com.aljaroudi.muntathir.ui.navigation.title

/** Today, up to three tool shortcuts and Tools; a bar on phones, a rail on larger windows. */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun AppShell(
    shortcuts: List<AppTool>,
    modifier: Modifier = Modifier,
    navigator: AppNavigator = rememberAppNavigator(),
) {
    val tabs = tabs(shortcuts)
    LaunchedEffect(tabs) { navigator.keepAvailable(tabs) }
    val listDetail = rememberListDetailSceneStrategy<NavKey>()
    val twoPane = isTwoPane()
    // Detail panes beside their list have no Up button.
    val detailBack: (() -> Unit)? = if (twoPane) null else navigator::back

    NavigationSuiteScaffold(
        modifier = modifier,
        navigationSuiteItems = {
            tabs.forEach { tab ->
                item(
                    selected = tab == navigator.tab,
                    onClick = { navigator.select(tab) },
                    icon = { Icon(tab.tabIcon, contentDescription = null) },
                    label = { Text(stringResource(tab.tabTitle)) },
                    modifier = Modifier.testTag("tab-${tab.testTag}"),
                )
            }
        },
    ) {
        NavDisplay(
            entries =
                navigator.entries(
                    entryProvider {
                        entry<TodayRoute> {
                            ComingSoonScreen(stringResource(TodayRoute.tabTitle), null)
                        }
                        entry<ToolsRoute> {
                            ToolsScreen(
                                shortcuts = shortcuts,
                                onOpen = { navigator.push(ToolRoute(it)) },
                                onSettings = { navigator.push(SettingsRoute) },
                            )
                        }
                        entry<ToolRoute> { route ->
                            // A tool is a tab root only when it is the selected tab itself.
                            ToolScreen(route.tool, onBack = navigator::back.takeIf { route != navigator.tab })
                        }
                        entry<SettingsRoute>(metadata = ListDetailSceneStrategy.listPane()) {
                            ComingSoonScreen(stringResource(com.aljaroudi.muntathir.R.string.settings), navigator::back)
                        }
                        entry<TabsSettingsRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                            TabsSettingsScreen(hiltViewModel(), detailBack)
                        }
                        entry<MonthAdjustmentsRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                            ComingSoonScreen(
                                stringResource(com.aljaroudi.muntathir.R.string.month_adjustments),
                                detailBack,
                            )
                        }
                        entry<DownloadsRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                            ComingSoonScreen(stringResource(com.aljaroudi.muntathir.R.string.downloads), detailBack)
                        }
                        entry<CreditsRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                            ComingSoonScreen(stringResource(com.aljaroudi.muntathir.R.string.app_name), detailBack)
                        }
                        entry<LocationRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                            LocationScreen(onBack = detailBack ?: navigator::back)
                        }
                    },
                ),
            onBack = navigator::back,
            sceneStrategies = listOf(listDetail),
        )
    }
}

/** A tool as a tab root (no Up button) or pushed from Tools/Today. Swift `ToolDestination`. */
@Composable
private fun ToolScreen(
    tool: AppTool,
    onBack: (() -> Unit)?,
) {
    when (tool) {
        else -> ComingSoonScreen(stringResource(tool.title), onBack)
    }
}

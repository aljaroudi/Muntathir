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
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.ui.NavDisplay
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.ui.calendar.CalendarScreen
import com.aljaroudi.muntathir.ui.calendar.EventsScreen
import com.aljaroudi.muntathir.ui.calendar.EventsViewModel
import com.aljaroudi.muntathir.ui.calendar.MonthAdjustmentsScreen
import com.aljaroudi.muntathir.ui.components.isTwoPane
import com.aljaroudi.muntathir.ui.location.LocationScreen
import com.aljaroudi.muntathir.ui.navigation.AppNavigator
import com.aljaroudi.muntathir.ui.navigation.CreditsRoute
import com.aljaroudi.muntathir.ui.navigation.DownloadsRoute
import com.aljaroudi.muntathir.ui.navigation.LocationRoute
import com.aljaroudi.muntathir.ui.navigation.MonthAdjustmentsRoute
import com.aljaroudi.muntathir.ui.navigation.QuranReaderRoute
import com.aljaroudi.muntathir.ui.navigation.Route
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
import com.aljaroudi.muntathir.ui.quran.QuranReaderScreen
import com.aljaroudi.muntathir.ui.quran.QuranReaderViewModel
import com.aljaroudi.muntathir.ui.quran.QuranScreen
import com.aljaroudi.muntathir.ui.settings.CreditsScreen
import com.aljaroudi.muntathir.ui.settings.SettingsLinks
import com.aljaroudi.muntathir.ui.settings.SettingsScreen
import com.aljaroudi.muntathir.ui.today.TodayScreen

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
    // Beside the surah list, another surah replaces the open one rather than stacking.
    val openReader: (QuranReaderRoute) -> Unit = { route ->
        if (twoPane && navigator.current.lastOrNull() is QuranReaderRoute) {
            navigator.current.removeAt(navigator.current.lastIndex)
        }
        navigator.push(route)
    }

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
                    listPanes(
                        entryProvider {
                            entry<TodayRoute> {
                                TodayScreen(
                                    hiltViewModel(),
                                    onChooseLocation = { navigator.push(LocationRoute) },
                                    onOpenCalendar = {
                                        val calendar = ToolRoute(AppTool.Calendar)
                                        if (calendar in tabs) navigator.select(calendar) else navigator.push(calendar)
                                    },
                                )
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
                                ToolScreen(
                                    route.tool,
                                    onBack = navigator::back.takeIf { route != navigator.tab },
                                    openReader,
                                )
                            }
                            entry<QuranReaderRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                QuranReaderScreen(
                                    hiltViewModel<QuranReaderViewModel, QuranReaderViewModel.Factory>(
                                        creationCallback = { it.create(route) },
                                    ),
                                    detailBack,
                                )
                            }
                            entry<SettingsRoute>(metadata = ListDetailSceneStrategy.listPane()) {
                                // A detail opened from Settings replaces the one beside it rather than stacking.
                                val open: (Route) -> Unit = { route ->
                                    if (navigator.current.lastOrNull() in
                                        SETTINGS_DETAILS
                                    ) {
                                        navigator.current.removeAt(navigator.current.lastIndex)
                                    }
                                    navigator.push(route)
                                }
                                SettingsScreen(
                                    hiltViewModel(),
                                    SettingsLinks(
                                        onTabs = { open(TabsSettingsRoute) },
                                        onDownloads = { open(DownloadsRoute) },
                                        onLocation = { open(LocationRoute) },
                                        onMonthAdjustments = { open(MonthAdjustmentsRoute) },
                                        onCredits = { open(CreditsRoute) },
                                    ),
                                    navigator::back,
                                )
                            }
                            entry<TabsSettingsRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                TabsSettingsScreen(hiltViewModel(), detailBack)
                            }
                            entry<MonthAdjustmentsRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                MonthAdjustmentsScreen(hiltViewModel(), detailBack)
                            }
                            entry<DownloadsRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                ComingSoonScreen(stringResource(com.aljaroudi.muntathir.R.string.downloads), detailBack)
                            }
                            entry<CreditsRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                CreditsScreen(detailBack)
                            }
                            entry<LocationRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                LocationScreen(onBack = detailBack ?: navigator::back)
                            }
                        },
                    ),
                ),
            onBack = navigator::back,
            sceneStrategies = listOf(listDetail),
        )
    }
}

private val SETTINGS_DETAILS =
    setOf(TabsSettingsRoute, DownloadsRoute, LocationRoute, MonthAdjustmentsRoute, CreditsRoute)

/** Tools whose root lists items for a detail pane beside it. */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
private fun listPanes(provider: (NavKey) -> NavEntry<NavKey>): (NavKey) -> NavEntry<NavKey> =
    { key ->
        val entry = provider(key)
        if (key == ToolRoute(AppTool.Quran)) {
            NavEntry(key, entry.contentKey, ListDetailSceneStrategy.listPane()) { entry.Content() }
        } else {
            entry
        }
    }

/** A tool as a tab root (no Up button) or pushed from Tools/Today. Swift `ToolDestination`. */
@Composable
private fun ToolScreen(
    tool: AppTool,
    onBack: (() -> Unit)?,
    openReader: (QuranReaderRoute) -> Unit,
) {
    when (tool) {
        AppTool.Quran -> QuranScreen(hiltViewModel(), openReader, onBack)
        AppTool.Calendar -> CalendarScreen(hiltViewModel(), onBack)
        AppTool.Events -> EventsScreen(hiltViewModel<EventsViewModel>().library, onBack)
        else -> ComingSoonScreen(stringResource(tool.title), onBack)
    }
}

package com.aljaroudi.muntathir.ui.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.layout.PaneScaffoldDirective
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.material3.adaptive.navigation.BackNavigationBehavior
import androidx.compose.material3.adaptive.navigation3.ListDetailSceneStrategy
import androidx.compose.material3.adaptive.navigation3.rememberListDetailSceneStrategy
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.ui.NavDisplay
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.ui.activity.ActivityScreen
import com.aljaroudi.muntathir.ui.calendar.CalendarScreen
import com.aljaroudi.muntathir.ui.calendar.EventsScreen
import com.aljaroudi.muntathir.ui.calendar.EventsViewModel
import com.aljaroudi.muntathir.ui.calendar.MonthAdjustmentsScreen
import com.aljaroudi.muntathir.ui.components.isTwoPane
import com.aljaroudi.muntathir.ui.downloads.DownloadsScreen
import com.aljaroudi.muntathir.ui.figures.FigurePickerScreen
import com.aljaroudi.muntathir.ui.figures.FigureProfileScreen
import com.aljaroudi.muntathir.ui.figures.FiguresScreen
import com.aljaroudi.muntathir.ui.hadith.HadithBrowseScreen
import com.aljaroudi.muntathir.ui.hadith.HadithBrowseViewModel
import com.aljaroudi.muntathir.ui.hadith.HadithDetailScreen
import com.aljaroudi.muntathir.ui.hadith.HadithDetailViewModel
import com.aljaroudi.muntathir.ui.hadith.HadithIntroductionScreen
import com.aljaroudi.muntathir.ui.hadith.HadithIntroductionViewModel
import com.aljaroudi.muntathir.ui.hadith.HadithSavedScreen
import com.aljaroudi.muntathir.ui.hadith.HadithSavedViewModel
import com.aljaroudi.muntathir.ui.hadith.HadithSessionStore
import com.aljaroudi.muntathir.ui.location.LocationScreen
import com.aljaroudi.muntathir.ui.navigation.AppNavigator
import com.aljaroudi.muntathir.ui.navigation.CreditsRoute
import com.aljaroudi.muntathir.ui.navigation.DetailRoute
import com.aljaroudi.muntathir.ui.navigation.DownloadsRoute
import com.aljaroudi.muntathir.ui.navigation.FigurePickerRoute
import com.aljaroudi.muntathir.ui.navigation.FigureProfileRoute
import com.aljaroudi.muntathir.ui.navigation.HadithBrowseRoute
import com.aljaroudi.muntathir.ui.navigation.HadithDetailRoute
import com.aljaroudi.muntathir.ui.navigation.HadithIntroductionRoute
import com.aljaroudi.muntathir.ui.navigation.HadithRoute
import com.aljaroudi.muntathir.ui.navigation.HadithSavedRoute
import com.aljaroudi.muntathir.ui.navigation.HighlightPaletteRoute
import com.aljaroudi.muntathir.ui.navigation.LocationRoute
import com.aljaroudi.muntathir.ui.navigation.MonthAdjustmentsRoute
import com.aljaroudi.muntathir.ui.navigation.OpenRequest
import com.aljaroudi.muntathir.ui.navigation.QuranReaderRoute
import com.aljaroudi.muntathir.ui.navigation.QuranSavedRoute
import com.aljaroudi.muntathir.ui.navigation.RakaatSessionRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import com.aljaroudi.muntathir.ui.navigation.RulingDetailRoute
import com.aljaroudi.muntathir.ui.navigation.RulingSectionRoute
import com.aljaroudi.muntathir.ui.navigation.RulingsSavedRoute
import com.aljaroudi.muntathir.ui.navigation.SermonRoute
import com.aljaroudi.muntathir.ui.navigation.SettingsRoute
import com.aljaroudi.muntathir.ui.navigation.TabsSettingsRoute
import com.aljaroudi.muntathir.ui.navigation.TodayRoute
import com.aljaroudi.muntathir.ui.navigation.ToolRoute
import com.aljaroudi.muntathir.ui.navigation.ToolsRoute
import com.aljaroudi.muntathir.ui.navigation.icon
import com.aljaroudi.muntathir.ui.navigation.rememberAppNavigator
import com.aljaroudi.muntathir.ui.navigation.tabIcon
import com.aljaroudi.muntathir.ui.navigation.tabTitle
import com.aljaroudi.muntathir.ui.navigation.tabs
import com.aljaroudi.muntathir.ui.navigation.testTag
import com.aljaroudi.muntathir.ui.qibla.QiblaScreen
import com.aljaroudi.muntathir.ui.quran.QuranReaderScreen
import com.aljaroudi.muntathir.ui.quran.QuranReaderViewModel
import com.aljaroudi.muntathir.ui.quran.QuranSavedScreen
import com.aljaroudi.muntathir.ui.quran.QuranScreen
import com.aljaroudi.muntathir.ui.rakaat.RakaatScreen
import com.aljaroudi.muntathir.ui.rakaat.RakaatSessionScreen
import com.aljaroudi.muntathir.ui.rulings.RulingDetailScreen
import com.aljaroudi.muntathir.ui.rulings.RulingDetailViewModel
import com.aljaroudi.muntathir.ui.rulings.RulingSectionScreen
import com.aljaroudi.muntathir.ui.rulings.RulingSectionViewModel
import com.aljaroudi.muntathir.ui.rulings.RulingsSavedScreen
import com.aljaroudi.muntathir.ui.rulings.RulingsScreen
import com.aljaroudi.muntathir.ui.sermons.SermonsScreen
import com.aljaroudi.muntathir.ui.settings.CreditsScreen
import com.aljaroudi.muntathir.ui.settings.HighlightPaletteScreen
import com.aljaroudi.muntathir.ui.settings.SettingsLinks
import com.aljaroudi.muntathir.ui.settings.SettingsScreen
import com.aljaroudi.muntathir.ui.supplications.SupplicationsScreen
import com.aljaroudi.muntathir.ui.tasbih.TasbihScreen
import com.aljaroudi.muntathir.ui.today.TodayScreen
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/** Today, up to three tool shortcuts and Tools; a bar on phones, a rail on larger windows. */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun AppShell(
    shortcuts: List<AppTool>,
    modifier: Modifier = Modifier,
    navigator: AppNavigator = rememberAppNavigator(),
    openRequest: OpenRequest? = null,
    onOpened: () -> Unit = {},
) {
    val tabs = tabs(shortcuts)
    LaunchedEffect(tabs) { navigator.keepAvailable(tabs) }
    LaunchedEffect(openRequest) {
        openRequest ?: return@LaunchedEffect
        navigator.open(openRequest.tool, tabs)
        onOpened()
    }
    // Back stops at the list: with a detail placeholder both panes stay shown, so the default (pop until the
    // panes change) would also pop the list and leave the tool.
    val listDetail =
        rememberListDetailSceneStrategy<NavKey>(
            backNavigationBehavior = BackNavigationBehavior.PopUntilContentChange,
            directive = paneDirective(),
        )
    val twoPane = isTwoPane()
    // Detail panes beside their list have no Up button.
    val detailBack: (() -> Unit)? = if (twoPane) null else navigator::back
    // Beside a list, a detail replaces the one open (and a new list closes it) rather than stacking.
    val open: (Route) -> Unit = { route ->
        if (twoPane) {
            while (navigator.current.lastOrNull() is DetailRoute) {
                navigator.current.removeAt(
                    navigator.current.lastIndex,
                )
            }
        }
        navigator.push(route)
    }
    val hadithSession = hiltViewModel<HadithShellViewModel>().session
    // Swift `HadithSession`: remember the hadith screens below the library for the next launch.
    LaunchedEffect(navigator) {
        snapshotFlow { navigator.current.toList() }.collect { stack ->
            val root = stack.indexOf(ToolRoute(AppTool.Hadith))
            if (root >= 0) hadithSession.save(stack.drop(root + 1).filterIsInstance<HadithRoute>())
        }
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
                                    open,
                                    onRestoreHadith = { routes -> routes.forEach(navigator::push) },
                                )
                            }
                            entry<QuranSavedRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                // Opening a saved verse replaces Saved beside the list, but stacks on phones.
                                QuranSavedScreen(hiltViewModel(), onOpen = { navigator.push(it) }, onBack = detailBack)
                            }
                            entry<HighlightPaletteRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                HighlightPaletteScreen(hiltViewModel(), detailBack)
                            }
                            entry<QuranReaderRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                QuranReaderScreen(
                                    hiltViewModel<QuranReaderViewModel, QuranReaderViewModel.Factory>(
                                        creationCallback = { it.create(route) },
                                    ),
                                    open,
                                    detailBack,
                                )
                            }
                            entry<HadithBrowseRoute> { route ->
                                HadithBrowseScreen(
                                    hiltViewModel<HadithBrowseViewModel, HadithBrowseViewModel.Factory>(
                                        creationCallback = { it.create(route, isRoot = false) },
                                    ),
                                    onOpen = open,
                                    onRestore = {},
                                    onBack = navigator::back,
                                )
                            }
                            entry<HadithDetailRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                HadithDetailScreen(
                                    hiltViewModel<HadithDetailViewModel, HadithDetailViewModel.Factory>(
                                        creationCallback = { it.create(route) },
                                    ),
                                    detailBack,
                                )
                            }
                            entry<HadithIntroductionRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                HadithIntroductionScreen(
                                    hiltViewModel<HadithIntroductionViewModel, HadithIntroductionViewModel.Factory>(
                                        creationCallback = { it.create(route) },
                                    ),
                                    detailBack,
                                )
                            }
                            entry<HadithSavedRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                HadithSavedScreen(
                                    hiltViewModel<HadithSavedViewModel, HadithSavedViewModel.Factory>(
                                        creationCallback = { it.create(route) },
                                    ),
                                    onOpen = { navigator.push(it) },
                                    onBack = detailBack,
                                )
                            }
                            entry<SermonRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                SermonsScreen(route.id, onBack = detailBack, open = { navigator.push(it) })
                            }
                            entry<RulingDetailRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                RulingDetailScreen(
                                    hiltViewModel<RulingDetailViewModel, RulingDetailViewModel.Factory>(
                                        creationCallback = { it.create(route) },
                                    ),
                                    onOpen = { navigator.push(it) },
                                    onBack = detailBack,
                                )
                            }
                            entry<RulingSectionRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                RulingSectionScreen(
                                    hiltViewModel<RulingSectionViewModel, RulingSectionViewModel.Factory>(
                                        creationCallback = { it.create(route) },
                                    ),
                                    onOpen = { navigator.push(it) },
                                    onBack = detailBack ?: navigator::back,
                                )
                            }
                            entry<RulingsSavedRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                RulingsSavedScreen(
                                    hiltViewModel(),
                                    onOpen = { navigator.push(it) },
                                    onBack = detailBack,
                                )
                            }
                            entry<SettingsRoute>(
                                metadata =
                                    ListDetailSceneStrategy.listPane(
                                        detailPlaceholder = { DetailPlaceholder(Icons.Outlined.Settings) },
                                    ),
                            ) {
                                SettingsScreen(
                                    hiltViewModel(),
                                    SettingsLinks(
                                        onTabs = { open(TabsSettingsRoute) },
                                        onHighlightColors = { open(HighlightPaletteRoute) },
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
                                DownloadsScreen(hiltViewModel(), detailBack)
                            }
                            entry<CreditsRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                CreditsScreen(detailBack)
                            }
                            entry<LocationRoute>(metadata = ListDetailSceneStrategy.detailPane()) {
                                LocationScreen(onBack = detailBack ?: navigator::back)
                            }
                            entry<RakaatSessionRoute> { route ->
                                RakaatSessionScreen(route, open, navigator::back)
                            }
                            entry<FigureProfileRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                FigureProfileScreen(route, open, detailBack)
                            }
                            entry<FigurePickerRoute>(metadata = ListDetailSceneStrategy.detailPane()) { route ->
                                FigurePickerScreen(route, open, detailBack)
                            }
                        },
                    ),
                ),
            onBack = navigator::back,
            sceneStrategies = listOf(listDetail),
        )
    }
}

private val LIST_TOOLS =
    setOf(
        ToolRoute(AppTool.Quran),
        ToolRoute(AppTool.Hadith),
        ToolRoute(AppTool.Supplications),
        ToolRoute(AppTool.Sermons),
        ToolRoute(AppTool.Rulings),
        ToolRoute(AppTool.Figures),
    )

/** Holds app-wide stores the shell needs outside any screen. */
@HiltViewModel
class HadithShellViewModel
    @Inject
    constructor(
        val session: HadithSessionStore,
    ) : ViewModel()

/**
 * The default pane directive without moving focus to each newly shown pane: focusing a list pane lands on its
 * search field and opens the on-screen keyboard. Tab still moves between panes.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
private fun paneDirective(): PaneScaffoldDirective {
    val base = calculatePaneScaffoldDirective(currentWindowAdaptiveInfoV2())
    return PaneScaffoldDirective(
        maxHorizontalPartitions = base.maxHorizontalPartitions,
        horizontalPartitionSpacerSize = base.horizontalPartitionSpacerSize,
        maxVerticalPartitions = base.maxVerticalPartitions,
        verticalPartitionSpacerSize = base.verticalPartitionSpacerSize,
        defaultPanePreferredWidth = base.defaultPanePreferredWidth,
        defaultPanePreferredHeight = base.defaultPanePreferredHeight,
        excludedBounds = base.excludedBounds,
        shouldAutoFocusCurrentDestination = false,
    )
}

/** The empty detail pane in two panes, until something in the list is opened. */
@Composable
private fun DetailPlaceholder(icon: ImageVector) {
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainerLow), Alignment.Center) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(96.dp),
            tint = MaterialTheme.colorScheme.outlineVariant,
        )
    }
}

/** Tools whose root lists items for a detail pane beside it. */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
private fun listPanes(provider: (NavKey) -> NavEntry<NavKey>): (NavKey) -> NavEntry<NavKey> =
    { key ->
        val entry = provider(key)
        if (key in LIST_TOOLS || key is HadithBrowseRoute) {
            val icon = ((key as? ToolRoute)?.tool ?: AppTool.Hadith).icon
            val metadata = ListDetailSceneStrategy.listPane(detailPlaceholder = { DetailPlaceholder(icon) })
            NavEntry(key, entry.contentKey, metadata) { entry.Content() }
        } else {
            entry
        }
    }

/** A tool as a tab root (no Up button) or pushed from Tools/Today. Swift `ToolDestination`. */
@Composable
private fun ToolScreen(
    tool: AppTool,
    onBack: (() -> Unit)?,
    open: (Route) -> Unit,
    onRestoreHadith: (List<HadithRoute>) -> Unit,
) {
    when (tool) {
        AppTool.Quran -> {
            QuranScreen(hiltViewModel(), open, onBack)
        }

        AppTool.Hadith -> {
            HadithBrowseScreen(
                hiltViewModel<HadithBrowseViewModel, HadithBrowseViewModel.Factory>(
                    creationCallback = { it.create(HadithBrowseRoute(), isRoot = true) },
                ),
                onOpen = open,
                onRestore = onRestoreHadith,
                onBack = onBack,
            )
        }

        AppTool.Supplications -> {
            SupplicationsScreen(hiltViewModel(), open, onBack)
        }

        AppTool.Dictionary -> {
            com.aljaroudi.muntathir.ui.dictionary
                .DictionaryScreen(onBack = onBack)
        }

        AppTool.Sermons -> {
            SermonsScreen(onBack = onBack, onOpen = { open(SermonRoute(it)) }, open = open)
        }

        AppTool.Rulings -> {
            RulingsScreen(hiltViewModel(), open, onBack)
        }

        AppTool.Calendar -> {
            CalendarScreen(hiltViewModel(), onBack, open = open)
        }

        AppTool.Events -> {
            EventsScreen(hiltViewModel<EventsViewModel>(), open, onBack)
        }

        AppTool.Figures -> {
            FiguresScreen(open, onBack)
        }

        AppTool.Tasbih -> {
            TasbihScreen(onBack)
        }

        AppTool.Rakaat -> {
            RakaatScreen(open, onBack)
        }

        AppTool.PrayerProgress -> {
            ActivityScreen(onBack)
        }

        AppTool.Qibla -> {
            QiblaScreen(onBack)
        }
    }
}

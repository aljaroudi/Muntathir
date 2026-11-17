package com.aljaroudi.muntathir.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.rememberDecoratedNavEntries
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import com.aljaroudi.muntathir.core.app.AppTool

/** Every possible tab root, in a fixed order so each keeps its own saved back stack. */
val TAB_ROOTS: List<Route> = listOf(TodayRoute, ToolsRoute) + AppTool.entries.map(::ToolRoute)

/** The tabs shown for [shortcuts]: Today, the shortcuts in order, then Tools. Swift `ContentView` tabs. */
fun tabs(shortcuts: List<AppTool>): List<Route> = listOf(TodayRoute) + shortcuts.map(::ToolRoute) + ToolsRoute

/**
 * One back stack per tab. Back from a tab's root returns to Today, so the app always exits through Today.
 * Stacks survive configuration changes and process death; the selected tab survives configuration changes.
 */
class AppNavigator(
    val stacks: Map<Route, NavBackStack<NavKey>>,
    /** Index into [TAB_ROOTS]; an `Int` so it saves with the activity. */
    private val tabIndex: MutableIntState,
) {
    var tab: Route
        get() = TAB_ROOTS[tabIndex.intValue]
        set(value) {
            tabIndex.intValue = TAB_ROOTS.indexOf(value)
        }

    val current: NavBackStack<NavKey> get() = stacks.getValue(tab)

    fun select(route: Route) {
        if (route == tab) {
            // Reselecting a tab pops it to its root.
            while (current.size > 1) current.removeAt(current.lastIndex)
        }
        tab = route
    }

    fun push(route: Route) {
        if (current.lastOrNull() != route) current.add(route)
    }

    fun back() {
        if (current.size > 1) current.removeAt(current.lastIndex) else tab = TodayRoute
    }

    /**
     * Opens Today or [tool] from outside the app (launcher shortcut, widget, tile): the tool's own tab when it is
     * one of [tabs], otherwise on top of Tools.
     */
    fun open(
        tool: AppTool?,
        tabs: List<Route>,
    ) {
        val route = tool?.let(::ToolRoute) ?: TodayRoute
        when {
            route in tabs -> {
                select(route)
            }

            else -> {
                tab = ToolsRoute
                while (current.size > 1) current.removeAt(current.lastIndex)
                push(route)
            }
        }
    }

    /** Falls back to Today when the selected shortcut is removed. Swift `AppTab.available(in:)`. */
    fun keepAvailable(tabs: List<Route>) {
        if (tab !in tabs) tab = TodayRoute
    }

    @Composable
    fun entries(provider: (NavKey) -> NavEntry<NavKey>): List<NavEntry<NavKey>> {
        val decorated =
            stacks.mapValues { (root, stack) ->
                rememberDecoratedNavEntries(
                    backStack = stack,
                    entryDecorators =
                        listOf(
                            rememberSaveableStateHolderNavEntryDecorator(),
                            rememberViewModelStoreNavEntryDecorator(),
                        ),
                    // The same route can sit in Today's stack and the shown tab's stack; scope its state per stack.
                    entryProvider = { key ->
                        val entry = provider(key)
                        NavEntry(key, "$root/${entry.contentKey}", entry.metadata) { entry.Content() }
                    },
                )
            }
        val inUse = if (tab == TodayRoute) listOf(TodayRoute) else listOf(TodayRoute, tab)
        return inUse.flatMap { decorated.getValue(it) }
    }
}

@Composable
fun rememberAppNavigator(): AppNavigator {
    val stacks = TAB_ROOTS.associateWith { rememberNavBackStack(it) }
    val tabIndex = rememberSaveable { mutableIntStateOf(TAB_ROOTS.indexOf(TodayRoute)) }
    return remember { AppNavigator(stacks, tabIndex) }
}

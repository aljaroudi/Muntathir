import SwiftUI

/// What one tool's split view has open. Lives above the tab view so it survives layout changes.
@MainActor @Observable final class SplitState {
    private(set) var selection: FigureRoute?
    /// Picked for the person rather than by them; never restored or pushed onto a stack.
    private(set) var automatic = true
    var detailPath: [FigureRoute] = []

    /// The open item as a route a stack can push, when the person opened it.
    var route: FigureRoute? {
        automatic ? nil : selection
    }

    /// Opens `route` on the person's behalf, starting a fresh detail stack.
    func select(_ route: FigureRoute?) {
        guard route != selection else { return }
        selection = route
        automatic = false
        detailPath = []
    }

    /// Fills an empty split with a route the person didn't pick.
    func selectAutomatically(_ route: FigureRoute) {
        selection = route
        automatic = true
        detailPath = []
    }

    /// Empties the split so the next default fills it.
    func clear() {
        selection = nil
        automatic = true
        detailPath = []
    }

    /// Takes over a stack's path: its first screen becomes the selection, the rest stays pushed in the detail.
    func adopt(_ path: [FigureRoute]) {
        guard let first = path.first else { return }
        selection = first
        automatic = false
        detailPath = Array(path.dropFirst())
    }

    /// Gives up the selection, returning the stack path that shows the same thing.
    func handOff() -> [FigureRoute]? {
        defer {
            selection = nil
            detailPath = []
        }
        return route.map { [$0] + detailPath }
    }
}

@MainActor @Observable final class SplitSelections {
    @ObservationIgnored private var states: [AppTool: SplitState] = [:]

    func state(for tool: AppTool) -> SplitState {
        if let state = states[tool] {
            return state
        }
        let state = SplitState()
        states[tool] = state
        return state
    }
}

extension EnvironmentValues {
    /// Set only when the tool should lay out as a split view.
    @Entry var splitState: SplitState?
    /// True inside a split view's list column, where rows select instead of push.
    @Entry var adaptiveSplitActive = false
    /// True for a split view's detail page, which stays open after a choice; dismissing it would change the selection.
    @Entry var isSplitDetailRoot = false
}

/// Shows a list beside the route it selects when the tab sidebar is showing; otherwise the list pushes as before.
///
/// Rows select the same route a stack would push, so whatever is open carries over when the layout changes.
struct AdaptiveSplit<ListContent: View>: View {
    /// Keys the selection restored on macOS.
    let restorationKey: String
    /// The route opened when nothing is selected yet; nil while the list is still loading.
    var defaultSelection: FigureRoute?
    /// Clears the selection when it changes, for lists whose rows depend on a choice like a religious authority.
    var scope = ""
    /// Gives the list column its own stack, for lists that drill down before reaching the detail.
    var listPushes = false
    @ViewBuilder var list: (Binding<FigureRoute?>) -> ListContent
    @Environment(\.splitState) private var state
    @Environment(\.hadithAssets) private var hadithAssets
    @Environment(\.supplicationAssets) private var supplicationAssets

    var body: some View {
        if let state {
            split(state)
        } else {
            list(.constant(nil))
        }
    }

    private func split(_ state: SplitState) -> some View {
        @Bindable var state = state
        // A closure binding, since only the list writes through it and those writes are the person's picks.
        let selection = Binding<FigureRoute?> {
            state.selection
        } set: { route in
            state.select(route)
            save(route)
        }
        return NavigationSplitView(columnVisibility: .constant(.all)) {
            Group {
                if listPushes {
                    NavigationStack {
                        list(selection)
                    }
                } else {
                    list(selection)
                }
            }
            // The tab sidebar already has a toggle; the list column stays put beside the detail.
            .toolbar(removing: .sidebarToggle)
            // Only the list column selects; lists inside the detail, like a surah's own search, still push.
            .environment(\.adaptiveSplitActive, true)
        } detail: {
            NavigationStack(path: $state.detailPath) {
                Group {
                    if let route = state.selection {
                        FigureRouteView(route: route, hadithAssets: hadithAssets, supplicationAssets: supplicationAssets)
                            .id(route)
                    } else {
                        ProgressView()
                    }
                }
                .figureDestinations(hadithAssets: hadithAssets, supplicationAssets: supplicationAssets)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: scope) { state.clear() }
        .onChange(of: defaultSelection, initial: true) { _, route in
            guard state.selection == nil else { return }
            if let restored = restored() {
                state.select(restored)
            } else if let route {
                state.selectAutomatically(route)
            }
        }
    }

    private var defaultsKey: String {
        "split.selection." + restorationKey
    }

    private func save(_ route: FigureRoute?) {
        #if os(macOS)
            UserDefaults.standard.set(route.flatMap { try? JSONEncoder().encode($0) }, forKey: defaultsKey)
        #endif
    }

    private func restored() -> FigureRoute? {
        #if os(macOS)
            UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(FigureRoute.self, from: $0) }
        #else
            nil
        #endif
    }
}

/// A row that selects `route` in a split view's list column and pushes it onto the stack's path otherwise.
struct AdaptiveLink<Label: View>: View {
    let route: FigureRoute
    /// The search the row is a result of, recorded in search history once the person opens it.
    var search: (query: String, area: SearchHistory.Area)?
    @ViewBuilder var label: Label
    @Environment(\.adaptiveSplitActive) private var splitActive

    private var value: FigureRoute {
        guard let search, !search.query.isEmpty else { return route }
        return .opened(route, search: search.query, area: search.area)
    }

    var body: some View {
        if splitActive {
            // A tag rather than a value link, which would push in place when the list column has its own stack.
            label.tag(value)
        } else {
            NavigationLink(value: value) { label }
        }
    }
}

/// A list that binds `selection` only in a split view's list column; in a stack, a selection would swallow link taps.
struct AdaptiveList<Content: View>: View {
    @Binding var selection: FigureRoute?
    @ViewBuilder var content: Content
    @Environment(\.adaptiveSplitActive) private var splitActive

    var body: some View {
        if splitActive {
            List(selection: $selection) { content }
        } else {
            List { content }
        }
    }
}

extension View {
    /// Gives a split-capable tool's placeholder, such as a pending download, the stack the split would otherwise provide.
    func splitFallbackStack() -> some View {
        modifier(SplitFallbackStack())
    }
}

private struct SplitFallbackStack: ViewModifier {
    @Environment(\.splitState) private var state
    @Environment(\.hadithAssets) private var hadithAssets
    @Environment(\.supplicationAssets) private var supplicationAssets

    func body(content: Content) -> some View {
        if state == nil {
            content
        } else {
            NavigationStack {
                content.figureDestinations(hadithAssets: hadithAssets, supplicationAssets: supplicationAssets)
            }
        }
    }
}

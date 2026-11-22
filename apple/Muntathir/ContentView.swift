import SwiftUI

struct ContentView: View {
    private static var defaults: UserDefaults {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ? UserDefaults(suiteName: "Muntathir.UITests")! : .standard
    }

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var hadithSession = HadithSession(defaults: ContentView.defaults)
    @AppStorage("tabViewCustomization") private var tabCustomization = TabViewCustomization()
    @State private var selectedTab: AppTab = .today
    // Driven by `isTabViewSidebarAvailable` rather than size class, which can be regular without a sidebar.
    #if os(macOS)
        /// Mac windows always show the sidebar.
        @State private var isSidebarAvailable = true
        @State private var isSidebarShowing = true
    #else
        @State private var isSidebarAvailable = false
        /// Whether the sidebar is expanded rather than collapsed into the floating tab bar.
        @State private var isSidebarShowing = false
    #endif
    @State private var toolPaths: [AppTool: [FigureRoute]] = [:]
    @State private var toolsPath: [FigureRoute] = []
    @State private var splitSelections = SplitSelections()
    @State private var hadithAssets = AssetPackUpdates.shared.hadith
    @State private var supplicationAssets = AssetPackUpdates.shared.supplications
    @State private var rulingsAssets = AssetPackUpdates.shared.rulings
    @State private var translations = QuranTranslationStore.shared
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                shell(.today) { TodayView(referenceDate: skyTestDate) }
            }
            #if os(iOS)
            .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            #endif
            if isSidebarAvailable {
                sidebarTabs
            } else {
                compactTabs
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($tabCustomization)
        #if os(iOS)
            // On macOS, Settings is its own window (⌘,) instead of a sidebar item.
            .tabViewSidebarBottomBar {
                if isSidebarAvailable {
                    Button {
                        selectedTab = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .padding()
                    .accessibilityIdentifier("settings-tab")
                }
            }
        #endif
            .environment(\.isShowingTabSidebar, isSidebarAvailable)
            .environment(\.rulingsAssets, rulingsAssets)
            .environment(\.hadithAssets, hadithAssets)
            .environment(\.supplicationAssets, supplicationAssets)
            .environment(\.hadithSession, hadithSession)
            .onChange(of: model.preferences.tabShortcuts) { _, shortcuts in
                if !isSidebarAvailable {
                    selectedTab = selectedTab.available(in: shortcuts)
                }
            }
            .onChange(of: layout) { old, new in adapt(from: old, to: new) }
            .tint(.accentColor)
            .sheet(item: $translations.downloadRequest) { translation in
                QuranDownloadView(requested: translation.id)
            }
            .task { model.reschedule() }
            .task { await rulingsAssets.monitor() }
            .task { await hadithAssets.monitor() }
            .task { await supplicationAssets.monitor() }
            .task { await QuranTranslationStore.shared.monitor() }
            .task { await AssetPackUpdates.shared.run(.launch) }
            .onChange(of: model.locationService.current) { _, location in
                if model.liveLocation != nil, let location {
                    model.applyLive(location)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    hadithSession.save()
                    hadithAssets.cancelIntegrityCheck()
                    supplicationAssets.cancelIntegrityCheck()
                }
                if phase == .active {
                    model.reschedule()
                    Task { await AssetPackUpdates.shared.run(.foreground) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in model.reschedule() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in model.reschedule() }
            .alert(
                "Unable to update",
                isPresented: Binding(
                    get: { model.error != nil },
                    set: {
                        if !$0 {
                            model.error = nil
                        }
                    }
                )
            ) {
                Button("OK") { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
    }

    private var skyTestDate: Date? {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing"), let index = arguments.firstIndex(of: "--sky-date"),
               arguments.indices.contains(index + 1)
            {
                return ISO8601DateFormatter().date(from: arguments[index + 1])
            }
        #endif
        return nil
    }

    /// Shortcuts start in the tab bar; other tools stay in the sidebar until added via Edit.
    @TabContentBuilder<AppTab> private var sidebarTabs: some TabContent<AppTab> {
        ForEach(model.preferences.tabShortcuts) { tool in
            toolTab(tool)
        }
        ForEach(AppTool.groups) { group in
            TabSection {
                ForEach(group.tools.filter { !model.preferences.tabShortcuts.contains($0) }) { tool in
                    toolTab(tool)
                }
            } header: {
                Text(group.title)
            }
            .customizationID("section.\(group.id)")
            .defaultVisibility(.hidden, for: .tabBar)
        }
        #if os(iOS)
            // Opened from the sidebar's bottom bar.
            Tab(value: AppTab.settings) {
                Group {
                    if splitsActive {
                        SettingsSplitView()
                    } else {
                        NavigationStack { SettingsView() }
                    }
                }
                .reportsTabSidebar(available: $isSidebarAvailable, showing: $isSidebarShowing, active: selectedTab == .settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .tabPlacement(.sidebarOnly)
            .defaultVisibility(.hidden, for: .sidebar)
            .customizationBehavior(.disabled, for: .sidebar, .tabBar)
        #endif
    }

    /// Tab-bar buttons keep the system's symbol identifier so they don't clash with the matching row in Tools.
    private func toolTab(_ tool: AppTool, sidebar: Bool = true) -> some TabContent<AppTab> {
        Tab(value: AppTab.tool(tool)) {
            toolShell(tool)
        } label: {
            Label { Text(tool.title) } icon: { Image(systemName: tool.symbol) }
                .accessibilityIdentifier(sidebar ? tool.accessibilityID : tool.symbol)
        }
        .customizationID(tool.customizationID)
    }

    @TabContentBuilder<AppTab> private var compactTabs: some TabContent<AppTab> {
        ForEach(model.preferences.tabShortcuts) { tool in
            toolTab(tool, sidebar: false)
        }
        Tab("Tools", systemImage: "square.grid.2x2", value: AppTab.tools) {
            NavigationStack(path: $toolsPath) {
                List {
                    ForEach(AppTool.groups) { group in
                        let tools = group.tools.filter { !model.preferences.tabShortcuts.contains($0) }
                        if !tools.isEmpty {
                            Section(group.title) {
                                ForEach(tools) { tool in
                                    NavigationLink(value: FigureRoute.tool(tool)) {
                                        Label { Text(tool.title) } icon: { Image(systemName: tool.symbol) }
                                    }
                                    .accessibilityIdentifier(tool.accessibilityID)
                                }
                            }
                        }
                    }
                    Section {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier("settings")
                    }
                }
                .navigationTitle("Tools")
                .figureDestinations(hadithAssets: hadithAssets, supplicationAssets: supplicationAssets)
            }
            .reportsTabSidebar(available: $isSidebarAvailable, showing: $isSidebarShowing, active: selectedTab == .tools)
        }
    }

    private struct Layout: Equatable {
        var sidebar: Bool
        var splits: Bool
    }

    private var layout: Layout {
        Layout(sidebar: isSidebarAvailable, splits: splitsActive)
    }

    /// Split views only fit beside an expanded sidebar; under the floating tab bar, tools push as on iPhone.
    private var splitsActive: Bool {
        isSidebarAvailable && isSidebarShowing
    }

    /// Carries what's open across layouts: split selections become stack paths before the tabs change, and back after.
    private func adapt(from old: Layout, to new: Layout) {
        if old.splits, !new.splits {
            handOffSplits()
        }
        if old.sidebar != new.sidebar {
            adaptSelection(sidebar: new.sidebar)
        }
        if !old.splits, new.splits {
            adoptSplits()
        }
    }

    /// Keeps the open tool selected when the sidebar appears or goes away.
    private func adaptSelection(sidebar: Bool) {
        if sidebar {
            let root = toolsPath.first
            selectedTab = selectedTab.withSidebar(toolsRoot: root)
            if case let .tool(tool) = root {
                toolPaths[tool] = Array(toolsPath.dropFirst())
            }
            toolsPath = []
        } else {
            let shortcuts = model.preferences.tabShortcuts
            if case let .tool(tool) = selectedTab, !shortcuts.contains(tool) {
                toolsPath = [.tool(tool)] + (tool.isSplitCapable ? toolPaths.removeValue(forKey: tool) ?? [] : [])
            }
            selectedTab = selectedTab.withoutSidebar(shortcuts: shortcuts)
        }
    }

    /// A split tool hands what the person opened to its stack; automatic picks aren't pushed.
    private func handOffSplits() {
        for tool in AppTool.available where tool.isSplitCapable {
            toolPaths[tool] = splitSelections.state(for: tool).handOff()
        }
    }

    /// A split tool shows the first screen pushed in its stack as the selection.
    private func adoptSplits() {
        for tool in AppTool.available where tool.isSplitCapable {
            if let path = toolPaths.removeValue(forKey: tool) {
                splitSelections.state(for: tool).adopt(path)
            }
        }
    }

    private func shell(_ tab: AppTab, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
        }
        .reportsTabSidebar(available: $isSidebarAvailable, showing: $isSidebarShowing, active: selectedTab == tab)
    }

    private func toolShell(_ tool: AppTool) -> some View {
        let path = Binding<[FigureRoute]>(
            get: { toolPaths[tool] ?? [] },
            set: { toolPaths[tool] = $0 }
        )
        return Group {
            // A split view brings its own stacks and can't sit inside another one.
            if splitsActive, tool.isSplitCapable {
                ToolDestination(tool: tool)
                    .environment(\.splitState, splitSelections.state(for: tool))
            } else {
                NavigationStack(path: path) {
                    ToolDestination(tool: tool)
                        .figureDestinations(hadithAssets: hadithAssets, supplicationAssets: supplicationAssets)
                }
            }
        }
        .id(tool)
        .reportsTabSidebar(available: $isSidebarAvailable, showing: $isSidebarShowing, active: selectedTab == .tool(tool))
    }
}

private extension View {
    /// `isTabViewSidebarAvailable` and `tabBarPlacement` are only meaningful inside tab content, so tabs report them upward.
    /// Only the selected tab reports; tabs in the background can hold stale values.
    func reportsTabSidebar(available: Binding<Bool>, showing: Binding<Bool>, active: Bool) -> some View {
        modifier(TabSidebarAvailabilityReporter(isAvailable: available, isShowing: showing, isActive: active))
    }
}

private struct TabSidebarAvailabilityReporter: ViewModifier {
    @Binding var isAvailable: Bool
    @Binding var isShowing: Bool
    let isActive: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
            content
        #else
            Group {
                if #available(iOS 27, *) {
                    content.modifier(SidebarAvailabilityReader(isAvailable: $isAvailable, isActive: isActive))
                } else {
                    // Before iOS 27, regular width implies a sidebar.
                    content.modifier(SizeClassSidebarReader(isAvailable: $isAvailable, isActive: isActive))
                }
            }
            .modifier(SidebarPlacementReader(isShowing: $isShowing, isActive: isActive))
        #endif
    }
}

#if os(iOS)
    @available(iOS 27, *)
    private struct SidebarAvailabilityReader: ViewModifier {
        @Binding var isAvailable: Bool
        let isActive: Bool
        @Environment(\.isTabViewSidebarAvailable) private var isTabViewSidebarAvailable

        func body(content: Content) -> some View {
            content.modifier(ActiveTabReporter(value: isTabViewSidebarAvailable, isActive: isActive, target: $isAvailable))
        }
    }

    private struct SidebarPlacementReader: ViewModifier {
        @Binding var isShowing: Bool
        let isActive: Bool
        @Environment(\.tabBarPlacement) private var tabBarPlacement

        func body(content: Content) -> some View {
            content.modifier(ActiveTabReporter(value: tabBarPlacement == .sidebar, isActive: isActive, target: $isShowing))
        }
    }

    private struct SizeClassSidebarReader: ViewModifier {
        @Binding var isAvailable: Bool
        let isActive: Bool
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        func body(content: Content) -> some View {
            content.modifier(ActiveTabReporter(value: horizontalSizeClass == .regular, isActive: isActive, target: $isAvailable))
        }
    }

    /// Copies `value` into `target` while this tab is selected, including when it becomes selected.
    private struct ActiveTabReporter: ViewModifier {
        let value: Bool
        let isActive: Bool
        @Binding var target: Bool

        private struct Reading: Equatable {
            let value: Bool
            let isActive: Bool
        }

        func body(content: Content) -> some View {
            content.onChange(of: Reading(value: value, isActive: isActive), initial: true) { _, reading in
                if reading.isActive, target != reading.value {
                    target = reading.value
                }
            }
        }
    }
#endif

extension EnvironmentValues {
    @Entry var isShowingTabSidebar = false
}

struct Card<Content: View>: View {
    var skyBackground = false
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background {
                if skyBackground {
                    SkyCardSurface().clipShape(.rect(cornerRadius: 24))
                } else {
                    RoundedRectangle(cornerRadius: 24).fill(.background)
                }
            }
    }
}

struct Page<Content: View>: View {
    var transparentBackground = false
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 18) { content }
                .containerRelativeFrame(.horizontal) { width, _ in min(760, max(0, width - 32)) }
                .padding()
                .frame(maxWidth: .infinity)
        }
        .background(transparentBackground ? Color.clear : Color.groupedBackground)
    }
}

struct ProvenanceLabel: View {
    let provenance: DateProvenance
    var body: some View {
        switch provenance {
        case .calculated:
            Label("Calculated — Umm al-Qura", systemImage: "function")
        case .confirmed: Label("Confirmed month", systemImage: "checkmark.seal")
        case .manual: Label("Manual month correction", systemImage: "hand.draw")
        }
    }
}

struct HijriHeading: View {
    let day: ResolvedDay
    let engine: CalendarEngine
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.semibold))
            ProvenanceLabel(provenance: day.provenance).font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var title: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = engine.baseline
        formatter.timeZone = engine.timeZone
        formatter.dateFormat = "MMMM y"
        return day.day.formatted(.number.locale(locale)) + " "
            + formatter.string(from: engine.baselineStart(day.month))
    }
}

struct EventRows: View {
    let events: [IslamicEvent]
    @Environment(\.locale) private var locale
    var body: some View {
        if events.isEmpty {
            Text("No observances today").foregroundStyle(.secondary)
        }
        ForEach(events) { event in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title(locale: locale))
                    if let year = event.yearText(locale: locale) {
                        Text(year).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "sparkle")
            }
        }
    }
}

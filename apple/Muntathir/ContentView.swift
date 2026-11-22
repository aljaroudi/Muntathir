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
    #else
        @State private var isSidebarAvailable = false
    #endif
    @State private var toolPaths: [AppTool: NavigationPath] = [:]
    @State private var toolsPath: [FigureRoute] = []
    @State private var hadithAssets = AssetPackUpdates.shared.hadith
    @State private var supplicationAssets = AssetPackUpdates.shared.supplications
    @State private var rulingsAssets = AssetPackUpdates.shared.rulings
    @State private var translations = QuranTranslationStore.shared
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                shell { TodayView(referenceDate: skyTestDate) }
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
            .task { updateReadingRoute() }
            .onChange(of: model.preferences.tabShortcuts) { _, shortcuts in
                if !isSidebarAvailable {
                    selectedTab = selectedTab.available(in: shortcuts)
                }
            }
            .onChange(of: isSidebarAvailable) { _, available in adaptSelection(sidebar: available) }
            .onChange(of: selectedTab) { _, _ in updateReadingRoute() }
            .onChange(of: toolsPath) { _, _ in updateReadingRoute() }
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
                shell { SettingsView() }
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
            .reportsTabSidebarAvailability($isSidebarAvailable)
        }
    }

    /// Keeps the open tool selected when the sidebar appears or goes away.
    private func adaptSelection(sidebar: Bool) {
        if sidebar {
            let root = toolsPath.first
            selectedTab = selectedTab.withSidebar(toolsRoot: root)
            if case let .tool(tool) = root {
                toolPaths[tool] = NavigationPath(toolsPath.dropFirst())
            }
            toolsPath = []
        } else {
            let shortcuts = model.preferences.tabShortcuts
            if case let .tool(tool) = selectedTab, !shortcuts.contains(tool) {
                toolsPath = [.tool(tool)]
            }
            selectedTab = selectedTab.withoutSidebar(shortcuts: shortcuts)
        }
    }

    private func updateReadingRoute() {
        hadithSession.state.active = selectedTab == .tool(.hadith)
            || (selectedTab == .tools && (toolsPath.contains(.hadith) || toolsPath.contains(.tool(.hadith))))
    }

    private func shell(@ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
        }
        .reportsTabSidebarAvailability($isSidebarAvailable)
    }

    private func toolShell(_ tool: AppTool) -> some View {
        let path = Binding<NavigationPath>(
            get: { toolPaths[tool] ?? NavigationPath() },
            set: { toolPaths[tool] = $0 }
        )
        return NavigationStack(path: path) {
            ToolDestination(tool: tool)
                .figureDestinations(hadithAssets: hadithAssets, supplicationAssets: supplicationAssets)
        }
        .id(tool)
        .reportsTabSidebarAvailability($isSidebarAvailable)
    }
}

private extension View {
    /// `isTabViewSidebarAvailable` is only meaningful inside tab content, so tabs report it upward.
    func reportsTabSidebarAvailability(_ isAvailable: Binding<Bool>) -> some View {
        modifier(TabSidebarAvailabilityReporter(isAvailable: isAvailable))
    }
}

private struct TabSidebarAvailabilityReporter: ViewModifier {
    @Binding var isAvailable: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
            content
        #else
            if #available(iOS 27, *) {
                content.modifier(SidebarAvailabilityReader(isAvailable: $isAvailable))
            } else {
                // Before iOS 27, regular width implies a sidebar.
                content.modifier(SizeClassSidebarReader(isAvailable: $isAvailable))
            }
        #endif
    }
}

#if os(iOS)
    @available(iOS 27, *)
    private struct SidebarAvailabilityReader: ViewModifier {
        @Binding var isAvailable: Bool
        @Environment(\.isTabViewSidebarAvailable) private var isTabViewSidebarAvailable

        func body(content: Content) -> some View {
            content.onChange(of: isTabViewSidebarAvailable, initial: true) { _, available in
                if isAvailable != available {
                    isAvailable = available
                }
            }
        }
    }

    private struct SizeClassSidebarReader: ViewModifier {
        @Binding var isAvailable: Bool
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        func body(content: Content) -> some View {
            content.onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
                if isAvailable != (sizeClass == .regular) {
                    isAvailable = sizeClass == .regular
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

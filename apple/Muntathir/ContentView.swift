import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var hadithSession = HadithSession(defaults: ProcessInfo.processInfo.arguments.contains("--ui-testing") ? UserDefaults(suiteName: "Muntathir.UITests")! : .standard)
    @State private var selectedTab: AppTab = .today
    @State private var toolPaths: [AppTool: NavigationPath] = [:]
    @State private var toolsPath: [FigureRoute] = []
    @State private var hadithAssets = HadithAssetStore()
    @State private var supplicationAssets = HadithAssetStore(backend: AppleAssetPackBackend(identifier: "supplications", resourcePath: "Supplications/supplications.db"), packID: "supplications")
    @State private var translations = QuranTranslationStore.shared
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                shell { TodayView(referenceDate: skyTestDate) }
            }
            ForEach(model.preferences.tabShortcuts) { tool in
                Tab(value: AppTab.tool(tool)) {
                    toolShell(tool)
                } label: {
                    Label { Text(tool.title) } icon: { Image(systemName: tool.symbol) }
                }
            }
            Tab("Tools", systemImage: "square.grid.2x2", value: AppTab.tools) {
                NavigationStack(path: $toolsPath) {
                    List {
                        ForEach(AppTool.groups.indices, id: \.self) { index in
                            let tools = AppTool.groups[index].filter { !model.preferences.tabShortcuts.contains($0) }
                            if !tools.isEmpty {
                                Section {
                                    ForEach(tools) { tool in
                                        NavigationLink(value: FigureRoute.tool(tool)) {
                                            Label { Text(tool.title) } icon: {
                                                if tool == .tasbih {
                                                    Text(verbatim: "📿")
                                                } else {
                                                    Image(systemName: tool.symbol)
                                                }
                                            }
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
            }
        }
        .environment(\.hadithAssets, hadithAssets)
        .environment(\.supplicationAssets, supplicationAssets)
        .environment(\.hadithSession, hadithSession)
        .task { updateReadingRoute() }
        .onChange(of: model.preferences.tabShortcuts) { _, shortcuts in
            selectedTab = selectedTab.available(in: shortcuts)
        }
        .onChange(of: selectedTab) { _, _ in updateReadingRoute() }
        .onChange(of: toolsPath) { _, _ in updateReadingRoute() }
        .tint(.accentColor)
        .sheet(item: $translations.downloadRequest) { translation in
            QuranDownloadView(requested: translation.id)
        }
        .task { model.reschedule() }
        .task { await hadithAssets.monitor() }
        .task { await supplicationAssets.monitor() }
        .task { await QuranTranslationStore.shared.monitor() }
        .task { await QuranTranslationStore.shared.refresh() }
        .task { await hadithAssets.refresh() }
        .task { await supplicationAssets.refresh() }
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
                Task { await hadithAssets.refresh(); await supplicationAssets.refresh(); await QuranTranslationStore.shared.refresh() }
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

    private func updateReadingRoute() {
        hadithSession.state.active = selectedTab == .tool(.hadith)
            || (selectedTab == .tools && (toolsPath.contains(.hadith) || toolsPath.contains(.tool(.hadith))))
    }

    private func shell(@ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
        }
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
    }
}

struct Card<Content: View>: View {
    var skyBackground = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
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
        .background(transparentBackground ? Color.clear : Color(.systemGroupedBackground))
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

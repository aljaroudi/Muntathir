import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") { shell { TodayView() } }
            Tab("Calendar", systemImage: "calendar") { shell { CalendarScreen() } }
            Tab("Qibla", systemImage: "location.north.circle") { shell { QiblaView() } }
        }
        .tint(.accentColor)
        .sheet(isPresented: $settings) { SettingsView() }
        .task { model.reschedule() }
        .onChange(of: model.locationService.current) { _, location in
            if model.liveLocation != nil, let location { model.applyLive(location) }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.reschedule() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in model.reschedule() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in model.reschedule() }
        .alert("Unable to update", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content().toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { settings = true }
                }
            }
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(.background, in: .rect(cornerRadius: 24))
    }
}
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(spacing: 18) { content }.frame(maxWidth: 760).padding().frame(maxWidth: .infinity) }
            .background(Color(.systemGroupedBackground))
    }
}
struct ProvenanceLabel: View {
    let provenance: DateProvenance
    var body: some View {
        switch provenance {
        case .calculated: Label("Calculated — Umm al-Qura", systemImage: "function")
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
            ProvenanceLabel(provenance: day.provenance).font(.caption).foregroundStyle(.secondary)
        }
    }
    var title: String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.calendar = engine.baseline; formatter.timeZone = engine.timeZone
        formatter.dateFormat = "MMMM y"
        return day.day.formatted(.number.locale(locale)) + " " + formatter.string(from: engine.baselineStart(day.month))
    }
}
struct EventRows: View {
    let events: [IslamicEvent]
    @Environment(\.locale) private var locale
    var body: some View {
        if events.isEmpty { Text("No observances today").foregroundStyle(.secondary) }
        ForEach(events) { event in
            NavigationLink { EventDetail(event: event) } label: {
                Label(event.title(arabic: locale.language.languageCode?.identifier == "ar"), systemImage: "sparkle")
            }
        }
    }
}
struct EventDetail: View {
    let event: IslamicEvent
    @Environment(\.locale) private var locale
    var body: some View {
        List {
            Text(event.title(arabic: locale.language.languageCode?.identifier == "ar")).font(.title2)
            if event.convention != nil { Text("Twelver Shia convention. Historical dates may differ between sources.").foregroundStyle(.secondary) }
            if !event.references.isEmpty {
                Section("References") { ForEach(event.references, id: \.self) { Text($0.description).textSelection(.enabled) } }
            }
        }.navigationTitle("Observance")
    }
}

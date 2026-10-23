import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                shell { TodayView(referenceDate: skyTestDate) }
            }
            Tab("Calendar", systemImage: "calendar") {
                shell { CalendarScreen() }
            }
            Tab("Tools", systemImage: "square.grid.2x2") {
                shell {
                    List {
                        NavigationLink {
                            QuranView()
                        } label: {
                            Label("The Holy Quran", systemImage: "book.closed")
                        }
                        .accessibilityIdentifier("holy-quran")
                        NavigationLink {
                            QiblaView().toolbar { settingsToolbar }
                        } label: {
                            Label("Qibla", systemImage: "location.north.circle")
                        }
                        .accessibilityIdentifier("qibla")
                    }
                    .navigationTitle("Tools")
                }
            }
        }
        .tint(.accentColor)
        .sheet(isPresented: $settings) { SettingsView() }
        .task { model.reschedule() }
        .onChange(of: model.locationService.current) { _, location in
            if model.liveLocation != nil, let location {
                model.applyLive(location)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reschedule()
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

    private func shell(@ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
                .toolbar { settingsToolbar }
        }
    }

    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") {
                settings = true
            }
        }
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

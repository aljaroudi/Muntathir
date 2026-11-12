import SwiftUI

struct EventsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    static func events(in month: Int, from events: [IslamicEvent]) -> [IslamicEvent] {
        events.filter { $0.month == month }.sorted { $0.day < $1.day }
    }

    private var monthNames: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .islamicUmmAlQura)
        return formatter.monthSymbols
    }

    var body: some View {
        List {
            ForEach(1 ... 12, id: \.self) { month in
                Section {
                    let events = Self.events(in: month, from: model.content.events)
                    if events.isEmpty {
                        Text("No events").foregroundStyle(.secondary)
                    }
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: event.day.formatted(.number.locale(locale)) + " " + monthNames[month - 1])
                                .font(.subheadline).foregroundStyle(.secondary)
                            FigureObservanceRow(event: event)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("event-\(event.id)")
                    }
                } header: {
                    Text(verbatim: monthNames[month - 1])
                        .accessibilityIdentifier("events-month-\(month)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Events")
    }
}

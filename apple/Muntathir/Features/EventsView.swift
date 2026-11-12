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
        let months = monthNames
        List {
            ForEach(1 ... 12, id: \.self) { month in
                Section {
                    let events = Self.events(in: month, from: model.content.events)
                    if events.isEmpty {
                        Text("No events").foregroundStyle(.secondary)
                    }
                    ForEach(events) { event in
                        let day = event.day.formatted(.number.locale(locale))
                        HStack(alignment: .top, spacing: 12) {
                            Text(verbatim: day)
                                .font(.title2.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 8))
                                .fixedSize()
                                .accessibilityLabel(Text(verbatim: "\(day) \(months[month - 1])"))
                            FigureObservanceRow(event: event)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("event-\(event.id)")
                    }
                } header: {
                    Text(verbatim: months[month - 1])
                        .accessibilityIdentifier("events-month-\(month)")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Events")
    }
}

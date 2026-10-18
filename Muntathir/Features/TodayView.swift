import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let engine = model.engine
            Page {
                VStack(alignment: .leading, spacing: 12) {
                    Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).inZone(model.zone)))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)

                if let location = model.location {
                    let prayers = PrayerCalculator.times(
                        on: now,
                        location: location,
                        method: model.preferences.prayerMethod,
                        asrRule: model.preferences.asrRule
                    ).filter { model.preferences.isVisible($0.name) }
                    let tomorrow = engine.addingDays(1, to: now)
                    let next =
                        (prayers
                        + PrayerCalculator.times(
                            on: tomorrow,
                            location: location,
                            method: model.preferences.prayerMethod,
                            asrRule: model.preferences.asrRule
                        )).first {
                            $0.name.isPrayer
                                && model.preferences.isVisible($0.name)
                                && $0.date > now
                        }
                    Card {
                        Text("Prayer times").font(.headline)
                        if let next {
                            HStack(alignment: .firstTextBaseline) {
                                Label("Next prayer", systemImage: "clock").font(
                                    .subheadline
                                )
                                Text(next.name.title).fontWeight(.semibold)
                                Spacer()
                                Text(next.date, style: .relative)
                                    .monospacedDigit().font(.subheadline)
                            }
                            .foregroundStyle(Color.accentColor)
                            .accessibilityElement(children: .combine)
                            
                            Divider()
                        }
                        if prayers.isEmpty {
                            ContentUnavailableView {
                                Label(
                                    "Prayer Times Unavailable",
                                    systemImage: "clock"
                                )
                            } description: {
                                Text(
                                    "This location needs to be updated to calculate prayer times."
                                )
                            } actions: {
                                NavigationLink("Choose a location") {
                                    LocationPicker()
                                }
                            }
                        }
                        ForEach(prayers) { prayer in
                            HStack {
                                Text(prayer.name.title)
                                Spacer()
                                Text(
                                    prayer.date.formatted(.dateTime.hour().minute().inZone(model.zone))
                                )
                                .font(.title3.weight(.medium))
                                .monospacedDigit()
                            }
                            .foregroundStyle(
                                prayer.name == next?.name
                                    ? Color.accentColor : Color.primary
                            )
                            .padding(.vertical, 5)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier(
                                "prayer-\(prayer.name.rawValue)"
                            )
                            if prayer.id != prayers.last?.id { Divider() }
                        }
                    }
                } else {
                    Card {
                        ContentUnavailableView {
                            Label(
                                "Prayer Times Unavailable",
                                systemImage: "clock"
                            )
                        } description: {
                            Text("Set a location to view prayer times.")
                        } actions: {
                            NavigationLink {
                                LocationPicker()
                            } label: {
                                Label(
                                    "Choose a location",
                                    systemImage: "location"
                                )
                            }
                        }
                    }
                }
            }.navigationTitle(title(now, engine: engine))
        }
    }
    private func title(_ date: Date, engine: CalendarEngine) -> String {
        let day = engine.resolve(date)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = engine.baseline
        formatter.timeZone = engine.timeZone
        formatter.dateFormat = "MMMM"
        return
            "\(day.day.formatted()) \(formatter.string(from: engine.baselineStart(day.month)))"
    }
}

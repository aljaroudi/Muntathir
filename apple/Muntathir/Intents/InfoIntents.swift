import AppIntents
import SwiftUI

// These answer from the settings the app shares with its widgets, without opening the app.

/// The prayer settings the app last saved, or an error asking for a location.
private func prayerSettings() throws -> (WidgetPrayerSettings, SavedLocation) {
    guard let settings = WidgetPrayerStore.read(), let location = settings.location else {
        throw MuntathirIntentError.noLocation
    }
    return (settings, location)
}

private func timeText(_ date: Date, in location: SavedLocation) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: location.timeZone))
}

struct NextPrayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Prayer Time"
    static let description = IntentDescription("Tells you when the next prayer is, or when a prayer you name is next due.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Prayer") var prayer: PrayerName?

    static var parameterSummary: some ParameterSummary {
        Summary("When is \(\.$prayer)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog & ShowsSnippetView {
        let (settings, location) = try prayerSettings()
        let now = Date.now
        let moment: PrayerMoment?
        if let prayer {
            // A named prayer is answered even when it's hidden from the Today list.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = location.timeZone
            let days = [now, calendar.date(byAdding: .day, value: 1, to: now) ?? now]
            moment = days.lazy.compactMap { day in
                PrayerCalculator.times(on: day, location: location, method: settings.method, imsakMinutes: settings.imsakMinutes)
                    .first { $0.name == prayer && $0.date > now }
            }.first
        } else {
            moment = settings.nextPrayer(after: now)
        }
        guard let moment else { throw MuntathirIntentError.notFound }
        let name = moment.name.title
        let time = timeText(moment.date, in: location)
        return .result(value: moment.date, dialog: "\(name) is at \(time)") {
            PrayerSnippet(moments: [moment], location: location, highlighted: moment.name)
        }
    }
}

struct TodayPrayerTimesIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Prayer Times"
    static let description = IntentDescription("Lists today's prayer times for your location.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let (settings, location) = try prayerSettings()
        let now = Date.now
        let moments = settings.prayers(on: now)
        guard !moments.isEmpty else { throw MuntathirIntentError.notFound }
        let list = moments.map { $0.name.title + " " + timeText($0.date, in: location) }.formatted(.list(type: .and))
        return .result(dialog: "\(list)") {
            PrayerSnippet(moments: moments, location: location, highlighted: settings.nextPrayer(after: now)?.name)
        }
    }
}

struct HijriDateIntent: AppIntent {
    static let title: LocalizedStringResource = "Hijri Date"
    static let description = IntentDescription("Tells you today's Hijri date, including your month corrections.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let engine = WidgetCalendarSettings.read().engine
        let date = HijriHeading.title(day: engine.resolve(.now), engine: engine, locale: .current)
        return .result(value: date, dialog: "Today is \(date)")
    }
}

struct NextIslamicEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Islamic Event"
    static let description = IntentDescription("Tells you which Islamic occasion comes next and when.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ReturnsValue<IslamicEventEntity> & ProvidesDialog {
        let engine = WidgetCalendarSettings.read().engine
        let settings = WidgetPrayerStore.read()
        let now = Date.now
        guard let upcoming = ContentLibrary().upcomingEvent(on: now, engine: engine, sunset: { settings?.sunset(on: $0) }),
              let event = upcoming.events.first else { throw MuntathirIntentError.notFound }
        let title = upcoming.events.map { $0.title(locale: .current) }.formatted(.list(type: .and))
        let dialog: IntentDialog = switch upcoming.timing {
        case .today: "Today: \(title)"
        case .tonight: "Tonight: \(title)"
        case .tomorrow: "Tomorrow: \(title)"
        case let .countdown(duration):
            "\(title), in \(duration.formatted(.units(allowed: [.days, .hours], width: .wide, maximumUnitCount: 1)))"
        }
        return .result(value: IslamicEventEntity(event), dialog: dialog)
    }
}

struct DailyAyahIntent: AppIntent {
    static let title: LocalizedStringResource = "Daily Ayah"
    static let description = IntentDescription("Shows today's verse, the same one as the Daily Ayah widget.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ReturnsValue<AyahEntity> & ProvidesDialog & ShowsSnippetView {
        let engine = WidgetCalendarSettings.read().engine
        guard let ayah = ContentLibrary().verse(on: .now, engine: engine, prayerSettings: WidgetPrayerStore.read()) else {
            throw MuntathirIntentError.notFound
        }
        let entity = AyahEntity(ayah)
        return .result(value: entity, dialog: "\(entity.reference)") {
            AyahSnippet(text: entity.text, translation: entity.translation, reference: entity.reference)
        }
    }
}

private struct PrayerSnippet: View {
    let moments: [PrayerMoment]
    let location: SavedLocation
    let highlighted: PrayerName?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(moments) { moment in
                HStack {
                    Label(moment.name.title, systemImage: moment.name.symbol)
                    Spacer()
                    Text(timeText(moment.date, in: location)).monospacedDigit()
                }
                .fontWeight(moment.name == highlighted ? .semibold : .regular)
                .foregroundStyle(moment.name == highlighted ? .primary : .secondary)
            }
        }
        .padding()
    }
}

private struct AyahSnippet: View {
    let text: String
    let translation: String?
    let reference: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.title3)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            if let translation {
                Text(translation).font(.callout)
            }
            Text(reference).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }
}

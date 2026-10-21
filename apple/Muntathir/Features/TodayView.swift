import SwiftUI
import WeatherKit

struct TodayView: View {
    var referenceDate: Date?
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var weather: CurrentWeatherStore = {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-weather") {
                let arguments = ProcessInfo.processInfo.arguments
                let condition = arguments.firstIndex(of: "--weather-condition").flatMap { index in
                    arguments.indices.contains(index + 1) ? WeatherKit.WeatherCondition(rawValue: arguments[index + 1]) : nil
                } ?? .clear
                return CurrentWeatherStore(publish: { _, _ in }) { _ in
                    WeatherReading(temperature: .init(value: 30, unit: .celsius), apparentTemperature: .init(value: 35, unit: .celsius),
                                   condition: condition.description, weatherCondition: condition, date: .now, attribution: nil)
                }
            }
        #endif
        return CurrentWeatherStore()
    }()

    @State private var dailyAyah: Ayah?
    @Environment(\.scenePhase) private var scenePhase
    @State private var skyTitleHeight: CGFloat = 52
    @State private var refreshedAt = Date.now
    @ScaledMetric(relativeTo: .body) private var prayerSymbolWidth: CGFloat = 28

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = referenceDate ?? max(context.date, refreshedAt)
            let engine = model.engine
            let sun = model.location.flatMap { SolarPosition.calculate(at: now, latitude: $0.latitude, longitude: $0.longitude) }
            let moon = model.location.flatMap { MoonPosition.calculate(at: now, latitude: $0.latitude, longitude: $0.longitude) }
            let prayers = model.location.map { location in
                PrayerCalculator.times(on: now, location: location, method: model.preferences.prayerMethod,
                                       imsakMinutes: model.preferences.imsakMinutes)
                    .filter { model.preferences.isVisible($0.name) }
            } ?? []
            Page(transparentBackground: sun != nil) {
                if let location = model.location {
                    let tomorrow = engine.addingDays(1, to: now)
                    let next =
                        (prayers
                            + PrayerCalculator.times(
                                on: tomorrow,
                                location: location,
                                method: model.preferences.prayerMethod,
                                imsakMinutes: model.preferences.imsakMinutes
                            )).first {
                            $0.name.isPrayer
                                && model.preferences.isVisible($0.name)
                                && $0.date > now
                        }
                    Card(skyBackground: sun != nil) {
                        if prayers.isEmpty {
                            ContentUnavailableView {
                                Label("Prayer Times Unavailable", systemImage: "clock")
                            } description: {
                                Text("This location needs to be updated to calculate prayer times.")
                            } actions: {
                                NavigationLink("Choose a location") {
                                    LocationPicker()
                                }
                            }
                        }
                        Grid(horizontalSpacing: 8, verticalSpacing: 16) {
                            ForEach(prayers) { prayer in
                                GridRow {
                                    HStack {
                                        Label {
                                            Text(prayer.name.title)
                                        } icon: {
                                            Image(systemName: prayer.name.symbol)
                                                .frame(width: prayerSymbolWidth)
                                        }
                                        Spacer(minLength: 8)
                                        if prayer.name == next?.name, let next {
                                            Text(PrayerCountdownFormat(target: next.date, locale: locale).format(now))
                                                .font(.caption).monospacedDigit()
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Color.accentColor.opacity(0.1), in: .capsule)
                                        }
                                    }
                                    Text(
                                        prayer.date.formatted(.dateTime.hour().minute().inZone(model.zone))
                                    )
                                    .font(.system(.title3, design: .monospaced, weight: .medium))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .gridColumnAlignment(.trailing)
                                }
                                .foregroundStyle(
                                    prayer.name == next?.name
                                        ? Color.accentColor : Color.primary
                                )
                                .padding(.vertical, 5)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("prayer-\(prayer.name.rawValue)")
                                if prayer.id != prayers.last?.id {
                                    Divider()
                                        .gridCellUnsizedAxes(.horizontal)
                                }
                            }
                        }
                    }
                } else {
                    Card(skyBackground: sun != nil) {
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
                if let dailyAyah {
                    DailyAyahCard(ayah: dailyAyah, skyBackground: sun != nil)
                }
                TodayInfoCards(date: now, skyBackground: sun != nil, weather: weather, sun: sun, moon: moon)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if sun != nil {
                    // Reserve sky, not a card: the sun stays visible while the prayer list scrolls.
                    VStack(spacing: 0) {
                        Text(title(now, engine: engine))
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                            .frame(maxWidth: 760, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityAddTraits(.isHeader)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { skyTitleHeight = $0 }
                        Color.clear.frame(height: skyHeight)
                            .accessibilityHidden(true)
                    }
                    .allowsHitTesting(false)
                }
            }
            .background {
                if let sun {
                    TodaySkyBackground(sun: sun, bandHeight: skyHeight, headerHeight: skyTitleHeight, moon: moon,
                                       markers: model.location.map { SolarArcMarker.make(prayers: prayers, now: now, location: $0) } ?? [])
                }
            }
            .toolbarBackground(sun == nil ? .automatic : .hidden, for: .navigationBar)
            .toolbarColorScheme(sun == nil ? nil : .dark, for: .navigationBar)
            .navigationTitle(sun == nil ? title(now, engine: engine) : "")
            .navigationBarTitleDisplayMode(sun == nil ? .large : .inline)
            .task(id: engine.gregorian.startOfDay(for: now)) {
                dailyAyah = model.content.verse(on: now, timeZone: model.zone)
            }
        }
        .task(id: model.location) { await weather.refresh(location: model.location) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshedAt = .now
                Task { await weather.refresh(location: model.location) }
            }
        }
    }

    private var skyHeight: CGFloat {
        verticalSizeClass == .compact ? 96 : 148
    }

    private func title(_ date: Date, engine: CalendarEngine) -> String {
        let day = engine.resolve(date)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = engine.baseline
        formatter.timeZone = engine.timeZone
        formatter.dateFormat = "MMMM"
        return "\(day.day.formatted(.number.locale(locale))) \(formatter.string(from: engine.baselineStart(day.month)))"
    }
}

#if DEBUG
    private struct TodaySkyPreview: View {
        let date: String
        @State private var model: AppModel = {
            let defaults = UserDefaults(suiteName: "Muntathir.SkyPreview")!
            let model = AppModel(defaults: defaults, cloud: nil)
            model.select(SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
            return model
        }()

        var body: some View {
            NavigationStack { TodayView(referenceDate: ISO8601DateFormatter().date(from: date)) }
                .environment(model)
        }
    }

    #Preview("Today — dawn") { TodaySkyPreview(date: "2026-10-21T02:15:00Z") }
    #Preview("Today — sunrise") { TodaySkyPreview(date: "2026-10-21T03:19:00Z") }
    #Preview("Today — noon") { TodaySkyPreview(date: "2026-10-21T09:05:00Z") }
    #Preview("Today — sunset") { TodaySkyPreview(date: "2026-10-21T14:52:00Z") }
    #Preview("Today — twilight, dark Arabic") {
        TodaySkyPreview(date: "2026-10-21T15:25:00Z")
            .preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: "ar"))
            .environment(\.layoutDirection, .rightToLeft)
    }

    #Preview("Today — night, accessible") {
        TodaySkyPreview(date: "2026-10-21T21:00:00Z")
            .environment(\.dynamicTypeSize, .accessibility2)
    }
#endif

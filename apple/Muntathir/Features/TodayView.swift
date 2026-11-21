import SwiftUI
import WeatherKit

struct TodayView: View {
    var referenceDate: Date?
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var weather: CurrentWeatherStore = {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-weather") {
                let arguments = ProcessInfo.processInfo.arguments
                let condition = arguments.firstIndex(of: "--weather-condition").flatMap { index in
                    arguments.indices.contains(index + 1) ? WeatherKit.WeatherCondition(rawValue: arguments[index + 1]) : nil
                } ?? .clear
                return CurrentWeatherStore(cached: { _, _ in nil }, publish: { _, _ in }) { _ in
                    WeatherReading(temperature: .init(value: 30, unit: .celsius), apparentTemperature: .init(value: 35, unit: .celsius),
                                   condition: condition.description, weatherCondition: condition, date: .now, attribution: nil)
                }
            }
        #endif
        return CurrentWeatherStore()
    }()

    #if DEBUG
        @State private var captureClock = CaptureClock()
    #endif

    @State private var translationStore = QuranTranslationStore.shared
    @State private var dailyAyah: Ayah?
    @Environment(\.scenePhase) private var scenePhase
    @State private var skyTitleHeight: CGFloat = 52
    @State private var refreshedAt = Date.now
    @ScaledMetric(relativeTo: .body) private var prayerSymbolWidth: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var prayerCardWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .body) private var prayerCardSymbolHeight: CGFloat = 24

    var body: some View {
        TimelineView(timelineSchedule) { context in
            let now = displayDate(context.date)
            let engine = model.engine
            let versePrayerSettings = WidgetPrayerSettings(
                location: model.location, method: model.preferences.prayerMethod, hiddenPrayers: [], imsakMinutes: model.preferences.imsakMinutes
            )
            let verseDay = ContentLibrary.verseDay(on: now, engine: engine, prayerSettings: versePrayerSettings)
            let sun = model.location.flatMap { SolarPosition.calculate(at: now, latitude: $0.latitude, longitude: $0.longitude) }
            let moon = model.location.flatMap { MoonPosition.calculate(at: now, latitude: $0.latitude, longitude: $0.longitude) }
            let prayers = model.location.map { location in
                PrayerCalculator.times(on: now, location: location, method: model.preferences.prayerMethod,
                                       imsakMinutes: model.preferences.imsakMinutes)
                    .filter { model.preferences.isVisible($0.name) }
            } ?? []
            TodayPage(transparentBackground: sun != nil) {
                Card(skyBackground: sun != nil, spacing: 8) {
                    let dateStyle = Date.FormatStyle(locale: locale, calendar: engine.gregorian, timeZone: engine.timeZone)
                    Text(now.formatted(dateStyle.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("gregorian-date")
                        .overlay(alignment: .trailing) {
                            // Overlaid so the date stays centred in the card.
                            if model.location != nil, !prayers.isEmpty {
                                let horizontal = model.preferences.horizontalPrayerTimes
                                Button(horizontal ? "Vertical layout" : "Horizontal layout",
                                       systemImage: horizontal ? "list.bullet" : "rectangle.split.3x1")
                                {
                                    model.update { $0.horizontalPrayerTimes.toggle() }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("prayer-layout")
                            }
                        }
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
                        } else if model.preferences.horizontalPrayerTimes {
                            Divider()
                            HorizontalPrayerTimes(prayers: prayers, next: next?.name) { prayer in
                                prayerCard(prayer, next: prayer.name == next?.name ? next : nil, now: now)
                            }
                        } else {
                            Divider()
                            VStack(spacing: 16) {
                                ForEach(prayers) { prayer in
                                    let rowLayout = typeSize.isAccessibilitySize
                                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                        : AnyLayout(HStackLayout(spacing: 8))
                                    rowLayout {
                                        rowLayout {
                                            Label {
                                                Text(prayer.name.title)
                                            } icon: {
                                                Image(systemName: prayer.name.symbol)
                                                    .frame(width: prayerSymbolWidth)
                                            }
                                            if !typeSize.isAccessibilitySize {
                                                Spacer(minLength: 8)
                                            }
                                            if prayer.name == next?.name, let next {
                                                Text(PrayerCountdownFormat(target: next.date, locale: locale).format(now))
                                                    .font(.caption).monospacedDigit()
                                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                                    .background(Color.accentColor.opacity(0.1), in: .capsule)
                                            }
                                        }
                                        prayerTime(prayer.date)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(
                                        prayer.name == next?.name
                                            ? Color.accentColor : Color.primary
                                    )
                                    .padding(.vertical, 5)
                                    .accessibilityElement(children: .combine)
                                    .contentShape(.rect)
                                    .accessibilityIdentifier("prayer-\(prayer.name.rawValue)")
                                    .contextMenu { prayerMenu(prayer.name) }
                                    if prayer.id != prayers.last?.id {
                                        Divider()
                                            .gridCellUnsizedAxes(.horizontal)
                                    }
                                }
                            }
                        }
                    } else {
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
                .appTip(.prayers, enabled: !prayers.isEmpty)
                if let dailyAyah {
                    DailyAyahCard(ayah: dailyAyah, skyBackground: sun != nil)
                        .layoutValue(key: TodayColumnKey.self, value: 1)
                }
                TodayInfoCards(skyBackground: sun != nil, weather: weather, sun: sun, moon: moon,
                               event: model.content.upcomingEvent(on: now, engine: engine, sunset: versePrayerSettings.sunset(on:)))
                    .layoutValue(key: TodayColumnKey.self, value: 1)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if sun != nil {
                    // Reserve sky, not a card: the sun stays visible while the prayer list scrolls.
                    VStack(spacing: 0) {
                        Text(title(now, engine: engine))
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                            .frame(maxWidth: horizontalSizeClass == .regular && !typeSize.isAccessibilitySize ? 1120 : 760,
                                   alignment: .leading)
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
                                       markers: model.location.map { SolarArcMarker.make(prayers: prayers, now: now, location: $0) } ?? [],
                                       mirrored: (model.location?.latitude ?? 0) < 0)
                }
            }
            .toolbarBackground(sun == nil ? .automatic : .hidden, for: .navigationBar)
            .toolbarColorScheme(sun == nil ? nil : .dark, for: .navigationBar)
            .navigationTitle(sun == nil ? title(now, engine: engine) : "")
            .navigationBarTitleDisplayMode(sun == nil ? .large : .inline)
            .task(id: "\(engine.timeZone.identifier)-\(verseDay.month.index)-\(verseDay.day)-\(translationStore.revision)-\(String(describing: model.location))") {
                #if DEBUG
                    dailyAyah = ProcessInfo.processInfo.arguments.contains("--marketing-capture")
                        ? (ProcessInfo.processInfo.arguments.contains("--screenshot-verse")
                            ? (try? QuranDatabase().verse(surah: 94, number: 6)) : exampleAyah) : ContentLibrary().verse(on: verseDay)
                #else
                    dailyAyah = ContentLibrary().verse(on: verseDay)
                #endif
                guard referenceDate == nil,
                      let boundary = versePrayerSettings.dailyVerseTimelineDates(from: now, engine: engine).dropFirst().first else { return }
                let midnight = engine.addingDays(1, to: engine.gregorian.startOfDay(for: now))
                do {
                    if midnight < boundary {
                        try await Task.sleep(for: .seconds(max(0, midnight.timeIntervalSinceNow)))
                        refreshedAt = .now
                    }
                    try await Task.sleep(for: .seconds(max(0, boundary.timeIntervalSinceNow)))
                    refreshedAt = .now
                } catch {}
            }
        }
        .task(id: "\(scenePhase)-\(String(describing: model.location))") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await weather.refresh(location: model.location)
                do { try await Task.sleep(for: .seconds(900)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshedAt = .now
            }
        }
    }

    #if DEBUG
        /// Display-linked updates keep marketing animation continuous in Simulator.
        private var timelineSchedule: AnimationTimelineSchedule {
            .animation(minimumInterval: captureClock?.isAnimated == true ? 1.0 / 30 : 60)
        }
    #else
        private var timelineSchedule: PeriodicTimelineSchedule {
            .periodic(from: .now, by: 60)
        }
    #endif

    /// `padded` reserves a leading digit's width so list rows align; centred cards don't need it.
    private func prayerTime(_ date: Date, padded: Bool = true) -> some View {
        let style = Date.FormatStyle.dateTime.locale(locale).inZone(model.zone)
        let time = date.formatted(style.hour(.defaultDigits(amPM: .omitted)).minute())
        let digits = time.filter(\.isWholeNumber)
        var displayTime = AttributedString(time)
        if padded, digits.count == 3, let digit = digits.first {
            // An invisible localized digit reserves the exact width in either writing direction.
            var padding = AttributedString(String(digit))
            padding.foregroundColor = .clear
            displayTime.insert(padding, at: displayTime.startIndex)
        }
        return Text(displayTime)
            .font(.title3.weight(.medium))
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(Text(date, format: style.hour().minute()))
    }

    @ViewBuilder private func prayerMenu(_ name: PrayerName) -> some View {
        Button(model.preferences.enabledPrayers.contains(name) ? "Mute" : "Alert",
               systemImage: model.preferences.enabledPrayers.contains(name) ? "bell.slash" : "bell")
        {
            Task {
                let enabled = !model.preferences.enabledPrayers.contains(name)
                await model.setPrayer(name, enabled: enabled)
                if model.preferences.enabledPrayers.contains(name) == enabled {
                    AppTip.complete(.prayers)
                }
            }
        }
        if !name.isRequired {
            Button("Hide", systemImage: "eye.slash") {
                model.update { $0.hiddenPrayers.insert(name) }
                AppTip.complete(.prayers)
            }
        }
    }

    /// One equal-width column in the horizontal layout. `next` is set only on the upcoming prayer's column,
    /// which is tinted and shows its countdown, like the upcoming row in the list.
    private func prayerCard(_ prayer: PrayerMoment, next: PrayerMoment?, now: Date) -> some View {
        let isNext = next != nil
        let countdown = next.map { PrayerCountdownFormat(target: $0.date, locale: locale).format(now) }
        return VStack(spacing: 6) {
            // Symbols differ in height; a fixed frame keeps every column's rows on the same lines.
            Image(systemName: prayer.name.symbol)
                .frame(height: prayerCardSymbolHeight)
            Text(prayer.name.title)
                .font(.caption.weight(isNext ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            prayerTime(prayer.date, padded: false)
                .fontWeight(isNext ? .semibold : .medium)
            // Other columns reserve the countdown's height so every column matches.
            Text(countdown ?? " ")
                .font(.caption2).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.1), in: .capsule)
                .opacity(isNext ? 1 : 0)
                .accessibilityHidden(!isNext)
        }
        .frame(width: prayerCardWidth)
        .padding(.vertical, 6)
        .foregroundStyle(isNext ? Color.accentColor : Color.primary)
        .accessibilityElement(children: .combine)
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 14))
        .accessibilityIdentifier("prayer-\(prayer.name.rawValue)")
        .contextMenu { prayerMenu(prayer.name) }
    }

    private func displayDate(_ date: Date) -> Date {
        #if DEBUG
            if let captureClock {
                return captureClock.date(at: .now)
            }
        #endif
        return referenceDate ?? max(date, refreshedAt)
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

/// A sideways-scrolling row of prayer columns, divided like the list's rows, that keeps the upcoming prayer in view.
private struct HorizontalPrayerTimes<Card: View>: View {
    let prayers: [PrayerMoment]
    let next: PrayerName?
    @ViewBuilder let card: (PrayerMoment) -> Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(prayers) { prayer in
                        card(prayer).id(prayer.name)
                        if prayer.id != prayers.last?.id {
                            Divider()
                        }
                    }
                }
                // Dividers span the tallest column instead of the scroll view's height.
                .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear { reveal(with: proxy, animated: false) }
            .onChange(of: next) { reveal(with: proxy, animated: !reduceMotion) }
        }
    }

    /// A nil anchor scrolls only as far as needed, leaving an already visible card in place.
    private func reveal(with proxy: ScrollViewProxy, animated: Bool) {
        guard let next else { return }
        withAnimation(animated ? .default : nil) {
            proxy.scrollTo(next)
        }
    }
}

struct UpcomingEventCard: View {
    let events: [IslamicEvent]
    let timing: ContentLibrary.EventTiming
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                timingLabel
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("upcoming-event-timing")
            Text(verbatim: events.map { $0.title(locale: locale) }.joined(separator: "\n"))
                .font(.subheadline)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .accessibilityIdentifier("upcoming-event-names")
        }
        .accessibilityElement(children: .contain)
    }

    private var timingLabel: Text {
        switch timing {
        case .today:
            Text(verbatim: relativeDay(0))
        case .tonight:
            Text("Tonight", comment: "Timing for an observance on the evening before its calendar date.")
        case .tomorrow:
            Text(verbatim: relativeDay(1))
        case let .countdown(duration):
            Text(verbatim: duration.formatted(.units(allowed: [.days, .hours], width: .wide, maximumUnitCount: 1).locale(locale)))
        }
    }

    private func relativeDay(_ days: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: days))
    }
}

#if DEBUG
    private struct TodaySkyPreview: View {
        let date: String
        @State private var model: AppModel

        init(date: String, horizontal: Bool = false) {
            self.date = date
            // Separate suites so the layout choice doesn't leak into the other previews.
            let defaults = UserDefaults(suiteName: horizontal ? "Muntathir.SkyPreview.horizontal" : "Muntathir.SkyPreview")!
            let model = AppModel(defaults: defaults, cloud: nil)
            model.select(SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
            model.update { $0.horizontalPrayerTimes = horizontal }
            _model = State(initialValue: model)
        }

        var body: some View {
            NavigationStack { TodayView(referenceDate: ISO8601DateFormatter().date(from: date)) }
                .environment(model)
        }
    }

    #Preview("Today — dawn") { TodaySkyPreview(date: "2026-10-21T02:15:00Z") }
    #Preview("Today — sunrise") { TodaySkyPreview(date: "2026-10-21T03:19:00Z") }
    #Preview("Today — noon") { TodaySkyPreview(date: "2026-10-21T09:05:00Z") }
    #Preview("Today — sunset") { TodaySkyPreview(date: "2026-10-21T14:52:00Z") }
    #Preview("Today — horizontal, evening") { TodaySkyPreview(date: "2026-10-21T15:40:00Z", horizontal: true) }
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

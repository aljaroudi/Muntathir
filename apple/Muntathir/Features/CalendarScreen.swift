import SwiftUI

struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var now: Date
    @State private var selectedYear: Int?
    @State private var pickerMonth: HijriMonth?
    @State private var pendingDay: ResolvedDay?
    /// The year whose initial scroll already ran, so returning to the screen keeps the user's position.
    @State private var positionedYear: Int?

    init() {
        #if DEBUG
            let date = CaptureClock()?.start ?? .now
        #else
            let date = Date.now
        #endif
        _now = State(initialValue: date)
    }

    var body: some View {
        let engine = model.engine
        let currentMonth = engine.resolve(now).month
        let year = selectedYear ?? currentMonth.year
        let months = (1 ... 12).map { HijriMonth(year: year, month: $0) }
        // The List is the screen's root scroll view so the navigation bar tracks it and it
        // receives swipes across the full width (including iPad margins).
        ScrollViewReader { proxy in
            List {
                ForEach(months, id: \.self) { month in
                    CalendarMonthSection(month: month, now: now)
                }
            }
            .groupedListStyle()
            // Scrolling to a Section aligns its first row with the top of the content area; this
            // margin keeps the (non-sticky) month header visible above it instead of under the bar.
            .safeAreaPadding(.top, 44)
            .task(id: year) {
                // `task` reruns whenever the List reappears (tab switch, popping a profile);
                // only position each year once so the user's scroll position isn't thrown away.
                guard positionedYear != year else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                // A day picked in the jump sheet scrolls on dismiss instead.
                if pendingDay == nil {
                    scrollToStart(year: year, engine: engine, proxy: proxy, animated: false)
                }
                positionedYear = year
            }
            .navigationTitle("Calendar")
            .navigationSubtitle(Text("\(year.formatted(.number.grouping(.never).locale(locale))) AH"))
            .inlineNavigationTitle()
            .toolbarTitleMenu {
                ControlGroup {
                    Button("Previous year", systemImage: "chevron.backward") { selectedYear = year - 1 }
                        .disabled(year <= 1350)
                    Button("Next year", systemImage: "chevron.forward") { selectedYear = year + 1 }
                        .disabled(year >= 1500)
                }
                Section {
                    ForEach(months, id: \.self) { month in
                        Button(monthTitle(month, engine: engine, includeYear: false)) {
                            scroll(to: Self.monthID(month), proxy: proxy)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .trailingBar) {
                    Button("Today") {
                        if year == currentMonth.year {
                            scrollToStart(year: currentMonth.year, engine: engine, proxy: proxy, animated: true)
                        }
                        selectedYear = nil
                    }.accessibilityIdentifier("calendar-today")
                }
                ToolbarItem(placement: .trailingBar) {
                    Button("Jump to date", systemImage: "calendar") {
                        pickerMonth = year == currentMonth.year ? currentMonth : months[0]
                    }.labelStyle(.iconOnly).accessibilityIdentifier("calendar-jump")
                }
            }
            .sheet(isPresented: Binding(get: { pickerMonth != nil }, set: {
                if !$0 {
                    pickerMonth = nil
                }
            }), onDismiss: {
                if let day = pendingDay {
                    scroll(to: Self.jumpTarget(day, eventDays: model.content.events.filter { $0.month == day.month.month }.map(\.day), engine: engine), proxy: proxy)
                    pendingDay = nil
                }
            }) {
                if let month = pickerMonth {
                    datePicker(month, engine: engine)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = currentDate }
        .onChange(of: scenePhase) {
            _, phase in if phase == .active {
                now = currentDate
            }
        }
    }

    private func datePicker(_ month: HijriMonth, engine: CalendarEngine) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Button("Previous month", systemImage: "chevron.backward") { pickerMonth = month.advanced(-1) }
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                            .disabled(month == HijriMonth(year: 1350, month: 1))
                        Spacer()
                        Text(monthTitle(month, engine: engine)).font(.headline).multilineTextAlignment(.center)
                            .accessibilityIdentifier("calendar-month-title")
                        Spacer()
                        Button("Next month", systemImage: "chevron.forward") { pickerMonth = month.advanced(1) }
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                            .disabled(month == HijriMonth(year: 1500, month: 12))
                    }
                    if isExpected(month, engine: engine) {
                        Text("Future dates are estimates until the month’s moonsighting is confirmed or the month begins.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    let days = engine.days(in: month)
                    if typeSize.isAccessibilitySize {
                        LazyVStack { ForEach(days, id: \.self) { date in dayButton(date, engine: engine) } }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 8) {
                            ForEach(0 ..< 7, id: \.self) { index in
                                Text(weekday(index, engine: engine)).font(.caption2).foregroundStyle(.secondary)
                            }
                            let blanks = (engine.gregorian.component(.weekday, from: days[0]) - engine.gregorian.firstWeekday + 7) % 7
                            // Offset past the weekday header IDs (0–6) so every grid child has a unique ID.
                            ForEach(7 ..< 7 + blanks, id: \.self) { _ in Color.clear.frame(height: 48).accessibilityHidden(true) }
                            ForEach(days, id: \.self) { date in dayButton(date, engine: engine) }
                        }
                    }
                }.padding()
            }
            .navigationTitle("Jump to date").inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pickerMonth = nil } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func dayButton(_ date: Date, engine: CalendarEngine) -> some View {
        let day = engine.resolve(date)
        let isToday = engine.gregorian.isDate(date, inSameDayAs: now)
        return Button {
            pendingDay = day
            selectedYear = day.month.year
            pickerMonth = nil
        } label: {
            VStack(spacing: 3) {
                Text(day.day, format: .number).font(.body.weight(.medium))
                Text(date.formatted(.dateTime.day().locale(locale).inZone(model.zone))).font(.caption2)
                Image(systemName: "circle.fill").font(.system(size: 4)).opacity(model.content.events(on: day).isEmpty ? 0 : 1)
            }.frame(maxWidth: .infinity, minHeight: 48).padding(.vertical, 3)
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .background(isToday ? Color.accentColor : .clear, in: .rect(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel("\(day.day) \(monthTitle(day.month, engine: engine))")
            .accessibilityValue(isToday ? String(localized: "Today") : "")
            .accessibilityAddTraits(isToday ? .isSelected : [])
            .accessibilityIdentifier("calendar-day-\(day.month.year)-\(day.month.month)-\(day.day)")
    }

    static func monthID(_ month: HijriMonth) -> String {
        "calendar-month-\(month.year)-\(month.month)"
    }

    nonisolated static func dayID(_ month: HijriMonth, _ day: Int) -> String {
        "calendar-events-\(month.year)-\(month.month)-\(day)"
    }

    static func jumpTarget(_ day: ResolvedDay, eventDays: [Int], engine: CalendarEngine) -> String {
        let length = engine.days(in: day.month).count
        guard let next = eventDays.filter({ $0 >= day.day && $0 <= length }).min() else { return monthID(day.month) }
        return dayID(day.month, next)
    }

    static func isExpected(_ month: HijriMonth, now: Date, engine: CalendarEngine, confirmations: [MonthCorrection]) -> Bool {
        guard month > engine.resolve(now).month else { return false }
        return !confirmations.contains { $0.month == month && $0.provenance == .confirmed && $0.start.date(in: engine.timeZone) == engine.start(of: month) }
    }

    private func isExpected(_ month: HijriMonth, engine: CalendarEngine) -> Bool {
        Self.isExpected(month, now: now, engine: engine, confirmations: model.confirmations.map(\.correction))
    }

    static func initialTarget(year: Int, currentMonth: HijriMonth, nextDay: ResolvedDay?) -> String {
        guard year == currentMonth.year else { return monthID(HijriMonth(year: year, month: 1)) }
        guard let nextDay, nextDay.month.year == year else { return monthID(currentMonth) }
        return dayID(nextDay.month, nextDay.day)
    }

    private func scrollToStart(year: Int, engine: CalendarEngine, proxy: ScrollViewProxy, animated: Bool) {
        // Today always has a row (its events, or a "No events" placeholder), followed by the next event.
        let today = engine.resolve(engine.gregorian.startOfDay(for: now))
        scroll(to: Self.initialTarget(year: year, currentMonth: today.month, nextDay: today), proxy: proxy, animated: animated)
    }

    private func scroll(to id: String, proxy: ScrollViewProxy, animated: Bool = true) {
        let animation: Animation? = reduceMotion || !animated ? nil : .easeInOut(duration: 0.25)
        withAnimation(animation) { proxy.scrollTo(id, anchor: .top) }
        // Rows far from the viewport only have estimated heights, so a long jump can land short.
        // Repeat once the rows around the target have been measured.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(animation) { proxy.scrollTo(id, anchor: .top) }
        }
    }

    static func countdownText(days: Int, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        return formatter.localizedString(from: DateComponents(day: days))
    }

    private var currentDate: Date {
        #if DEBUG
            CaptureClock()?.start ?? .now
        #else
            .now
        #endif
    }

    private func monthTitle(_ month: HijriMonth, engine: CalendarEngine, includeYear: Bool = true) -> String {
        calendarMonthTitle(month, engine: engine, locale: locale, includeYear: includeYear)
    }

    private func weekday(_ index: Int, engine: CalendarEngine) -> String {
        let f = DateFormatter(); f.locale = locale
        return f.shortWeekdaySymbols[(index + engine.gregorian.firstWeekday - 1) % 7]
    }
}

extension HijriMonth: Identifiable {
    var id: Int {
        index
    }
}

private struct EventDay: Identifiable {
    let date: Date
    let day: ResolvedDay
    var id: String {
        CalendarScreen.dayID(day.month, day.day)
    }
}

private struct CalendarMonthSection: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    let month: HijriMonth
    let now: Date

    var body: some View {
        let engine = model.engine
        // Event days, plus today even when it has no events so users can see where they are.
        let dates = engine.days(in: month).compactMap { date -> EventDay? in
            let day = engine.resolve(date)
            let isToday = engine.gregorian.isDate(date, inSameDayAs: now)
            return model.content.events(on: day).isEmpty && !isToday ? nil : EventDay(date: date, day: day)
        }
        let expected = CalendarScreen.isExpected(month, now: now, engine: engine, confirmations: model.confirmations.map(\.correction))
        let nextEvent = model.content.nextEventDate(onOrAfter: now, engine: engine)
        Section {
            if dates.isEmpty {
                Text("No events").foregroundStyle(.secondary)
            } else {
                ForEach(dates) { entry in
                    let events = model.content.events(on: entry.day)
                    let background = rowBackground(isToday: engine.gregorian.isDate(entry.date, inSameDayAs: now))
                    eventRow(entry.date, day: entry.day, firstEvent: events.first, engine: engine, nextEvent: nextEvent, expected: expected)
                        .listRowBackground(background)
                        .id(entry.id)
                    ForEach(events.dropFirst()) { event in
                        FigureObservanceRow(event: event)
                            .listRowBackground(background)
                    }
                }
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle(month, engine: engine, includeYear: false))
                    .font(.headline).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if expected {
                    Text("Expected").font(.footnote)
                }
            }
            .textCase(nil)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(CalendarScreen.monthID(month))
        }
        .id(CalendarScreen.monthID(month))
    }

    private func eventRow(_ date: Date, day: ResolvedDay, firstEvent: IslamicEvent?, engine: CalendarEngine, nextEvent: Date?, expected: Bool) -> some View {
        let isToday = engine.gregorian.isDate(date, inSameDayAs: now)
        let isNext = date == nextEvent
        let dateText = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale).inZone(model.zone))
        let hijriText = Text(verbatim: day.day.formatted(.number.locale(locale)) + " " + monthTitle(day.month, engine: engine, includeYear: false))
            .font(.subheadline.weight(isToday ? .semibold : .medium))
            .foregroundStyle(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        let hijriDate = HStack(alignment: .firstTextBaseline, spacing: 8) {
            hijriText
            if isToday {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: .capsule)
                    .accessibilityIdentifier(isNext ? "calendar-countdown" : "calendar-today-badge")
            }
        }
        let civilDate = Group {
            if expected {
                Text("Expected: \(dateText)")
            } else {
                Text(verbatim: dateText)
            }
        }.font(.caption)
        return VStack(alignment: .leading, spacing: 8) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        hijriDate
                        civilDate
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        hijriDate
                        Spacer(minLength: 0)
                        civilDate.multilineTextAlignment(.trailing)
                    }
                }
            }
            .foregroundStyle(.secondary)
            // Today's badge already says "Today", so the countdown only appears on later days.
            if isNext, !isToday {
                let countdown = CalendarScreen.countdownText(days: engine.distance(engine.gregorian.startOfDay(for: now), date), locale: locale)
                Group {
                    if expected {
                        Text("Expected: \(countdown)")
                    } else {
                        Text(verbatim: countdown)
                    }
                }.font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("calendar-countdown")
            }
            if let firstEvent {
                FigureObservanceRow(event: firstEvent)
            } else {
                // Only today's placeholder row has no event; its badge already says "Today".
                Text("No events").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isToday ? .isSelected : [])
        .accessibilityIdentifier(CalendarScreen.dayID(day.month, day.day))
    }

    private func monthTitle(_ month: HijriMonth, engine: CalendarEngine, includeYear: Bool = true) -> String {
        calendarMonthTitle(month, engine: engine, locale: locale, includeYear: includeYear)
    }

    /// Today's rows get an accent tint over the standard grouped cell background.
    private func rowBackground(isToday: Bool) -> some View {
        Color.secondaryGroupedBackground
            .overlay(isToday ? Color.accentColor.opacity(0.1) : .clear)
    }
}

private func calendarMonthTitle(_ month: HijriMonth, engine: CalendarEngine, locale: Locale, includeYear: Bool = true) -> String {
    let f = DateFormatter(); f.locale = locale; f.calendar = engine.baseline; f.timeZone = engine.timeZone; f.dateFormat = includeYear ? "MMMM y" : "MMMM"
    return f.string(from: engine.baselineStart(month))
}

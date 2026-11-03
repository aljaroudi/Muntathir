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
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    Button("Previous year", systemImage: "chevron.backward") { selectedYear = year - 1 }
                        .labelStyle(.iconOnly).disabled(year <= 1300)
                    Spacer()
                    Menu {
                        ForEach(months, id: \.self) { month in
                            Button(monthTitle(month, engine: engine, includeYear: false)) {
                                scroll(to: Self.monthID(month), proxy: proxy)
                            }
                            .accessibilityIdentifier("calendar-jump-month-\(month.month)")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(year.formatted(.number.grouping(.never).locale(locale))) AH")
                            Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true)
                        }.font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("calendar-year")
                    Spacer()
                    Button("Next year", systemImage: "chevron.forward") { selectedYear = year + 1 }
                        .labelStyle(.iconOnly).disabled(year >= 1600)
                }.padding(.horizontal, 20).padding(.vertical, 8)
                List {
                    ForEach(months, id: \.self) { month in
                        CalendarMonthSection(month: month, now: now) { pickerMonth = month }
                    }
                }
                .listStyle(.plain)
                .listSectionSpacing(24)
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 8, for: .scrollContent)
                .id(year)
                .task(id: year) {
                    await Task.yield()
                    if !Task.isCancelled, pendingDay == nil, year == currentMonth.year {
                        scrollToStart(year: year, engine: engine, proxy: proxy)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Today", systemImage: "arrow.uturn.backward") {
                        selectedYear = nil
                        if year == currentMonth.year {
                            scrollToStart(year: currentMonth.year, engine: engine, proxy: proxy)
                        }
                    }.labelStyle(.iconOnly).accessibilityIdentifier("calendar-today")
                    Button("Jump to date", systemImage: "calendar") {
                        pickerMonth = year == currentMonth.year ? currentMonth : months[0]
                    }.labelStyle(.iconOnly).accessibilityIdentifier("calendar-jump")
                }
            }
            .sheet(item: $pickerMonth, onDismiss: {
                if let day = pendingDay {
                    scroll(to: Self.jumpTarget(day, eventDays: model.content.events.filter { $0.month == day.month.month }.map(\.day), engine: engine), proxy: proxy)
                    pendingDay = nil
                }
            }) { month in
                datePicker(month, engine: engine)
            }
        }
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
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
                            .labelStyle(.iconOnly).disabled(month == HijriMonth(year: 1300, month: 1))
                        Spacer()
                        Text(monthTitle(month, engine: engine)).font(.headline).multilineTextAlignment(.center)
                            .accessibilityIdentifier("calendar-month-title")
                        Spacer()
                        Button("Next month", systemImage: "chevron.forward") { pickerMonth = month.advanced(1) }
                            .labelStyle(.iconOnly).disabled(month == HijriMonth(year: 1600, month: 12))
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
                            ForEach(0 ..< blanks, id: \.self) { _ in Color.clear.frame(height: 48).accessibilityHidden(true) }
                            ForEach(days, id: \.self) { date in dayButton(date, engine: engine) }
                        }
                    }
                }.padding()
            }
            .navigationTitle("Jump to date").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pickerMonth = nil } } }
        }.presentationDetents([.large])
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

    private func scrollToStart(year: Int, engine: CalendarEngine, proxy: ScrollViewProxy) {
        let nextDay = model.content.nextEventDate(onOrAfter: now, engine: engine).map { engine.resolve($0) }
        scroll(to: Self.initialTarget(year: year, currentMonth: engine.resolve(now).month, nextDay: nextDay), proxy: proxy)
    }

    private func scroll(to id: String, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
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
    let selectMonth: () -> Void

    var body: some View {
        let engine = model.engine
        let dates = engine.days(in: month).compactMap { date -> EventDay? in
            let day = engine.resolve(date)
            return model.content.events(on: day).isEmpty ? nil : EventDay(date: date, day: day)
        }
        let expected = CalendarScreen.isExpected(month, now: now, engine: engine, confirmations: model.confirmations.map(\.correction))
        let nextEvent = model.content.nextEventDate(onOrAfter: now, engine: engine)
        Section {
            if dates.isEmpty {
                Text("No events").font(.subheadline).foregroundStyle(.secondary)
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(dates) { entry in
                    eventRow(entry.date, day: entry.day, engine: engine, nextEvent: nextEvent, expected: expected)
                        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                        .listRowBackground(entry.date == nextEvent ? Color.accentColor.opacity(0.06) : Color(.secondarySystemGroupedBackground))
                        .id(entry.id)
                }
            }
        } header: {
            Button(action: selectMonth) {
                HStack {
                    Text(monthTitle(month, engine: engine, includeYear: false)).font(.headline)
                    Spacer(minLength: 8)
                    if expected {
                        Text("Expected").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Image(systemName: "calendar").font(.body).foregroundStyle(.secondary)
                }.foregroundStyle(.primary).padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textCase(nil)
            .accessibilityIdentifier(CalendarScreen.monthID(month))
        }
        .id(CalendarScreen.monthID(month))
    }

    private func eventRow(_ date: Date, day: ResolvedDay, engine: CalendarEngine, nextEvent: Date?, expected: Bool) -> some View {
        let isToday = engine.gregorian.isDate(date, inSameDayAs: now)
        let isNext = date == nextEvent
        let dateText = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale).inZone(model.zone))
        let hijriDate = Text(verbatim: day.day.formatted(.number.locale(locale)) + " " + monthTitle(day.month, engine: engine, includeYear: false))
            .font(.subheadline.weight(.medium))
        let civilDate = Group {
            if expected {
                Text("Expected: \(dateText)")
            } else {
                Text(verbatim: dateText)
            }
        }.font(.caption)
        let stackedDates = VStack(alignment: .leading, spacing: 4) {
            hijriDate
            civilDate
        }
        return VStack(alignment: .leading, spacing: 10) {
            Group {
                if typeSize.isAccessibilitySize {
                    stackedDates
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            hijriDate
                            Spacer(minLength: 0)
                            civilDate
                        }
                        stackedDates
                    }
                }
            }
            .foregroundStyle(.secondary)
            if isNext {
                let countdown = CalendarScreen.countdownText(days: engine.distance(engine.gregorian.startOfDay(for: now), date), locale: locale)
                Group {
                    if isToday {
                        Text("Today")
                    } else if expected {
                        Text("Expected: \(countdown)")
                    } else {
                        Text(verbatim: countdown)
                    }
                }.font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("calendar-countdown")
            }
            ForEach(model.content.events(on: day)) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title(locale: locale)).font(.body)
                    if let year = event.yearText(locale: locale) {
                        Text(verbatim: year)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isToday ? .isSelected : [])
        .accessibilityIdentifier(CalendarScreen.dayID(day.month, day.day))
    }

    private func monthTitle(_ month: HijriMonth, engine: CalendarEngine, includeYear: Bool = true) -> String {
        calendarMonthTitle(month, engine: engine, locale: locale, includeYear: includeYear)
    }
}

private func calendarMonthTitle(_ month: HijriMonth, engine: CalendarEngine, locale: Locale, includeYear: Bool = true) -> String {
    let f = DateFormatter(); f.locale = locale; f.calendar = engine.baseline; f.timeZone = engine.timeZone; f.dateFormat = includeYear ? "MMMM y" : "MMMM"
    return f.string(from: engine.baselineStart(month))
}

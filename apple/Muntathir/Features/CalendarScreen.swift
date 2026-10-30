import SwiftUI

struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var now: Date
    @State private var monthOffset = 0
    @State private var calendarExpanded = false
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
        let month = engine.resolve(now).month.advanced(monthOffset)
        let days = engine.days(in: month)
        let today = engine.gregorian.startOfDay(for: now)
        let nextEvent = model.content.nextEventDate(onOrAfter: today, engine: engine)
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                Card {
                    let previous = Button("Previous month", systemImage: "chevron.backward") { monthOffset -= 1 }
                        .labelStyle(.iconOnly).disabled(month.year <= 1300 && month.month == 1)
                    let next = Button("Next month", systemImage: "chevron.forward") { monthOffset += 1 }
                        .labelStyle(.iconOnly).disabled(month.year >= 1600 && month.month == 12)
                    let heading = Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            calendarExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(monthTitle(month, engine: engine))
                                .multilineTextAlignment(.center)
                            Image(systemName: calendarExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .accessibilityHidden(true)
                        }.font(.headline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(calendarExpanded ? Text("Expanded") : Text("Collapsed"))
                    .accessibilityIdentifier("calendar-month-title")
                    if typeSize.isAccessibilitySize {
                        heading.frame(maxWidth: .infinity)
                        HStack {
                            previous
                            Spacer()
                            next
                        }
                    } else {
                        HStack {
                            previous
                            Spacer()
                            heading
                            Spacer()
                            next
                        }
                    }
                    if calendarExpanded {
                        if typeSize.isAccessibilitySize {
                            ScrollView {
                                LazyVStack {
                                    ForEach(days, id: \.self) { date in dayButton(date, engine: engine, proxy: proxy) }
                                }
                            }.frame(maxHeight: 240)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 8) {
                                ForEach(0 ..< 7, id: \.self) { index in Text(weekday(index, engine: engine)).font(.caption2).foregroundStyle(.secondary) }
                                let blanks = (engine.gregorian.component(.weekday, from: days[0]) - engine.gregorian.firstWeekday + 7) % 7
                                ForEach(0 ..< blanks, id: \.self) { _ in Color.clear.frame(height: 48).accessibilityHidden(true) }
                                ForEach(days, id: \.self) { date in dayButton(date, engine: engine, proxy: proxy) }
                            }
                        }
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(days, id: \.self) { date in
                            let day = engine.resolve(date)
                            let events = model.content.events(on: day)
                            let isToday = engine.gregorian.isDate(date, inSameDayAs: now)
                            let isPast = date < today
                            let isNext = date == nextEvent
                            if !events.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(day.day, format: .number)
                                            .font(.title.weight(.bold)).monospacedDigit()
                                        Text(date.formatted(.dateTime.weekday(.wide).locale(locale).inZone(model.zone)))
                                            .font(.headline)
                                        Spacer(minLength: 0)
                                    }
                                    if isNext {
                                        Group {
                                            if isToday {
                                                Text("Today")
                                            } else {
                                                Text(verbatim: Self.countdownText(days: engine.distance(today, date), locale: locale))
                                            }
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityIdentifier("calendar-countdown")
                                    }
                                    ForEach(events) { event in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(event.title(locale: locale))
                                                .font(.body)
                                            if let year = event.yearText(locale: locale) {
                                                Text(verbatim: day.day.formatted(.number.locale(locale)) + " " + monthTitle(day.month, engine: engine, includeYear: false) + " " + year)
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Text(date.formatted(.dateTime.day().month(.wide).locale(locale).inZone(model.zone)))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .foregroundStyle(isPast ? Color.secondary : Color.primary)
                                .padding(16)
                                .background(isNext ? Color.accentColor.opacity(0.08) : Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(isNext ? Color.accentColor : .clear, lineWidth: 1.5)
                                }
                                .accessibilityAddTraits(isToday ? .isSelected : [])
                                .id(CivilDate(date, in: model.zone))
                                .accessibilityIdentifier("calendar-events-\(day.day)")
                            }
                        }
                    }.padding(.bottom)
                }
                .onAppear { scrollToDay(now, engine: engine, proxy: proxy) }
                .onChange(of: month) { _, _ in
                    if monthOffset == 0 {
                        scrollToDay(now, engine: engine, proxy: proxy)
                    }
                }
            }
        }
        .frame(maxWidth: 760)
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Calendar")
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = currentDate }
        .onChange(of: scenePhase) {
            _, phase in if phase == .active {
                now = currentDate
            }
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
        let f = DateFormatter(); f.locale = locale; f.calendar = engine.baseline; f.timeZone = engine.timeZone; f.dateFormat = includeYear ? "MMMM y" : "MMMM"
        return f.string(from: engine.baselineStart(month))
    }

    private func weekday(_ index: Int, engine: CalendarEngine) -> String {
        let f = DateFormatter(); f.locale = locale
        return f.shortWeekdaySymbols[(index + engine.gregorian.firstWeekday - 1) % 7]
    }

    private func scrollToDay(_ date: Date, engine: CalendarEngine, proxy: ScrollViewProxy) {
        guard !model.content.events(on: engine.resolve(date)).isEmpty else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            proxy.scrollTo(CivilDate(date, in: model.zone), anchor: .top)
        }
    }

    private func dayButton(_ date: Date, engine: CalendarEngine, proxy: ScrollViewProxy) -> some View {
        let day = engine.resolve(date)
        let isToday = engine.gregorian.isDate(date, inSameDayAs: now)
        return Button { scrollToDay(date, engine: engine, proxy: proxy) } label: {
            VStack(spacing: 3) {
                Text(day.day, format: .number).font(.body.weight(.medium))
                Text(date.formatted(.dateTime.day().inZone(model.zone))).font(.caption2)
                Image(systemName: "circle.fill").font(.system(size: 4)).opacity(model.content.events(on: day).isEmpty ? 0 : 1)
            }.frame(maxWidth: .infinity, minHeight: 48).padding(.vertical, 3)
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .background(isToday ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel("\(day.day) \(monthTitle(day.month, engine: engine))")
            .accessibilityValue(isToday ? String(localized: "Today") : "")
            .accessibilityAddTraits(isToday ? .isSelected : [])
            .accessibilityIdentifier("calendar-day-\(day.day)")
    }
}

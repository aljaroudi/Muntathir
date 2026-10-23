import SwiftUI

struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var now: Date
    @State private var monthOffset = 0
    @State private var correcting = false
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
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                Card {
                    HStack {
                        Button("Previous month", systemImage: "chevron.backward") { monthOffset -= 1 }.labelStyle(.iconOnly).disabled(month.year <= 1300 && month.month == 1)
                        Spacer()
                        Button {
                            if monthOffset == 0 {
                                scrollToDay(now, engine: engine, proxy: proxy)
                            } else {
                                monthOffset = 0
                            }
                        } label: {
                            Text(monthTitle(month, engine: engine)).font(.headline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Back to today")
                        .accessibilityIdentifier("calendar-month-title")
                        Spacer()
                        Button("Next month", systemImage: "chevron.forward") { monthOffset += 1 }.labelStyle(.iconOnly).disabled(month.year >= 1600 && month.month == 12)
                    }
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
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(days, id: \.self) { date in
                            let day = engine.resolve(date)
                            let events = model.content.events(on: day)
                            let isToday = engine.gregorian.isDate(date, inSameDayAs: now)
                            if !events.isEmpty {
                                HStack(alignment: .top, spacing: 14) {
                                    VStack(spacing: 3) {
                                        Text(day.day, format: .number).font(.title2.weight(.semibold))
                                        Text(date.formatted(.dateTime.day().month(.abbreviated).inZone(model.zone)))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }.frame(minWidth: 52)
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(events) { event in
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(event.title(locale: locale))
                                                if let year = event.yearText(locale: locale) {
                                                    Text(year).font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(16)
                                .background(isToday ? Color.accentColor.opacity(0.08) : Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(isToday ? Color.accentColor : .clear, lineWidth: 1.5)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Adjust this month", systemImage: "calendar.badge.clock") { correcting = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = currentDate }
        .onChange(of: scenePhase) {
            _, phase in if phase == .active {
                now = currentDate
            }
        }
        .sheet(isPresented: $correcting) { CorrectionView(month: month, offset: model.preferences.monthOffsets.first { $0.month == month }?.days ?? 0) }
    }

    private var currentDate: Date {
        #if DEBUG
            CaptureClock()?.start ?? .now
        #else
            .now
        #endif
    }

    private func monthTitle(_ month: HijriMonth, engine: CalendarEngine) -> String {
        let f = DateFormatter(); f.locale = locale; f.calendar = engine.baseline; f.timeZone = engine.timeZone; f.dateFormat = "MMMM y"
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

struct CorrectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let month: HijriMonth
    @State var offset: Int
    @State private var error: String?

    private var start: Date {
        let source = (try? CalendarEngine(timeZone: model.zone, confirmed: model.confirmations.map(\.correction)))
            ?? (try! CalendarEngine(timeZone: model.zone))
        return source.addingDays(-offset, to: source.start(of: month))
    }

    var body: some View {
        NavigationStack {
            Form {
                Text("Hijri month: \(month.month.formatted()) / \(month.year.formatted(.number.grouping(.never)))")
                Picker("Day adjustment", selection: $offset) {
                    ForEach(-2 ... 2, id: \.self) { days in
                        Text(days, format: .number.sign(strategy: .always(includingZero: false))).tag(days)
                    }
                }
                .accessibilityIdentifier("month-offset")
                LabeledContent("Month starts", value: start.formatted(.dateTime.day().month(.wide).year().inZone(model.zone)))
                Text("Positive values advance the Hijri date. Every month remains 29 or 30 days. Prayer times are unchanged.")
                    .font(.footnote)
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                Button("Reset adjustment", role: .destructive) { save(0) }
            }
            .navigationTitle("Adjust month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save(offset) }.labelStyle(.iconOnly)
                }
            }
        }
    }

    private func save(_ days: Int) {
        do { try model.correct(month: month, offset: days); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

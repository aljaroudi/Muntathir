import Charts
import SwiftUI

struct ActivityProgressView: View {
    @Environment(\.progressStore) private var store
    @Environment(\.quranUserStore) private var readingStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    private var cardColumns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150), alignment: .top)]
    }

    private var totals: [ProgressActivityKind: Double] {
        ProgressActivity.totals(store?.activities ?? [])
    }

    private var prayerTotals: [(prayer: PrayerName, count: Int)] {
        PrayerProgress.prayers.map { prayer in
            (prayer, PrayerProgress.days(for: prayer, in: store?.records ?? []).values.filter { $0 == .onTime }.count)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store?.unavailable == true {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Unable to save or load activity.", systemImage: "exclamationmark.circle")
                        Button("Try again") { store?.retry() }
                    }.card()
                }
                prayerCard
                readingCards
                LazyVGrid(columns: cardColumns, spacing: 12) {
                    statCard(title: String(localized: "Bookmarks"), symbol: "bookmark.fill", value: collectionCount(readingStore?.bookmarks.count), tint: .orange, id: "progress-bookmarks")
                    statCard(title: String(localized: "Highlights"), symbol: "highlighter", value: collectionCount(readingStore?.highlights.count), tint: .purple, id: "progress-highlights")
                    statCard(title: String(localized: "Beads counted"), symbol: "circle.dotted", value: totals[.tasbih, default: 0].formatted(.number.precision(.fractionLength(0)).locale(locale)), tint: .teal, id: "progress-tasbih")
                }
                if readingStore?.unavailable == true {
                    Button("Try again") { readingStore?.reopen() }
                }
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Activity")
        .accessibilityIdentifier("progress-screen")
    }

    private var prayerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("On-time prayers", systemImage: "sun.horizon.fill").font(.headline)
            if typeSize.isAccessibilitySize {
                ForEach(prayerTotals, id: \.prayer) { item in
                    HStack {
                        Text(item.prayer.title)
                        Spacer()
                        Text(item.count, format: .number).bold().monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("prayer-total-\(item.prayer.rawValue)")
                }
            } else {
                Chart(prayerTotals, id: \.prayer) { item in
                    BarMark(x: .value("Prayer", item.prayer.title), y: .value("On-time totals", item.count))
                        .foregroundStyle(.teal.gradient)
                        .cornerRadius(6)
                        .annotation(position: .top) { Text(item.count, format: .number).font(.caption.bold()) }
                }
                .chartYScale(domain: 0 ... max(1, (prayerTotals.map(\.count).max() ?? 0) + 1))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel().font(.caption) }
                }
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("On-time prayers")
                .accessibilityValue(prayerTotals.map { "\($0.prayer.title): \($0.count.formatted(.number.locale(locale)))" }.joined(separator: ", "))
                .accessibilityIdentifier("progress-prayer-chart")
            }

            ForEach([PrayerTiming.outsideTime, .unavailable], id: \.self) { timing in
                let count = PrayerProgress.prayers.reduce(0) { $0 + PrayerProgress.days(for: $1, in: store?.records ?? []).values.filter { $0 == timing }.count }
                if count > 0 {
                    HStack {
                        Label(timing.title, systemImage: timing.symbol)
                        Spacer()
                        Text(count, format: .number)
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("prayer-\(timing.rawValue)-count")
                }
            }
            if store?.records.isEmpty != false {
                Text("No recorded prayers yet.").font(.footnote).foregroundStyle(.secondary)
            }
        }.card()
    }

    private var readingCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Time in reader", systemImage: "clock").font(.headline)
            LazyVGrid(columns: cardColumns, spacing: 12) {
                ForEach(ProgressActivityKind.reading, id: \.self) { kind in
                    statCard(title: kind.title, symbol: kind.symbol, value: duration(totals[kind, default: 0]), tint: .teal, id: "progress-\(kind.rawValue)")
                }
            }
        }
    }

    private func collectionCount(_ count: Int?) -> String {
        guard readingStore?.unavailable == false, let count else { return "—" }
        return count.formatted(.number.locale(locale))
    }

    private func duration(_ seconds: Double) -> String {
        let unit: UnitDuration = seconds < 60 ? .seconds : seconds < 3600 ? .minutes : .hours
        let value = seconds < 60 ? seconds.rounded(.down) : seconds < 3600 ? (seconds / 60).rounded(.down) : seconds / 3600
        return Measurement(value: value, unit: unit).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0 ... 1))).locale(locale))
    }

    private func statCard(title: String, symbol: String, value: String, tint: Color, id: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint).accessibilityHidden(true)
            Text(value).font(.title.bold()).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier(id)
    }
}

private extension View {
    func card() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondaryGroupedBackground, in: .rect(cornerRadius: 24))
    }
}

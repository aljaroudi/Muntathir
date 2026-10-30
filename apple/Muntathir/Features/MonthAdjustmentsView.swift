import SwiftUI

struct MonthAdjustmentsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var month: HijriMonth
    @State private var offset: Int
    @State private var error: String?

    init(month: HijriMonth, offset: Int) {
        _month = State(initialValue: month)
        _offset = State(initialValue: offset)
    }

    private func moveMonth(_ amount: Int) {
        month = month.advanced(amount)
        offset = model.preferences.monthOffsets.first { $0.month == month }?.days ?? 0
        error = nil
    }

    private var start: Date {
        let source = (try? CalendarEngine(timeZone: model.zone, confirmed: model.confirmations.map(\.correction)))
            ?? (try! CalendarEngine(timeZone: model.zone))
        return source.addingDays(-offset, to: source.start(of: month))
    }

    var body: some View {
        Form {
            HStack {
                Button("Previous month", systemImage: "chevron.backward") { moveMonth(-1) }
                    .disabled(month.year <= 1300 && month.month == 1)
                Spacer()
                Button("Next month", systemImage: "chevron.forward") { moveMonth(1) }
                    .disabled(month.year >= 1600 && month.month == 12)
            }.labelStyle(.iconOnly)
            Text("Hijri month: \(month.month, format: .number) / \(month.year, format: .number.grouping(.never))")
            Stepper(value: $offset, in: -2 ... 2) {
                LabeledContent(
                    "Day adjustment",
                    value: offset,
                    format: .number.sign(strategy: .always(includingZero: false))
                )
            }
            .accessibilityIdentifier("month-offset")
            LabeledContent("Month starts", value: start.formatted(.dateTime.day().month(.wide).year().inZone(model.zone)))
            if let error {
                Text(error).foregroundStyle(.red)
            }
            Button("Reset adjustment", role: .destructive) { save(0) }
        }
        .navigationTitle("Adjust month")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { save(offset) }.labelStyle(.iconOnly)
            }
        }
    }

    private func save(_ days: Int) {
        do { try model.correct(month: month, offset: days); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

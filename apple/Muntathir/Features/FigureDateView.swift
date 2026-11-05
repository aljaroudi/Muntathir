import SwiftUI

struct FigureDateView: View {
    @Environment(\.locale) private var locale
    let date: FigureDate

    var body: some View {
        let start = point(date.start)
        VStack(alignment: .leading, spacing: 3) {
            switch date.precision {
            case .exact: Text(verbatim: start)
            case .approximate: Text("About \(start)")
            case .range:
                if let end = date.end {
                    Text("From \(start) to \(point(end))")
                }
            }
            HStack {
                switch date.calendar {
                case .hijri: Text("Hijri")
                case .gregorian: Text("Gregorian")
                case .julian: Text("Julian")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func point(_ point: FigureDate.Point) -> String {
        let calendar: Calendar.Identifier = date.calendar == .hijri ? .islamic : .gregorian
        let year = point.year.formatted(.number.grouping(.never).locale(locale))
        let suffix = switch date.era {
        case .ah: String(localized: "AH", locale: locale)
        case .bh: String(localized: "BH", locale: locale)
        case .ce: String(localized: "CE", locale: locale)
        case .bce: String(localized: "BCE", locale: locale)
        }
        let month = point.month.map { Self.monthName($0, calendar: calendar, locale: locale) }
        let day = point.day.map { $0.formatted(.number.locale(locale)) }
        return [day, month, year, suffix].compactMap(\.self).joined(separator: " ")
    }

    static func hijriDay(_ day: Int, month: Int, locale: Locale) -> String {
        day.formatted(.number.locale(locale)) + " " + monthName(month, calendar: .islamic, locale: locale)
    }

    private static func monthName(_ month: Int, calendar: Calendar.Identifier, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: calendar)
        let symbols = formatter.monthSymbols ?? []
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : month.formatted(.number.locale(locale))
    }
}

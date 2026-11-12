import Foundation

/// The first `count` colors in the user's order form the quick picker.
enum HighlightPalette {
    static let defaultOrder = HighlightColor.allCases.map(\.rawValue).joined(separator: ",")
    static let defaultCount = 6

    static func validOrder(_ value: String) -> Bool {
        let names = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return names.count == HighlightColor.allCases.count && Set(names) == Set(HighlightColor.allCases.map(\.rawValue))
    }

    static func colors(order: String, count: Int = HighlightColor.allCases.count) -> [HighlightColor] {
        let order = validOrder(order) ? order : defaultOrder
        return Array(order.split(separator: ",").compactMap { HighlightColor(rawValue: String($0)) }.prefix(min(12, max(1, count))))
    }
}

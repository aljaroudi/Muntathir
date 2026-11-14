import Foundation
import Observation

@MainActor @Observable
final class SearchHistory {
    enum Area: String, CaseIterable {
        case quran, hadith, supplications, rulings, saved, figures, locations
    }

    static let shared = SearchHistory(defaults: ProcessInfo.processInfo.arguments.contains("--ui-testing")
        ? UserDefaults(suiteName: "Muntathir.UITests")! : .standard)
    private let defaults: UserDefaults
    private var entries: [Area: [String]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Dictionary(uniqueKeysWithValues: Area.allCases.map {
            ($0, defaults.stringArray(forKey: "searchHistory." + $0.rawValue) ?? [])
        })
    }

    func queries(in area: Area) -> [String] {
        entries[area] ?? []
    }

    func record(_ query: String, in area: Area) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        save(Array(([query] + queries(in: area).filter { $0 != query }).prefix(20)), in: area)
    }

    func remove(_ query: String, from area: Area) {
        save(queries(in: area).filter { $0 != query }, in: area)
    }

    func clear(_ area: Area) {
        save([], in: area)
    }

    private func save(_ queries: [String], in area: Area) {
        entries[area] = queries
        defaults.set(queries, forKey: "searchHistory." + area.rawValue)
    }
}

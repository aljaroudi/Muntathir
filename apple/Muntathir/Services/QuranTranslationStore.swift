import Foundation
import Observation
import WidgetKit

@MainActor @Observable final class QuranTranslationStore {
    static let shared = QuranTranslationStore()
    private(set) var selection: String
    private(set) var activeID: String
    private(set) var revision = 0
    private let defaults: UserDefaults?
    private let reloadWidgets: () -> Void
    private var languages: [String]

    init(defaults: UserDefaults? = QuranTranslationPreferences.defaults, languages: [String] = Locale.preferredLanguages,
         reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: "DailyAyah") })
    {
        self.defaults = defaults
        self.languages = languages
        self.reloadWidgets = reloadWidgets
        let saved = defaults?.string(forKey: QuranTranslationPreferences.selectionKey) ?? "auto"
        let initial = saved == "auto" || saved.isEmpty || QuranTranslation.catalog.contains(where: { $0.id == saved }) ? saved : "auto"
        selection = initial
        activeID = QuranTranslationPreferences.resolve(initial, languages: languages)?.id ?? ""
        publish()
    }

    func select(_ value: String) {
        guard value == "auto" || value.isEmpty || QuranTranslation.catalog.contains(where: { $0.id == value }) else { return }
        selection = value
        activeID = QuranTranslationPreferences.resolve(value, languages: languages)?.id ?? ""
        publish()
    }

    func activate(languages: [String]) {
        self.languages = languages
        let resolved = QuranTranslationPreferences.resolve(selection, languages: languages)?.id ?? ""
        if resolved != activeID {
            activeID = resolved
            publish()
        }
    }

    private func publish() {
        defaults?.set(selection, forKey: QuranTranslationPreferences.selectionKey)
        defaults?.set(activeID, forKey: QuranTranslationPreferences.resolvedKey)
        changed()
    }

    private func changed() {
        revision += 1
        reloadWidgets()
    }
}

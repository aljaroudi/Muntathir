import Foundation

/// Owns the downloadable content stores and runs their update checks, from the app and from background refresh.
@MainActor final class AssetPackUpdates {
    static let shared = AssetPackUpdates()

    let hadith: HadithAssetStore
    let supplications: HadithAssetStore
    let dictionary = LibraryPackStore<DictionaryReader>(packID: "lexicon", filename: "lexicon/lexicon.db",
                                                        backend: AppleAssetPackBackend(identifier: "lexicon", resourcePath: "Lexicon/lexicon.db"))
    let rulings: RulingsAssetStore
    private var current: Task<Void, Never>?

    private init() {
        let defaults = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? UserDefaults(suiteName: "Muntathir.UITests")! : .standard
        hadith = HadithAssetStore(defaults: defaults)
        supplications = HadithAssetStore(backend: AppleAssetPackBackend(identifier: "supplications", resourcePath: "Supplications/supplications.db"),
                                         packID: "supplications", defaults: defaults)
        rulings = RulingsAssetStore()
    }

    /// Refreshes every store, then checks each for a newer hosted pack, one pack at a time.
    /// Each run waits for the previous one, so launch and foreground checks never race.
    func run(_ trigger: AssetPackUpdateTrigger) async {
        let previous = current
        let task = Task {
            await previous?.value
            let translations = QuranTranslationStore.shared
            await dictionary.refresh()
            await rulings.refresh()
            await hadith.refresh()
            await supplications.refresh()
            await translations.refresh()
            await dictionary.checkForUpdates(trigger: trigger)
            await rulings.checkForUpdates(trigger: trigger)
            await hadith.checkForUpdates(trigger: trigger)
            await supplications.checkForUpdates(trigger: trigger)
            await translations.checkForUpdates(trigger: trigger)
        }
        current = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

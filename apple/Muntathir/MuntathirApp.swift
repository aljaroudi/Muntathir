import SwiftUI

@main
struct MuntathirApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var translations = QuranTranslationStore.shared
    @State private var model: AppModel
    @State private var quranStore: QuranUserStore
    init() {
        let model: AppModel
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let defaults = UserDefaults(suiteName: "Muntathir.UITests")!
                if !ProcessInfo.processInfo.arguments.contains("--ui-testing-preserve-state") {
                    defaults.removePersistentDomain(forName: "Muntathir.UITests")
                }
                if !ProcessInfo.processInfo.arguments.contains("--ui-testing-onboarding") {
                    defaults.set(true, forKey: "onboardingCompleted")
                }
                model = AppModel(defaults: defaults, cloud: nil)
                if ProcessInfo.processInfo.arguments.contains("--marketing-capture") {
                    model.update { $0.hiddenPrayers = Set(PrayerName.optionalTimes).subtracting([.sunset]) }
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-mecca") {
                    model.select(SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
                }
            } else {
                model = AppModel(feedClient: .production())
            }
        #else
            model = AppModel(feedClient: .production())
        #endif
        _model = State(initialValue: model)
        _quranStore = State(initialValue: QuranUserStore.application())
        BackgroundRefresh.register { await model.refreshInBackground() }
    }

    var body: some Scene {
        WindowGroup {
            QuranUserDataView(store: quranStore) {
                if model.onboardingCompleted {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environment(model)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await model.refreshInBackground()
            }
            .task(id: "\(scenePhase)-\(locale.identifier)-\(translations.downloadRequest)") {
                guard scenePhase == .active else { return }
                translations.activate(languages: Locale.preferredLanguages)
                await translations.downloadSelected()
            }
            .task { await translations.observeDownloads() }
        }
    }
}

import SwiftUI

@main
struct MuntathirApp: App {
    @State private var model: AppModel
    init() {
        let model: AppModel
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let defaults = UserDefaults(suiteName: "Muntathir.UITests")!
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing-preserve-state") {
                defaults.removePersistentDomain(forName: "Muntathir.UITests")
            }
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing-onboarding") {
                defaults.set(true, forKey: "onboardingCompleted")
            }
            model = AppModel(defaults: defaults, cloud: nil)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-mecca") {
                model.select(SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
            }
        } else {
            model = AppModel()
        }
        _model = State(initialValue: model)
        BackgroundRefresh.register { await model.refreshInBackground() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.onboardingCompleted {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environment(model)
        }
    }
}

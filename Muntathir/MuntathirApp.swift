import SwiftUI

@main
struct MuntathirApp: App {
    @State private var model: AppModel
    init() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let defaults = UserDefaults(suiteName: "Muntathir.UITests")!
            defaults.removePersistentDomain(forName: "Muntathir.UITests")
            let model = AppModel(defaults: defaults, cloud: nil)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-mecca") {
                model.select(SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
            }
            _model = State(initialValue: model)
        } else { _model = State(initialValue: AppModel()) }
    }
    var body: some Scene {
        WindowGroup { ContentView().environment(model) }
            .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { await model.refreshInBackground() }
    }
}

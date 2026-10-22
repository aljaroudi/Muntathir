import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    private var step: Int {
        model.onboardingStep
    }

    @State private var requestingNotifications = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Step \(step + 1, format: .number) of \(5, format: .number)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(step + 1), total: 5)
                        .accessibilityHidden(true)
                    stepContent
                    if step < 4 {
                        Button(step == 0 ? "Get started" : "Continue") { model.moveOnboarding(by: 1) }
                            .buttonStyle(.borderedProminent)
                            .disabled(step == 2 && model.location?.isValid != true)
                            .accessibilityIdentifier("onboarding-continue")
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Set up Muntathir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.backward") { model.moveOnboarding(by: -1) }
                            .disabled(requestingNotifications)
                            .accessibilityIdentifier("onboarding-back")
                    }
                }
            }
        }
        .tint(.accentColor)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0:
            Image(systemName: "moon.stars")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Welcome to Muntathir")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("A companion for your daily worship.")
            Label("Prayer times for your location", systemImage: "sun.max")
            Label("Hijri calendar and observances", systemImage: "calendar")
            Label("Find the direction of Qibla", systemImage: "location.north.circle")
        case 1:
            Text("Choose your app language")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                .font(.title2)
            Text("Choose your preferred language in iOS Settings. Return here to continue setup.")
            AppLanguageLink()
                .buttonStyle(.bordered)
        case 2:
            Text("Choose your location")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Choose a city or use your device location to calculate prayer times and Qibla.")
            NavigationLink {
                LocationPicker()
            } label: {
                Label("Choose a location", systemImage: "location")
            }
            .buttonStyle(.bordered)
            if let location = model.location {
                Label(location.name, systemImage: "checkmark.circle.fill")
            }
            Text("Device location stays on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case 3:
            Text("Prayer calculations")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Choose the calculation method you follow. You can change it later in Settings.")
            Picker("Method", selection: Binding(
                get: { model.preferences.prayerMethod },
                set: { value in model.update { $0.prayerMethod = value } }
            )) {
                ForEach(PrayerMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.menu)
        default:
            Text("Prayer reminders")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Enable notifications for your selected prayers. You can adjust reminders in Settings.")
            Text("Alerts are scheduled for up to 10 days. Open the app regularly to refresh them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if notificationsDenied {
                Text("Notifications are disabled. Enable them in system Settings.")
                Button("Finish setup") { model.completeOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding-finish")
            } else {
                Button("Enable notifications") {
                    requestingNotifications = true
                    Task {
                        let allowed = await model.notifications.authorize()
                        requestingNotifications = false
                        if allowed {
                            model.completeOnboarding()
                        } else {
                            notificationsDenied = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(requestingNotifications)
                Button("Not now") { model.completeOnboarding() }
                    .disabled(requestingNotifications)
                    .accessibilityIdentifier("onboarding-finish")
                if requestingNotifications {
                    ProgressView()
                }
            }
        }
    }
}

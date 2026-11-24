import MapKit
import SwiftUI

/// Settings as a short list of pages, for layouts without room for the split view.
struct SettingsView: View {
    private static let sections: [[SettingsPage]] = [
        [.location, .prayers, .notifications, .calendar],
        [.general, .tabs, .highlightColors, .downloads],
        [.whatsNew],
    ]

    var body: some View {
        List {
            ForEach(Self.sections, id: \.self) { pages in
                Section {
                    ForEach(pages.filter(SettingsPage.available.contains)) { page in
                        NavigationLink {
                            SettingsPageView(page: page)
                        } label: {
                            SettingsPageLabel(page: page)
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}

struct LocationSettingLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LabeledContent {
            Text(model.location?.name ?? String(localized: "Not selected"))
        } label: {
            Label("Location", systemImage: "location")
        }
    }
}

/// The adjustment screen for the current Hijri month.
struct CurrentMonthAdjustments: View {
    @Environment(AppModel.self) private var model
    private var settingsDate: Date {
        #if DEBUG
            CaptureClock()?.start ?? .now
        #else
            .now
        #endif
    }

    var body: some View {
        let month = model.engine.resolve(settingsDate).month
        MonthAdjustmentsView(month: month, offset: model.preferences.monthOffsets.first { $0.month == month }?.days ?? 0)
    }
}

/// Shown only where Apple Intelligence is available.
struct DictionarySummarySettingsSection: View {
    @AppStorage(DictionarySummarySection.setting) private var summaries = true

    var body: some View {
        if DictionarySummarizer.isAvailable {
            Section {
                Toggle("Summarize Dictionary Entries", isOn: $summaries)
                    .accessibilityIdentifier("settings-dictionary-summaries")
            } footer: {
                Text("Apple Intelligence picks the key passages of each root’s definitions on this device.")
            }
        }
    }
}

struct PrayerCalculationSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Picker(
                "Prayer calculations",
                selection: Binding(
                    get: { model.preferences.prayerMethod },
                    set: { value in
                        model.update { $0.prayerMethod = value }
                    }
                )
            ) {
                ForEach(PrayerMethod.allCases) {
                    Text($0.title).tag($0)
                }
            }
            Stepper(value: Binding(get: { model.preferences.imsakMinutes }, set: { value in
                model.update { $0.imsakMinutes = value }
            }), in: 0 ... 30) {
                LabeledContent(
                    "Imsak before Fajr",
                    value: Duration.seconds(model.preferences.imsakMinutes * 60),
                    format: .units(allowed: [.minutes], width: .wide)
                )
            }
        } header: {
            Text("Prayer calculations")
        } footer: {
            Text("Imsak is a precaution before calculated Fajr.")
        }
    }
}

struct WeatherSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Weather") {
            Toggle(isOn: Binding(
                get: { model.preferences.showFeelsLikeTemperature },
                set: { value in model.update { $0.showFeelsLikeTemperature = value } }
            )) {
                Label("Show feels-like temperature", systemImage: "thermometer.medium")
            }
        }
    }
}

struct HorizontalPrayerTimesToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Toggle(isOn: Binding(
            get: { model.preferences.horizontalPrayerTimes },
            set: { value in model.update { $0.horizontalPrayerTimes = value } }
        )) {
            Label("Horizontal prayer times", systemImage: "rectangle.split.3x1")
        }
        .accessibilityIdentifier("settings-horizontal-prayer-times")
    }
}

struct MonthConfirmationsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: {
                        model.preferences.announcementNotifications
                    },
                    set: { value in
                        Task {
                            let allowed =
                                value
                                    ? await model.notifications.authorize()
                                    : true
                            if allowed {
                                model.update {
                                    $0.announcementNotifications = value
                                }
                            } else {
                                model.error = String(
                                    localized:
                                    "Notifications are disabled. Enable them in system Settings."
                                )
                            }
                        }
                    }
                )
            ) {
                Label("Month confirmations", systemImage: "megaphone")
            }
        } header: {
            Text("Announcement notifications")
        } footer: {
            Text(
                "Alerts follow published month announcements after a successful refresh; delivery is not immediate."
            )
        }
    }
}

struct CalendarEventNotificationsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.preferences.calendarEventNotifications }, set: { enabled in
                Task {
                    let allowed = enabled ? await model.notifications.authorize() : true
                    if allowed {
                        model.update { $0.calendarEventNotifications = enabled }
                    } else {
                        model.error = String(localized: "Notifications are disabled. Enable them in system Settings.")
                    }
                }
            })) {
                Label("Calendar events", systemImage: "calendar.badge.clock")
            }
        } footer: {
            Text("Silent reminders at sunset for observances beginning this evening.")
        }
    }
}

struct SettingsSyncFooter: View {
    var body: some View {
        Section {} footer: {
            Text("Settings sync through iCloud when available. Live GPS and notification permissions stay on this device.")
        }
    }
}

struct LocationPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismissAction
    @Environment(\.isSplitDetailRoot) private var isSplitDetailRoot
    @State private var query = ""
    @State private var usingDeviceLocation = false
    var body: some View {
        List {
            Button("Use device location", systemImage: "location") {
                usingDeviceLocation = true
                model.locationService.locate()
            }
            if let current = model.locationService.current {
                Button {
                    model.applyLive(current)
                    close()
                } label: {
                    Label(current.name, systemImage: "location.fill")
                }
            }
            if model.locationService.isBusy {
                ProgressView()
            }
            if let message = model.locationService.message {
                Text(message).foregroundStyle(.secondary)
            }
            ForEach(model.locationService.results, id: \.self) { item in
                Button {
                    if let location = model.locationService.saved(item) {
                        SearchHistory.shared.record(query, in: .locations)
                        usingDeviceLocation = false
                        model.select(location)
                        close()
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(
                            item.name ?? String(localized: "Selected location")
                        )
                        Text(
                            item.addressRepresentations?.fullAddress(
                                includingRegion: true,
                                singleLine: true
                            ) ?? ""
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: model.locationService.current) { _, location in
            guard usingDeviceLocation, let location else { return }
            model.applyLive(location)
            close()
        }
        .navigationTitle("Choose a location").searchable(
            text: $query,
            placement: .alwaysVisible,
            prompt: "Search for a city"
        )
        .searchHistory($query, area: .locations)
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(350))
                await model.locationService.search(query)
            } catch {}
        }
    }

    /// Returns to the previous screen; as a settings page it stays, and the list row shows the new location.
    private func close() {
        if !isSplitDetailRoot {
            dismissAction()
        }
    }
}

struct PrayerVisibilitySection: View {
    @Environment(AppModel.self) private var model
    var header: LocalizedStringKey?

    var body: some View {
        Section {
            ForEach(PrayerName.allCases) { prayer in
                Toggle(prayer.title, isOn: Binding(get: { model.preferences.isVisible(prayer) }, set: { visible in
                    model.update {
                        if visible {
                            $0.hiddenPrayers.remove(prayer)
                        } else if !prayer.isRequired {
                            $0.hiddenPrayers.insert(prayer)
                        }
                    }
                })).disabled(prayer.isRequired)
            }
        } header: {
            if let header {
                Text(header)
            }
        } footer: { Text("Hiding a time does not change its notification setting.") }
    }
}

struct PrayerNotificationSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var permissionDenied = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.preferences.timeSensitiveNotifications }, set: { value in
                    model.update { $0.timeSensitiveNotifications = value }
                })) {
                    Label("Time Sensitive", systemImage: "bell.badge")
                }
                Button("System notification settings", systemImage: "gear") {
                    #if os(macOS)
                        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                    #else
                        let url = URL(string: UIApplication.openNotificationSettingsURLString)
                    #endif
                    if let url {
                        openURL(url)
                    }
                }
            } footer: {
                if permissionDenied {
                    Text("Notifications are disabled. Enable them in system Settings.")
                }
                Text("Allow Time Sensitive alerts in Settings and Focus. Sound follows Silent mode and your Ringtone and Alerts volume.")
            }
            Section {
                soundPicker("Prayers", keyPath: \.notificationSound)
                soundPicker("Sunset", keyPath: \.sunsetSound)
                soundPicker("Other Times", keyPath: \.otherTimesSound)
            }
            Section {
                ForEach(PrayerName.allCases) { prayer in
                    Toggle(prayer.title, isOn: Binding(get: { model.preferences.enabledPrayers.contains(prayer) }, set: { enabled in
                        Task { await model.setPrayer(prayer, enabled: enabled) }
                    }))
                }
            } footer: {
                Text("Alerts are scheduled for up to 10 days. Open the app regularly to refresh them.")
            }
            MonthConfirmationsSection()
            CalendarEventNotificationsSection()
        }.navigationTitle("Notifications")
            .onDisappear { model.notifications.stopPreview() }
            .task {
                if !model.preferences.enabledPrayers.isEmpty {
                    let authorized = await model.notifications.authorize()
                    permissionDenied = !authorized
                    if authorized {
                        model.reschedule()
                    }
                }
            }
    }

    private func soundPicker(_ title: LocalizedStringKey, keyPath: WritableKeyPath<Preferences, PrayerAlertSound>) -> some View {
        VStack(alignment: .leading) {
            Picker(title, selection: Binding(get: { model.preferences[keyPath: keyPath] }, set: { sound in
                model.update { $0[keyPath: keyPath] = sound }
                preview(sound)
            })) {
                ForEach(PrayerAlertSound.allCases) { sound in Text(sound.title).tag(sound) }
            }
            Button("Preview sound", systemImage: "speaker.wave.2") { preview(model.preferences[keyPath: keyPath]) }
                .disabled(model.preferences[keyPath: keyPath] == .silent)
        }
    }

    private func preview(_ sound: PrayerAlertSound) {
        Task {
            do { try await model.notifications.preview(sound: sound) }
            catch { model.error = error.localizedDescription }
        }
    }
}

import MapKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    private var settingsDate: Date {
        #if DEBUG
            CaptureClock()?.start ?? .now
        #else
            .now
        #endif
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { AppLanguageLink() }
                Section { ReadingSizeControls() }
                Section {
                    NavigationLink("Downloads") { DownloadsSettingsView() }
                        .accessibilityIdentifier("settings-downloads")
                }
                Section {
                    NavigationLink {
                        LocationPicker()
                    } label: {
                        LabeledContent(
                            "Location",
                            value: model.location?.name
                                ?? String(localized: "Not selected")
                        )
                    }
                } header: {
                    Text("Location")
                } footer: {
                    if model.liveLocation != nil {
                        Text("Device location stays on this device.")
                    }
                }
                Section {
                    Picker(
                        "Method",
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
                    }), in: 0 ... 120) {
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
                Section {
                    Picker("Method", selection: Binding(
                        get: { CalendarSource.method(for: model.preferences.selectedSourceID) },
                        set: { method in
                            model.update {
                                switch method {
                                case .system: $0.selectedSourceID = nil
                                case .nakedEye: $0.selectedSourceID = CalendarSource.middleEast
                                case .government: $0.selectedSourceID = "government-SA"
                                }
                            }
                        }
                    )) {
                        ForEach(CalendarMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .accessibilityIdentifier("calendar-method")
                    switch CalendarSource.method(for: model.preferences.selectedSourceID) {
                    case .system:
                        LabeledContent("Baseline", value: String(localized: "Umm al-Qura"))
                    case .nakedEye:
                        LabeledContent { Text("Middle East") } label: { Text("Region") }
                    case .government:
                        LabeledContent("Country", value: locale.localizedString(forRegionCode: "SA") ?? "SA")
                            .accessibilityIdentifier("calendar-country")
                    }
                    NavigationLink("Month adjustments") {
                        let month = model.engine.resolve(settingsDate).month
                        MonthAdjustmentsView(month: month, offset: model.preferences.monthOffsets.first { $0.month == month }?.days ?? 0)
                    }
                    .accessibilityIdentifier("month-adjustments")
                } header: {
                    Text("Calendar corrections")
                } footer: {
                    Text("Without a published announcement, dates use the system calendar. Adjust individual months in Month adjustments.")
                    if let error = model.error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section("Weather") {
                    Toggle("Show feels-like temperature", isOn: Binding(
                        get: { model.preferences.showFeelsLikeTemperature },
                        set: { value in model.update { $0.showFeelsLikeTemperature = value } }
                    ))
                }
                Section("Prayers") {
                    NavigationLink("Visibility") { PrayerVisibilitySettings() }
                    NavigationLink("Notifications") { PrayerNotificationSettings() }
                }
                Section {
                    Toggle(
                        "Month confirmations",
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
                    )
                } header: {
                    Text("Announcement notifications")
                } footer: {
                    Text(
                        "Alerts follow published month announcements after a successful refresh; delivery is not immediate."
                    )
                }
                Section {
                    Toggle("Calendar events", isOn: Binding(get: { model.preferences.calendarEventNotifications }, set: { enabled in
                        Task {
                            let allowed = enabled ? await model.notifications.authorize() : true
                            if allowed {
                                model.update { $0.calendarEventNotifications = enabled }
                            } else {
                                model.error = String(localized: "Notifications are disabled. Enable them in system Settings.")
                            }
                        }
                    }))
                } footer: {
                    Text("Silent reminders at sunset for observances beginning this evening.")
                }
                Section {} footer: {
                    Text("Settings sync through iCloud when available. Live GPS and notification permissions stay on this device.")
                }
            }.navigationTitle("Settings").toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct LocationPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
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
                    dismiss()
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
                        usingDeviceLocation = false
                        model.select(location)
                        dismiss()
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
            dismiss()
        }
        .navigationTitle("Choose a location").searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search for a city"
        )
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(350))
                await model.locationService.search(query)
            } catch {}
        }
    }
}

struct PrayerVisibilitySettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Form {
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
            } footer: { Text("Hiding a time does not change its notification setting.") }
        }.navigationTitle("Visibility")
    }
}

struct PrayerNotificationSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var body: some View {
        Form {
            Section {
                Toggle("Time Sensitive", isOn: Binding(get: { model.preferences.timeSensitiveNotifications }, set: { value in
                    model.update { $0.timeSensitiveNotifications = value }
                }))
                Button("System notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            } footer: {
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
        }.navigationTitle("Notifications")
            .onDisappear { model.notifications.stopPreview() }
            .task {
                if !model.preferences.enabledPrayers.isEmpty {
                    if await model.notifications.authorize() {
                        model.reschedule()
                    } else {
                        model.error = String(localized: "Notifications are disabled. Enable them in system Settings.")
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

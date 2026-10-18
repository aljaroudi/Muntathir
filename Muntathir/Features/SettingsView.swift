import MapKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
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
                    Picker(
                        "Asr convention",
                        selection: Binding(
                            get: { model.preferences.asrRule },
                            set: { value in model.update { $0.asrRule = value }
                            }
                        )
                    ) {
                        ForEach(AsrRule.allCases, id: \.rawValue) {
                            Text($0.title).tag($0)
                        }
                    }
                } header: {
                    Text("Prayer calculations")
                } footer: {
                    Text(
                        "Tehran calculates Maghrib after sunset. Methods may differ from your local authority."
                    )
                }
                Section {
                    LabeledContent(
                        "Baseline",
                        value: String(localized: "Calculated — Umm al-Qura")
                    )
                    ForEach(SightingMethod.allCases, id: \.rawValue) { method in
                        LabeledContent(
                            method.title,
                            value: method == .calculation
                                ? String(localized: "Active")
                                : String(localized: "Not connected")
                        )
                    }
                } header: {
                    Text("Calendar corrections")
                } footer: {
                    Text(
                        "Live sources are not connected yet. Use the Calendar tab to adjust a month manually."
                    )
                }
                Section {
                    ForEach(PrayerName.optionalTimes) { prayer in
                        Toggle(
                            prayer.title,
                            isOn: Binding(
                                get: { model.preferences.isVisible(prayer) },
                                set: { visible in
                                    model.update {
                                        if visible {
                                            $0.hiddenPrayers.remove(prayer)
                                        } else {
                                            $0.hiddenPrayers.insert(prayer)
                                        }
                                    }
                                }
                            )
                        )
                    }
                } header: {
                    Text("Visible prayer times")
                } footer: {
                    Text(
                        "Hiding a time does not change its notification setting."
                    )
                }
                Section {
                    ForEach(PrayerName.notifiable) { prayer in
                        Toggle(
                            prayer.title,
                            isOn: Binding(
                                get: {
                                    model.preferences.enabledPrayers.contains(
                                        prayer
                                    )
                                },
                                set: { value in
                                    Task {
                                        await model.setPrayer(
                                            prayer,
                                            enabled: value
                                        )
                                    }
                                }
                            )
                        )
                    }
                } header: {
                    Text("Prayer notifications")
                } footer: {
                    Text(
                        "Alerts are scheduled for the next 10 days. Open the app regularly to refresh them."
                    )
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
                        "Ready for future sources. Alerts will follow a successful refresh; delivery is not immediate."
                    )
                }
                Section {
                    NavigationLink("Sources and licenses") { LicensesView() }
                } header: {
                    Text("About")
                } footer: {
                    Text(
                        "Settings sync through iCloud when available. Live GPS and notification permissions stay on this device."
                    )
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
                    if let saved = model.locationService.saved(item) {
                        model.select(saved)
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

struct LicensesView: View {
    var body: some View {
        List {
            Section("Calculations") {
                Link(
                    "Adhan Swift 1.5.0",
                    destination: URL(
                        string: "https://github.com/batoulapps/adhan-swift"
                    )!
                )
                Text(
                    "Hijri baseline: Apple Foundation, Umm al-Qura. Calculated dates are not sighting confirmations."
                )
            }
            Section("Quran") {
                Link(
                    "Tanzil Project",
                    destination: URL(string: "https://tanzil.net")!
                )
                Text(license("Tanzil-LICENSE"))
            }
            Section("Library license") { Text(license("Adhan-LICENSE")) }
            Section("Events") {
                Text(
                    "Twelver Shia convention. Historical dates may differ between sources."
                )
                Link(
                    "Event references",
                    destination: URL(
                        string:
                        "https://al-islam.org/islam-faith-practice-history-sayyid-muhammad-rizvi/lesson-17-twelve-caliphs-or-imams"
                    )!
                )
            }
        }.navigationTitle("Sources and licenses")
    }

    private func license(_ name: String) -> String {
        Bundle.main.url(forResource: name, withExtension: "txt").flatMap {
            try? String(contentsOf: $0, encoding: .utf8)
        } ?? ""
    }
}

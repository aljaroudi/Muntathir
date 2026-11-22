import SwiftUI

/// The pages of the split settings layout, grouping what the single settings list shows inline.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, location, prayers, notifications, calendar, tabs, highlightColors, downloads, whatsNew

    /// The page itself, so list rows tag with the same type the selection holds.
    var id: Self {
        self
    }

    /// Tabs only apply where the tab bar can be customized.
    static var available: [SettingsPage] {
        #if os(macOS)
            allCases.filter { $0 != .tabs }
        #else
            allCases
        #endif
    }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .location: "Location"
        case .prayers: "Prayer times"
        case .notifications: "Notifications"
        case .calendar: "Calendar"
        case .tabs: "Tabs"
        case .highlightColors: "Highlight colors"
        case .downloads: "Downloads"
        case .whatsNew: "What’s New"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .location: "location"
        case .prayers: "clock"
        case .notifications: "bell"
        case .calendar: "calendar"
        case .tabs: "square.grid.2x2"
        case .highlightColors: "paintpalette"
        case .downloads: "arrow.down.circle"
        case .whatsNew: "sparkles"
        }
    }

    /// Matches the identifiers of the rows these pages replace on the single settings list.
    var accessibilityID: String {
        switch self {
        case .calendar: "month-adjustments"
        case .highlightColors: "settings-highlight-colors"
        default: "settings-\(rawValue)"
        }
    }
}

/// Settings as a list of pages beside the open page, for the iPad sidebar layout and the Mac Settings window.
struct SettingsSplitView: View {
    @AppStorage("settings.page") private var page: SettingsPage = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPage.available, selection: selection) { page in
                Group {
                    if page == .location {
                        // Shows the current location, which is also how a pick on that page confirms itself.
                        LocationSettingLabel()
                    } else {
                        Label(page.title, systemImage: page.symbol)
                    }
                }
                .accessibilityIdentifier(page.accessibilityID)
            }
            .navigationTitle("Settings")
            .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack {
                SettingsPageView(page: page)
                    .id(page)
                    .environment(\.isSplitDetailRoot, true)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The list never clears the page, so the detail always has something to show.
    private var selection: Binding<SettingsPage?> {
        Binding($page)
    }
}

private struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .general:
            Form {
                Section { AppLanguageLink() }
                WeatherSettingsSection()
                SettingsSyncFooter()
            }
            .navigationTitle("General")
        case .location:
            LocationPicker()
        case .prayers:
            Form {
                PrayerCalculationSection()
                Section { HorizontalPrayerTimesToggle() }
                PrayerVisibilitySection(header: "Visibility")
            }
            .navigationTitle("Prayer times")
        case .notifications:
            PrayerNotificationSettings(includesAppAlerts: true)
        case .calendar:
            CurrentMonthAdjustments()
        case .tabs:
            TabsSettingsView()
        case .highlightColors:
            HighlightPaletteSettings()
        case .downloads:
            DownloadsSettingsView()
        case .whatsNew:
            ReleaseNotesList(entries: ReleaseNote.history)
        }
    }
}

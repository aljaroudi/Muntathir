import AppIntents

// Phrases are a public contract with Siri: add freely, but don't remove ones people may already say.
// Each app may declare at most 10 App Shortcuts.

struct MuntathirShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextPrayerIntent(),
            phrases: [
                "Next prayer in \(.applicationName)",
                "When is the next prayer in \(.applicationName)",
                "When is \(\.$prayer) in \(.applicationName)",
            ],
            shortTitle: "Next Prayer",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: TodayPrayerTimesIntent(),
            phrases: [
                "Prayer times in \(.applicationName)",
                "Today's prayer times in \(.applicationName)",
            ],
            shortTitle: "Prayer Times",
            systemImageName: "sun.horizon"
        )
        AppShortcut(
            intent: HijriDateIntent(),
            phrases: [
                "Hijri date in \(.applicationName)",
                "What's the Hijri date in \(.applicationName)",
            ],
            shortTitle: "Hijri Date",
            systemImageName: "moon"
        )
        AppShortcut(
            intent: DailyAyahIntent(),
            phrases: [
                "Daily ayah in \(.applicationName)",
                "Today's verse in \(.applicationName)",
            ],
            shortTitle: "Daily Ayah",
            systemImageName: "text.quote"
        )
        AppShortcut(
            intent: NextIslamicEventIntent(),
            phrases: [
                "Next Islamic event in \(.applicationName)",
                "Next occasion in \(.applicationName)",
            ],
            shortTitle: "Next Event",
            systemImageName: "sparkle"
        )
        AppShortcut(
            intent: OpenSurahIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Read \(\.$target) in \(.applicationName)",
                "Open Surah \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Surah",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: OpenToolIntent(),
            phrases: [
                "Show \(\.$target) in \(.applicationName)",
                "Go to \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Tool",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: SearchInAppIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Search the Quran in \(.applicationName)",
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
    }

    /// Refreshes what Siri and Spotlight know about the app's content after launch.
    static func refresh() async {
        updateAppShortcutParameters()
        await SpotlightEntities.update()
    }
}

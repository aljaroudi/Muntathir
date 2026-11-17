# iOS → Android mapping

Spec paths are relative to `apple/Muntathir/` unless noted. Read the listed Swift files and READMEs ([app](../../apple/Muntathir/README.md), [shared](../../apple/Shared/README.md), [assets](../../apple/AssetPacks/README.md), [widgets](../../apple/MuntathirWidgets/README.md), [apple](../../apple/README.md)) before porting. Tests live in `apple/MuntathirTests/<Name>Tests.swift`.

| Feature | Swift spec | Android approach |
|---|---|---|
| App shell, tabs | `ContentView.swift`, `Core/AppTab.swift`, `Core/AppTool.swift`, `Features/TabsSettingsView.swift`, `Features/ToolDestination.swift` | `NavigationSuiteScaffold` + Nav3 per-tab stacks. Tools is an adaptive tile grid. |
| Preferences | `Services/Preferences.swift` | DataStore JSON with identical validation. `update {}` validates before commit. Backed up. |
| Onboarding | `Features/OnboardingView.swift`, `Features/AppLanguageLink.swift` | Same steps and resume. Language step is an in-app picker (AppCompat locales). |
| Location | `Services/LocationService.swift` | GPS only: coarse Fused fix named "Device location" (no reverse geocoding), offline time-zone map. No city search. Never uploaded or backed up. Qibla has its own precise session. |
| Hijri calendar | `Core/CalendarEngine.swift`, `Features/CalendarScreen.swift`, `Features/MonthAdjustmentsView.swift` | Port to `core`. Baseline = `HijrahChronology` (Umm al-Qura); verify against a 1350–1500 AH fixture exported from iOS. |
| Corrections feed | `Core/CorrectionsFeed.swift`, `Services/BackgroundRefresh.swift`, `shared/fixtures/corrections-v1.json` | `core` parser/validator + Ktor + ETag cache + WorkManager 12 h |
| Prayer times | `Core/PrayerCalculator.swift`, `Core/WidgetPrayerData.swift` | Adhan Swift 1.5.0 ported to `core/prayer/adhan`. Same Tehran Maghrib rule, Imsak, Islamic midnight. Shared prayer fixtures. |
| Notifications | `Services/NotificationService.swift`, `Services/PrayerAlertSound.swift`, `Resources/*.wav` | One chained exact alarm (next alert only), channels per category versioned by sound, no Time Sensitive toggle. Calendar-event reminder at sunset. |
| Today | `Features/TodayView.swift`, `TodayPage.swift`, `TodaySkyBackground.swift`, `SunDisc.swift`, `MoonDisc.swift`, `Core/SolarPosition.swift`, `Core/MoonPosition.swift`, `Core/SolarArc*.swift`, `Features/TodayInfoCards.swift`, `WidgetDateCards.swift` | Gradient-brush sky, sun/moon arc. Long-press a time to toggle alert/visibility. **No weather.** |
| Daily ayah + share | `Features/DailyAyahCard.swift`, `AyahBackground.swift`, `VerseActions.swift`, `Resources/quran-daily-ids.json` | Same schedule (sunset advance). Share = composable → bitmap (1080 w, ≤1920 h) → `FileProvider`. |
| Events | `Features/EventsView.swift`, repo `shared/events.json` | Same grouping; titles from JSON with `en` fallback |
| Quran | `Core/Quran*.swift`, `Services/QuranReader.swift`, `Services/QuranTranslationStore.swift`, `Features/Quran*.swift`, `Features/ReadingSizeMenu.swift`, `ReadingTextStyle.swift` | Bundled Arabic/English. Reader modes + Mushaf (QPCHafs TTF). Search + history. Translations via PAD. |
| Highlights, bookmarks | `Persistence/QuranUserSchema.swift`, `QuranUserStore.swift`, `ReadingBookmark.swift`, `BookmarkRecord.swift`, `Features/HighlightText.swift`, `HighlightEditor.swift`, `HighlightSwatch.swift`, `SavedList.swift`, `Core/HighlightPalette.swift` | Room with the same records and `winners()`. UTF-16 ranges carry over as-is. Custom selection toolbar (P1 spike). |
| Downloads | `Features/DownloadsSettingsView.swift`, `HadithDownloadsSection.swift`, `AssetDownload*.swift`, `Services/AssetPackBackend.swift`, `Resources/AssetDownloadSizes.json` | PAD backend + same per-language delete/restore |
| Hadith | `Core/Hadith*.swift`, `Services/HadithReader.swift`, `HadithAssetStore.swift`, `HadithLocalLibrary.swift`, `Features/Hadith*.swift` | Bundled SQLite driver. Paging 3 by source ID (50 window). Integrity scan cache. Route/scroll restore. |
| Supplications | `Features/SupplicationsView.swift`, `SupplicationTranslationPicker.swift`, `Core/SupplicationTranslation.swift` | Fast-follow pack, shares the Hadith reader |
| Rulings | `Core/RulingsReader.swift`, `Services/RulingsAssetStore.swift`, `Features/RulingsView.swift` | On-demand pack, list-detail |
| Smart search | `Services/SemanticSearch.swift`, `Features/MeaningSearchResults.swift`, `Core/SearchHistory.swift`, `Core/SearchRelevance.swift` | Same API and response validation |
| Figures | `Core/FigureLibrary.swift`, `Features/Figure*.swift`, repo `shared/figures/` | List-detail; family tree on Canvas |
| Qibla | `Features/QiblaView.swift`, `Services/QiblaLocationSession.swift`, `Core/QiblaAlignment.swift` | Maps Compose hybrid. Rotation-vector heading + `GeomagneticField`. ≤20 m / ≤15 s fix. 60° haptic ramp, 5° lock, 8° release. |
| Rakaat | `Core/Rakaat*.swift`, `Services/RakaatCamera.swift`, `Features/Rakaat*.swift` | CameraX `ImageAnalysis`, front camera, low res, ~10 fps, keep-latest |
| Tasbih | `Core/TasbihSession.swift`, `Features/TasbihView.swift`, `TasbihBeadScene.swift` | Canvas bead strand. 40 dp pull, 34/33/33, haptics, accessibility action, reduced motion. |
| Activity | `Core/PrayerProgress.swift`, `Core/ProgressActivity.swift`, `Persistence/ProgressStore.swift`, `Features/ProgressView.swift`, `ReadingActivity.swift` | Room. Max-not-sum merge. Timers pause in background or after 5 idle min. |
| Tips | `Features/AppTips.swift` | Material `RichTooltip` + DataStore flags |
| Credits | `Settings.bundle/Credits.plist`, `Resources/*CREDITS*`, `*LICENSE*` | In-app Sources and licenses screen (`ui/settings/CreditsScreen`) |
| Widgets | `apple/MuntathirWidgets/*.swift` | Glance: prayer (Chronometer countdown), daily ayah, Hijri date (no weather). Refresh at prayer boundaries/midnight. |
| Strings | `Localizable.xcstrings` (15 locales) | Generated `values-*/strings.xml` + plurals |
| Watch | `apple/MuntathirWatch*/` | Later (P8): Wear Compose, tiles, complications, Data Layer |
| Not ported | WeatherKit, CarPlay, iCloud KVS/CloudKit, Lock Screen widgets | — |

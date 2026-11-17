# Tasks

Status: `[ ]` todo · `[~]` in progress · `[x]` done. Take the first unblocked task. Skills live in `~/.android-studio/skills/`.

## P0 — Scaffold
Verified 2026-11-16: `just android-build` and `just android-test` pass; screenshot references recorded. The instrumented `androidTest` needs a device and hasn't run yet.

- [x] **P0.1** Gradle project in `android/` (AGP 9.5.1, Gradle 9.8.0, Kotlin 2.4.21, catalog, `core`/`app`, minSdk 26, Hilt). *Done when:* `./gradlew assembleDebug test` passes.
- [x] **P0.2** `just android-strings` / `android-build` / `android-test` / `android-screenshots` / `android-format` (Spotless + ktlint). *Done when:* recipes run from repo root.
- [x] **P0.3** Theme (dynamic color, emerald fallback, QPCHafs → TTF via fontTools, Lateef), edge-to-edge, adaptive + themed icon from the iOS SVG, backup rules. Skill: edge-to-edge.
- [x] **P0.4** `scripts/strings.py`: xcstrings + InfoPlist.strings → `values*/strings.xml` (404 strings, plurals); `generateLocaleConfig`. `android-test` runs `--check`. Colliding names get a hash suffix (e.g. `x_ah_9cf12d`); Java keywords get `_text`.
- [x] **P0.5** Fixtures moved to `shared/fixtures/` (Xcode never referenced them; the test bundle keeps its own copies). READMEs updated.
- [x] **P0.6** JUnit (`core`, reads `shared/fixtures`), Compose UI test (`androidTest`), screenshot suite (`src/screenshotTest`, references in `src/screenshotTestDefaultDebug/`; tasks `updateDebugScreenshotTestDefaultTestSuite` / `testDebugScreenshotTestDefaultTestSuite`). Skill: testing-setup.

## P1 — Core ports + spikes (parallelizable)
- [x] **P1.1** CalendarEngine + Umm al-Qura fixture (export 1350–1500 AH month starts from iOS). *Done when:* `EventsTests`, month-offset and calendar tests pass. Baseline is the Apple table itself (`shared/ummalqura.json`, from `shared/scripts/export-ummalqura.swift`), shipped as a `core` resource; JDK `HijrahChronology` matched all 1812 starts but only covers dates outside the table. Engine days are `LocalDate`s. The sunset case of `EventsTests` landed with P1.3.
- [x] **P1.2** CorrectionsFeed parser/validator. *Done when:* `FeedClientTests` cases pass. `FeedClient` (ETag, last-good cache, shared in-flight refresh) is in `core` behind a `FeedTransport`; Ktor and the AppModel stale-response guard come with P2.7.
- [x] **P1.3** PrayerCalculator on Adhan Kotlin (verify Jafari/Tehran). *Done when:* shared fixtures + `PrayerPreferencesTests`/`WidgetPrayerTests` logic pass. Deviation: Adhan Swift 1.5.0 ported into `core/prayer/adhan` instead of adhan2 (see README decisions); all three Adhan fixtures and the Mecca goldens match. `NotificationPlan` takes `NotificationOptions` until P2.1 adds Preferences.
- [x] **P1.4** Solar/Moon position, SolarArc, QiblaAlignment. *Done when:* matching tests pass. `SolarArcLayout` uses plain `ArcRect`/`ArcPoint` so `core` stays free of Android types.
- [x] **P1.5** TasbihSession, RakaatDetector/Preparation, ReadingTime, ProgressActivity merge, `HighlightSnapshot.winners`. Highlight and bookmark snapshots share `RecordSnapshot` (+ `nextModifiedAt`). `ReadingTime` strips inline Markdown with regexes (links, images, emphasis, code).
- [x] **P1.6** HadithText, QuranPageText, SearchRelevance, HighlightRange validation. Markdown via commonmark-java into a platform-neutral `StyledText` (text + UTF-16 spans); search matches apply per paragraph. `HadithText.canonical` is the reader string highlights index into. `HighlightRange` accepts any range that doesn't split a surrogate pair (like Swift) and compares quotes NFC-normalized.
- [x] **P1.7** Spike: selectable reader text with highlight ranges + custom toolbar. *Done when:* select → highlight → reopen restores the same UTF-16 ranges. `ui/reader/HighlightTextView` (TextView via `AndroidView`) + debug-only `ReaderSpikeActivity`; `HighlightSelectionTest` passes on API 37 (Arabic diacritics, cross-paragraph, emoji). Findings: the floating toolbar keeps Copy first, so Highlight is second; Espresso had to be pinned to 3.7 for API 36+ (the P0 Compose test now runs too).
- [x] **P1.8** Spike: PAD on-demand + fast-follow with `bundletool --local-testing`; Android target in `assets.py`. *Done when:* hadith.db opens via BundledSQLiteDriver with FTS5 queries. `just android-packs` (`assets.py android`: same validators, checks each module's delivery type) and `just android-local-testing` (bundletool via `./gradlew bundletool`, no install). Verified on the API 37 emulator: the on-demand hadith pack fetched, opened v8 with 145,479 hadith, Arabic/English FTS in about 1–11 ms; `HadithDatabaseTest` covers FTS on a schema-built DB. Findings: fast-follow packs aren't auto-downloaded under local testing (the app must still request them); asset-delivery-ktx 2.3.0's `requestProgressFlow` crashes with coroutines 1.11, so `PlayAssetPackBackend` uses its own listener flow.

## P2 — Daily essentials
Done 2026-11-17. `just android-test` passes. The instrumented tests (`MuntathirAppTest`, `OnboardingTest`, `CalendarTest`, `TodayTest`, `NotifierTest`) pass on the API 37 emulator.

- [x] **P2.1** Preferences DataStore + device-local store + backup rules. `Preferences`, `AppTool` and `AppModel` live in `core/app` (JVM-tested with in-memory `AppStorage`); `NotificationOptions` is gone. The app stores `files/datastore/preferences.v1.json` (backed up) and `no_backup/device.v1.json` (onboarding, GPS fix, delivered announcements). Hilt loads `AppModel` with one short blocking read per process.
- [x] **P2.2** App shell: NavigationSuiteScaffold, Nav3 stacks, Tools grid, tab shortcuts. Skills: navigation-3, adaptive. `AppNavigator` keeps one saved stack per possible tab root (Today, Tools, each tool) and scopes entry state per stack, since a route can sit in two shown stacks. Settings and its subpages use the Material list-detail scene. Shortcuts reorder with move buttons rather than drag. Tools not yet ported show a Coming soon screen.
- [x] **P2.3** Onboarding (language, location, method, notifications). Deviation: location is **GPS only** (no city search or history). A Fused coarse fix (falling back to the last known fix) is named by reverse `Geocoder` and zoned with the offline `timezonemap` (falling back to the device zone), and stored only in the device store. The language step is an in-app AppCompat picker. On each start, a granted fix refreshes the place when it moved more than 5 km or changed zone. `OnboardingTest` swaps storage and locator with Hilt.
- [x] **P2.4** Today (sky, prayer list, long-press actions, daily ayah + share).
  - `core/quran/DailyAyah` ports `DailyVerseScheduleTests`.
  - A Gradle `SharedContent` task bundles `quran.db`, `en.qarai.db`, the daily ids and surah names as assets, and the alert `.wav`s as `res/raw` (lowercased). The databases are copied to `no_backup/quran` per install or update.
  - The sky is the `TodaySky.metal` formula sampled into a vertical gradient plus seeded stars.
  - Long-press opens a menu and the same actions are TalkBack custom actions.
  - The card shows the English translation except in Arabic (the picker is P3.3).
  - Share draws the artwork off screen at 2× into a `GraphicsLayer` (1080 px wide) and shares it through a `FileProvider`.
- [x] **P2.5** Calendar, month adjustments, Events. `core/calendar/CalendarYear` builds the month sections. Names, digits and dates use ICU (Umm al-Qura month symbols, date skeletons, relative days), like Foundation. The jump sheet is a `ModalBottomSheet` grid. Event rows don't link to Figures yet (P5.4).
- [x] **P2.6** Notifications: alarms, channels, sounds, boot/time receivers, event reminders, month announcements.
  - Deviation: a **single chained alarm**. `AlarmScheduler` sets one alarm for the next alert from `NotificationPlan.alerts`. `AlarmReceiver` recomputes from current settings, posts what's due and sets the next one, so there's no 10-day/50-alert cap or list of pending alarms. The alarm is exact when `SCHEDULE_EXACT_ALARM` is granted (it's denied by default on API 34+), otherwise a 10-minute window.
  - Channels are versioned by sound (`prayers.chime.v1`); old ones are deleted. There is no Time Sensitive toggle and no adhan foreground service, since the bundled clips play fully as channel sounds.
  - `Rescheduler` follows the settings flow; `RescheduleReceiver` handles boot, time, zone, locale, package-replaced and exact-alarm permission changes.
  - `Notifier` is the `AppModel` announcer for month confirmations.
- [x] **P2.7** Feed WorkManager + launch refresh. `KtorFeedTransport` (OkHttp, 20 s timeout, size cap) backs `FeedClient` in `cache/calendar`. `AppModel.refreshFeed` has the stale-response guard (`AppModelTest`). `FeedRefreshWorker` (`@HiltWorker`) runs every 12 h on a network, and every `ON_START` refreshes too. WorkManager's default initializer is removed in favour of the Hilt factory.
- [x] **P2.8** Settings (prayers, calendar, tabs, downloads entry, language, credits).
  - Sections follow iOS order, without weather and reading (P3), as a list-detail list pane.
  - Android additions: system notification settings, an exact-alarm row when not granted, and an in-app "Sources and licenses" screen (from `Credits.plist`, the Adhan license and the adhan-sound credits, bundled as assets).
  - Notification switches ask for permission when turned on rather than on open. The sound pickers preview the sound on selection.
  - Android-only strings live in `strings_android.xml` in all 15 locales.

## P3 — Quran
- [x] **P3.1** Bundled DBs, surah list, reader modes, Mushaf.
  - `core/quran/QuranReader` holds every query from Swift `QuranReader`/`QuranDatabase` behind a tiny `QuranSql` interface, so `QuranReaderTest` runs all the Swift cases on the JVM against the iOS databases (sqlite-jdbc). `data/QuranDatabase` adapts the bundled driver and keeps connections on one thread.
  - Reader choices (`readingSizePercent`, `quranReadingMode`, translation selection, palette, Saved grouping) live in `core/app/ReadingPreferences`, stored as the backed-up `files/datastore/reading.v1.json` with the iOS keys and per-key validation. There's no cloud sync.
  - Mushaf: an RTL `HorizontalPager` of `HighlightTextView` pages. Each mushaf line is its own paragraph (joins become `\n`, so offsets don't move); verse lines are justified by a `ReplacementSpan` per space and every line gets a fixed height. Android's ICU regex rejects `(?U)`, so `QuranPageText` tokenizes by hand.
- [x] **P3.2** Search + history (+ smart search hook).
  - `QuranReader.search` (core) is the Swift algorithm and LRU cache; `ui/quran/QuranSearchModel` is shared by the surah list and the in-reader search (scoped to the surah open when search starts; results cover the reader without rebuilding it).
  - `core/text/SearchHistory` per area (max 20) in the backed-up `files/datastore/search-history.v1.json`; recent searches show while the empty field is focused.
  - `core/search/SemanticSearchClient` keeps the request/response validation; `KtorSemanticSearchTransport` posts to `BuildConfig.SEMANTIC_SEARCH_URL`: the `semanticSearchUrl` Gradle property, else the git-ignored iOS `SemanticSearchConfiguration.plist`; without either, Smart search is hidden. Nothing is sent until Smart search is tapped. `QuranSearchTest` swaps `SearchModule` for a fake.
- [ ] **P3.3** Translations pack, picker (Auto/None/explicit), Downloads screen.
- [ ] **P3.4** Highlights/bookmarks (Room), Saved list, editor.
- [ ] **P3.5** Reading timers → Activity.

## P4 — Library
- [ ] **P4.1** Hadith asset store (install index, integrity scan cache, update state).
- [ ] **P4.2** Hadith library/contents/chapter/detail, grading, introductions, number lookup, route restore.
- [ ] **P4.3** Supplications (fast-follow) + translations.
- [ ] **P4.4** Rulings.
- [ ] **P4.5** Smart search across kinds.

## P5 — Tools (parallelizable)
- [ ] **P5.1** Qibla. Skill: android-permissions-security.
- [ ] **P5.2** Rakaat tracker. Skill: camerax.
- [ ] **P5.3** Tasbih.
- [ ] **P5.4** Figures + family tree.
- [ ] **P5.5** Activity screen.

## P6 — System surfaces
- [ ] **P6.1** Glance prayer, ayah, and Hijri widgets. Skills: glance-appwidget-updates-and-memory, glance-canonical-layouts.
- [ ] **P6.2** Quick Settings tile (next prayer), app shortcuts.
- [ ] **P6.3** Verify backup/restore (`bmgr backupnow`, reinstall, restore).

## P7 — Release
- [ ] **P7.1** TalkBack, RTL, 200% font, tablets/foldables. Skill: adaptive.
- [ ] **P7.2** Baseline Profile, R8, ANR/perf pass. Skills: r8-analyzer, android-profiler, anr-audit-and-fix.
- [ ] **P7.3** Play policy audit (exact alarms, location, camera, foreground service). Skill: play-policy-insights.
- [ ] **P7.4** fastlane `supply` metadata (reuse 15-locale listings) + screenshots; internal app sharing PAD check.

## P8 — Wear OS (later)
- [ ] **P8.1** Wear app, tiles/widgets, complications, Data Layer snapshot. Skills: wear-compose-m3, wear-widgets.

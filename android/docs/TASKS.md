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
Done 2026-11-17. `just android-test` passes (193 core tests). All instrumented tests pass on the API 37 emulator, and the translation pack was verified with `just android-local-testing`.

- [x] **P3.1** Bundled DBs, surah list, reader modes, Mushaf.
  - `core/quran/QuranReader` holds every query from Swift `QuranReader`/`QuranDatabase` behind a tiny `QuranSql` interface, so `QuranReaderTest` runs all the Swift cases on the JVM against the iOS databases (sqlite-jdbc). `data/QuranDatabase` adapts the bundled driver and keeps connections on one thread.
  - Reader choices (`readingSizePercent`, `quranReadingMode`, translation selection, palette, Saved grouping) live in `core/app/ReadingPreferences`, stored as the backed-up `files/datastore/reading.v1.json` with the iOS keys and per-key validation. There's no cloud sync.
  - Mushaf: an RTL `HorizontalPager` of `HighlightTextView` pages. Each mushaf line is its own paragraph (joins become `\n`, so offsets don't move); verse lines are justified by a `ReplacementSpan` per space and every line gets a fixed height. Android's ICU regex rejects `(?U)`, so `QuranPageText` tokenizes by hand.
- [x] **P3.2** Search + history (+ smart search hook).
  - `QuranReader.search` (core) is the Swift algorithm and LRU cache; `ui/quran/QuranSearchModel` is shared by the surah list and the in-reader search (scoped to the surah open when search starts; results cover the reader without rebuilding it).
  - `core/text/SearchHistory` per area (max 20) in the backed-up `files/datastore/search-history.v1.json`; recent searches show while the empty field is focused.
  - `core/search/SemanticSearchClient` keeps the request/response validation; `KtorSemanticSearchTransport` posts to `BuildConfig.SEMANTIC_SEARCH_URL`: the `semanticSearchUrl` Gradle property, else the git-ignored iOS `SemanticSearchConfiguration.plist`; without either, Smart search is hidden. Nothing is sent until Smart search is tapped. `QuranSearchTest` swaps `SearchModule` for a fake.
- [x] **P3.3** Translations pack, picker (Auto/None/explicit), Downloads screen.
  - `packs/quran_translations` (on-demand, `Quran/<id>.db` × 12, filled by `just android-packs`). Verified with `just android-local-testing` on the API 37 emulator: choosing German downloaded the pack, installed all 12, removed the pack and showed German in the reader.
  - `core/quran/QuranTranslationFiles` + `QuranTranslationStore` port the Swift index (generation folders, atomic `index.json`, cleanup) and state machine behind a `TranslationPack` interface, so `QuranTranslationStoreTest` runs the `QuranAssetStoreTests` cases on the JVM. `data/QuranTranslations` drives it on the main thread with `PlayTranslationPack` (Play statuses → began/progress/finished/failed, plus a Wi-Fi/confirmation prompt Play needs).
  - The picker is a dialog (Auto, None, each language with a download mark); the Downloads rows use icon buttons instead of swipe actions. Today's daily ayah follows the selected installed translation.
- [x] **P3.4** Highlights/bookmarks (Room), Saved list, editor.
  - `core/highlight/QuranUserStore` ports the Swift store over a `UserRecords` table interface: winners by `modifiedAt` then record id, this installation's own rows, atomic batches, tombstones, rollback on failure. `QuranUserStoreTest` runs the Swift cases on the JVM. `ReadingBookmark` (with ruling ids and the `isHadith` coding rule) and `SavedEntry` sections are in `core` too.
  - Room 2.8 (`databases/user.db`, bundled driver, schema exported to `app/schemas`) holds `highlights`, `bookmarks` and `activity`; it's in Auto Backup. The installation id lives in `no_backup/QuranIdentity`, so a restored device writes its own rows.
  - Reader: selecting text → Highlight → editor (palette from `ReadingPreferences`; tapping a color saves); tapping highlighted text opens it (a chooser for overlaps); TalkBack gets one action per highlight. Mushaf selections save one highlight per verse. Bookmark is in each verse's menu.
  - Deviations: row actions are an overflow menu rather than swipe; palette reorder uses move buttons; Pearl is the iOS lavender as a solid swatch (no sheen). The P1.7 `ReaderSpikeActivity` and its test stay as they were. `SavedTest` covers bookmark → Saved → open/remove and select → highlight → reopen on in-memory Room.
- [x] **P3.5** Reading timers → Activity.
  - `ui/reader/trackReading` wraps `ReadingActivityClock`: it counts while the screen is resumed and the verses or pages are showing (not under search or the size sheet), pauses after 5 idle minutes, treats any pointer down as interaction, saves every 15 s and on pause or exit, with one session id per kind and the monotonic clock.
  - `data/user/ProgressStore` keeps sessions in Room's `activity` table and only stores growth (max, not sum). The Activity screen itself is P5.5. `ProgressStoreTest` and `SavedTest` cover it on device.

## P4 — Library
Done 2026-11-17. `just android-test` passes, and all 20 instrumented tests pass on the API 37 emulator.

- [x] **P4.1** Hadith asset store (install index, integrity scan cache, update state).
  - `core/hadith` ports `HadithAssetStore`, `HadithLocalLibrary`, `HadithReader`, the models and `HadithSession`. `HadithAssetStoreTest` and `HadithLocalLibraryTest` run every Swift case on the JVM against a JDBC port of `HadithFixture`; the timing case reads `build/hadith/dist/hadith.db` when it's built (cold refresh 4 ms, background scan 1.4 s).
  - There's no install index on iOS either: the pack is copied into `no_backup/Libraries/<pack>/library.db` and removed. Swift's `UserDefaults` flags (`restoring`, `cleanup`, `removed`, `validated.v1`) live in `no_backup/Libraries/<pack>.state.json`.
  - `data/library/ContentLibrary` (one per pack, from `ContentLibraries`) drives the store on the main thread. While it copies a pack or removes a book, `LibraryWorker` (expedited, `dataSync` below API 31) keeps the process alive. `StorageManager.allocateBytes` reserves twice the pack size first.
  - Deviations: the background scan adds `PRAGMA quick_check` to the probe queries. The signature has no inode (path, size, mtime). The v7-only `hadith_literal_rank` filter is skipped, since the bundled driver can't register functions and Android packs are v8. Cancellation is checked between statements, not by a progress handler.
  - Shared groundwork: `QuranSql` became `core/sql/ContentSql` (plus `SqlDriver`, `execute`, nullable columns), and `TranslationPack` became `core/assets/AssetPack` (`PlayAssetPack` per `ContentPack`). `AssetPackBackend` is bound in its own `AssetPackModule` for tests.
- [x] **P4.2** Hadith library/contents/chapter/detail, grading, introductions, number lookup, route restore.
  - `ui/hadith`: `HadithBrowseScreen` is Swift's `HadithView` for the library (`ToolRoute(Hadith)`), a book, a chapter, or a search across books (`HadithBrowseRoute`). It shows books in Four/Six/Other, the introduction, chapters by volume, narrations, number and `ch12` lookups, recent searches, and Search all books. The detail screen has highlights, bookmark, copy/share text, the English toggle, text size, gradings, previous/next and `trackReading`. Introduction and Saved screens complete it. `LibraryGate` shows the download state when the library isn't ready.
  - `HadithReaderTest` (24 cases, including the packaged `hadith.db`/`supplications.db` when built) covers `HadithReaderTests`, `HadithContentsTests`, `HadithBookGroupTests` and Swift's source-key encoding. The instrumented `HadithTest` uses a `FakeAssetPackBackend`: download → copy into the library → book → chapter → narration → bookmark → next, plus search.
  - Reader choices `hadithEnglishEnabled.v2` and `supplicationTranslation.v2` are in `ReadingPreferences` (iOS syncs them). Downloads lists Hadith (with per-book remove/restore) and Supplications.
  - Deviations: narrations load a page at a time as the list scrolls (no Previous/Next pages, no Paging 3). Session restore (`ui/hadith/HadithSessionStore`, `no_backup/hadith.session.v1.json`) reopens the open book, chapter and narration by stable source, with the first visible row and the narration's scroll offset, but not deeper result pages. Share is plain text (no image). The P1.8 spike (`data/HadithDatabase`, `AssetPackSpikeActivity`) is removed; `core/hadith` and `HadithTest` replace it.
- [x] **P4.3** Supplications (fast-follow) + translations.
  - `ui/supplications/SupplicationsScreen` is Swift's `SupplicationsView`: Saved, then each collection's supplications. Search covers title, text and translations (150 ms debounce, history area `Supplications`). The translation picker is a dialog with Auto, None and each language. Detail reuses `HadithDetailScreen` without previous/next, records `SupplicationReading`, and isn't kept in the session.
  - The fast-follow pack is requested on the first start when Play hasn't delivered it (iOS: essential). The instrumented `SupplicationsTest` covers it: the pack arrives, then open, bookmark, back, search.
- [x] **P4.4** Rulings.
  - `packs/rulings` (on-demand, `Rulings/rulings.db`, filled by `just android-packs`). `core/rulings` ports `RulingsReader` and `RulingsAssetStore`, which reads the pack in place as on iOS. `RulingsTest` runs the Swift cases on a JDBC port of `RulingsFixture`, plus the packaged `rulings.db` when it's built.
  - `ui/rulings` has the browser (disclaimer, Saved, authority and language pickers, a random sample or search with 150 ms debounce and history area `Rulings`), the detail (selectable answer, authority, Source link, sections, text size, bookmark), section and Saved screens, all list-detail. Downloads has a Rulings section. The instrumented `RulingsTest` covers download, default authority, English reader and bookmark.
  - `rulings.authority` and `rulings.languages.v2` are in `ReadingPreferences` (iOS keeps them in local `UserDefaults`); Android backs them up with the other reader choices.
- [x] **P4.5** Smart search across kinds.
  - `ui/search/SmartSearchRunner` + `smartSearchSection` are Swift's `MeaningSearchResults` for any result type: nothing is sent before consent, and a new query or scope asks again.
  - Hadith: kind `hadith`, scoped by `meaningSearchScope` (book volumes or chapter), skipped for numbers and `chN`. Each reference resolves to exactly one local narration; supplications and narrations already listed are dropped. Results show under "Smart search".
  - Rulings: kind `rulings` with the chosen authority and language. A result outside them, or missing locally, fails the search. Duplicates are dropped, and rows have no header. Supplications have no smart search, as on iOS.
  - `HadithReaderTest` and `SearchTest` cover the ambiguous lookup, the online scope and the rulings request. The instrumented `SmartSearchTest` covers both screens with a fake endpoint.
  - Quran search uses the same runner and section.
  - In two panes, every detail route (`DetailRoute`) replaces the open detail when another is opened, so the shell has one `open` rule.

## P5 — Tools (parallelizable)
Done 2026-11-17. `just android-test` passes, and all 29 instrumented tests pass on the API 37 emulator. Camera counting, compass heading, Qibla permissions, map imagery and haptics still need a physical device.

Groundwork, so the tools could be built in parallel worktrees:
- `core/progress/PrayerProgress` ports `PrayerCompletion`, `PrayerTiming`, `PrayerProgress` and `PrayerSessionRecording` (`PrayerProgressTest`).
- Room v2 adds `prayer_history` (auto-migration from v1). `ProgressStore` gains `save(PrayerCompletion)` (once per id), `prayers()` and the live `activityFlow`/`prayerFlow`.
- `core/qibla/QiblaSession` holds the `QiblaLocationSession` rules on one monotonic clock (`QiblaSessionTest` ports the platform-free cases of `QiblaLocationTests`, `QiblaAccuracyTests` and `RakaatQiblaTests`). `location/QiblaSensors` is the app interface, bound in `QiblaModule`.
- The routes (`RakaatSessionRoute`, `FigureProfileRoute`, `FigureTreeRoute`, `FigurePickerRoute`) and the shell entries are wired to placeholder screens in `ui/qibla`, `ui/rakaat`, `ui/tasbih`, `ui/figures` and `ui/activity`. Figures is a list-detail tool.

- [x] **P5.1** Qibla. Skill: android-permissions-security.
  - `location/DeviceQiblaSensors` drives `QiblaSession`: Fused high accuracy every second, and a rotation-vector heading with `GeomagneticField` declination, remapped for the display rotation. `core/qibla/QiblaGeometry` has the heading, accuracy and zoom math (`QiblaGeometryTest`).
  - The screen asks for fine + coarse location once per visit. With only approximate location it shows "Allow precise location" and Open Settings.
  - Map: Maps Compose hybrid, north-up, a geodesic line, and our own marker (no Maps location layer). The key comes from the `mapsApiKey` Gradle property or `MAPS_API_KEY` in `local.properties`. Without a key, a compass dial is shown instead (`QiblaMapModule`). `QiblaTest` fakes `QiblaModule`.
- [x] **P5.2** Rakaat tracker. Skill: camerax.
  - `core/rakaat/RakaatCapture` ports `RakaatCamera.process` (`RakaatCaptureTest`). `camera/DeviceSujoodCamera` (CameraX 1.6.2, `CameraModule`) reads front-camera Y-plane luma (BT.601, not Rec. 709) at about 320×240 and 10 fps. Once AE, AWB and AF converge it locks them through Camera2 interop, and only frames captured under the lock count.
  - The session keeps the screen on and locks orientation. It ends on `ON_STOP` or on leaving the screen, but not on a configuration change. It saves one `PrayerCompletion`, with retry. The preview is a blurred, dimmed `CameraXViewfinder` (TextureView). Any camera error ends the session, as an interruption does on iOS. `RakaatTest` fakes the camera and the Qibla sensors.
- [x] **P5.3** Tasbih.
  - `core/tasbih/TasbihBeadLoop` ports the `TasbihBeadScene` geometry (`TasbihBeadLoopTest`). `ui/tasbih` draws the loop in perspective on two Canvas layers around the count, with radial-gradient beads instead of RealityKit; the rear layer is blurred on API 31+.
  - A visit resets when the screen leaves composition (including switching away from a Tasbih tab), but not on a configuration change. Each bead records the visit's total. Reduced motion is an animator duration scale of 0. `TasbihTest` drives pulls and the accessibility action.
- [x] **P5.4** Figures.
  - `core/figures/FigureLibrary` ports the Swift library: validation, verified-only pruning, siblings, child groups, age, and search that folds diacritics and tatweel. `FigureLibraryTest` runs every Swift case and loads `shared/figures/figures.json`. `data/FigureStore` parses the bundled asset once, off the main thread.
  - `ui/figures` has the browser (recent searches, area `Figures`), the profile and the observance picker. Event and Calendar observance rows link to figures, which closes the P2.5 note.
  - Like iOS, there's no family tree for now (its layout is hard to read with several spouses). The tree screen is in this task's history (`c307b57`).
- [x] **P5.5** Activity screen. `ui/activity` is Swift `ActivityProgressView`: on-time prayers as Compose bars (rows at ≥1.5× font), reader time, bookmarks, highlights and beads, all live from `ProgressStore` and `QuranUserStore`. `Formats.readDuration` matches the Swift units. Tested by `ActivityTest`.

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

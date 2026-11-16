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
- [ ] **P1.8** Spike: PAD on-demand + fast-follow with `bundletool --local-testing`; Android target in `assets.py`. *Done when:* hadith.db opens via BundledSQLiteDriver with FTS5 queries.

## P2 — Daily essentials
- [ ] **P2.1** Preferences DataStore + device-local store + backup rules.
- [ ] **P2.2** App shell: NavigationSuiteScaffold, Nav3 stacks, Tools grid, tab shortcuts. Skills: navigation-3, adaptive.
- [ ] **P2.3** Onboarding (language, location/city search, method, notifications).
- [ ] **P2.4** Today (sky, prayer list, long-press actions, daily ayah + share).
- [ ] **P2.5** Calendar, month adjustments, Events.
- [ ] **P2.6** Notifications: alarms, channels, sounds, boot/time receivers, event reminders, month announcements.
- [ ] **P2.7** Feed WorkManager + launch refresh.
- [ ] **P2.8** Settings (prayers, calendar, tabs, downloads entry, language, credits).

## P3 — Quran
- [ ] **P3.1** Bundled DBs, surah list, reader modes, Mushaf.
- [ ] **P3.2** Search + history (+ smart search hook).
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

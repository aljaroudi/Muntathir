# Android port — handoff

Native Kotlin + Jetpack Compose port of the iOS app in [`apple/`](../../apple/): same behavior, Android-native design. These docs are the source of truth across sessions.

| Doc | Purpose |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Stack, modules, data, conventions |
| [MAPPING.md](MAPPING.md) | iOS feature → Swift spec files → Android approach |
| [PLAY_DATA_SAFETY.md](PLAY_DATA_SAFETY.md) | Play Console declarations |

## Session workflow

The phased port (P0–P8) is done; the checklist was retired. For new work:

1. Read the Swift spec files from `MAPPING.md`. **Swift code and READMEs define behavior**; these docs don't restate it.
2. Port the matching Swift tests first, then implement.
3. Run `just android-test` and note only deviations.
4. Record new decisions below.

**Parallel agents:** only for work in different packages. One task per agent, each in its own git worktree; link `web/node_modules` so the pre-commit hook runs. Merge one at a time and re-run tests.

## Decisions

### Scope
- One platform per user: no iOS↔Android sync.
- **No login, backend or Firestore.** Continuity is Android Auto Backup + device-to-device transfer only.
- No weather. Google Play only (Play Asset Delivery, no fallback).
- minSdk 26; avoid version-gated features.
- Smart search uses the existing `/v1/search` API.
- Simple, minimal code; four module types only: `core`, `app`, `wear`, asset packs (plus the test-only `:baselineprofile`).

### Core (P1)
- **Adhan:** `core/prayer/adhan` is a direct port of Adhan Swift 1.5.0 (MIT notice kept). adhan2 0.0.7 lacks Maghrib angles, the Tehran preset and failable results needed for Jafari/Tehran and high-latitude failures.
- **Umm al-Qura:** `shared/ummalqura.json` (exported by `shared/scripts/export-ummalqura.swift`) is the baseline on every platform; `HijrahChronology` only covers dates outside 1349/12–1501/1.
- **Reader text:** `AndroidView(TextView)` for selectable, highlightable text.

### Daily essentials (P2)
- **Location is GPS only:** no city search, search history or reverse geocoding (coordinates never go to a geocoder). Time zone from the offline `us.dustinj.timezonemap`, else the device zone. `SavedLocation` is coordinates + time zone in the device-local store; preferences have no saved city. Pre-release, so no stored-shape migrations. Prayer times use coarse location; only Qibla asks for precise.
- **Notification channels are versioned by sound**; no Time Sensitive toggle (`timeSensitiveNotifications` stays in the JSON for parity); no full-adhan foreground service.
- **One chained alarm** instead of a 10-day batch of 50.
- **`AppModel` lives in `core/app`** so the iOS AppModel tests run on the JVM.
- **Android-only strings** go in `values*/strings_android.xml` (watch: `wear/…/strings_wear.xml`), hand-translated for all 15 locales; `strings.py` owns only `strings.xml`, including the watch's subset (`WEAR_KEYS`).

### Quran (P3)
- **Platform-neutral stores in `core`:** `QuranSql`, `TranslationPack` and `UserRecords` are tiny interfaces so Swift tests run on the JVM against the iOS databases; the app adapts the bundled driver, PAD and Room.
- **Reader choices** are their own backed-up file (`reading.v1.json`) with the iOS sync keys and per-key validation.
- **Smart-search endpoint isn't in the repo:** the build reads the `semanticSearchUrl` Gradle property, else the git-ignored iOS `SemanticSearchConfiguration.plist`; without either the button is hidden. Nothing is sent until the user taps Smart search.
- **One DataStore per file and process** (cached in companions), since Hilt tests build several components per process.
- **The asset-pack API can be missing** (Studio and test installs): treat its errors as "not downloaded".

### Library (P4)
- **Hadith keeps full iOS parity:** each hadith-schema pack (Hadith, Supplications) is copied to `no_backup/Libraries/<pack>/library.db` and the Play pack removed, so single books can be removed and restored. Long copies run in-process, kept alive by an expedited WorkManager job; staging + atomic rename lets an interrupted install resume.
- **One SQL and pack interface:** every content DB goes through `core/sql/ContentSql` (bundled driver in the app, sqlite-jdbc in tests); every download through `core/assets/AssetPack`.
- **Android packs are always v8**, so the v7-only `hadith_literal_rank` function isn't ported (the bundled driver can't register functions).

### Tools (P5)
- **Qibla map needs a key; the compass doesn't:** Maps Compose hybrid map when `mapsApiKey` (Gradle property) or `MAPS_API_KEY` (`local.properties`) is set, otherwise a compass dial with the same ring, turn cue and haptics.
- **Qibla has its own precise session** (`ACCESS_FINE_LOCATION`), never saved. The Rakaat hint reuses it in optional mode, which never asks for permission.
- **Drawn, not 3D:** Canvas bead loop (no RealityKit), Compose bars (no chart library).
- **Rakaat light is Y-plane luma** (BT.601); the detector is relative to its own baseline, so Rec. 709 isn't needed.
- **No family tree**, matching iOS, until the layout handles several spouses.

### System surfaces (P6)
- **IBM Plex Sans Arabic is the app font** (iOS uses the system font), four weights bundled in `res/font` so it works offline, on first launch and in widgets. Reader bodies keep their fonts (`ReaderBodyFont`): Hafs for Quran text everywhere, Lateef for Hadith/supplication Arabic, system font for translations.
- **Glance lays out widgets; widget text is RemoteViews** (`widgets/WidgetText` XML layouts carrying font and dark-aware color), because Glance `Text` can't use app fonts. Rows mixing RemoteViews children use one XML layout, since Glance rows of them collapse.
- **Widgets read app state directly** (single process, Hilt entry point): no App Group mirror or Glance state store. One `WidgetUpdater` re-renders on change and keeps one alarm for the next prayer, sunset or midnight. Countdown is a launcher-driven `Chronometer`.

### Release (P7)
- **Play Console answers live in [PLAY_DATA_SAFETY.md](PLAY_DATA_SAFETY.md).**
- **No foreground-service type of our own** (WorkManager's service is untyped; it only runs below API 31). Play still needs the Data sync declaration because PAD's `ExtractionForegroundService` declares `dataSync`; keep that library service.
- **`:baselineprofile`** is a test-only module that never ships. Its output (`app/src/release/generated/`, ~7 MB) is git-ignored: run `./gradlew :app:generateReleaseBaselineProfile` (API 33+ emulator with a location, ~11 min) before a Play release; without it the release builds unprofiled.
- **Check release builds minified on a device**; R8 problems show only at runtime. Without an upload key they're debug-signed so they install.
- **Release workflow:** [shared Fastlane setup](../../fastlane/SETUP.md#android).
- **Check release layouts on device:** `ReleaseLayoutTest` (Accessibility Test Framework, English and Arabic at 200% font). Also run at tablet size: `adb shell wm size 2560x1600; adb shell wm density 320`, then `wm size reset; wm density reset`.
- **Two-pane lists don't move focus** (`shouldAutoFocusCurrentDestination = false`) and back stops at the list (`PopUntilContentChange`), since every list pane has a detail placeholder.

### Wear OS (P8)
- **`:wear` is a fourth module type** (Wear app) with the phone's application id and upload key, which the Data Layer requires. Wear OS 3+ (`minSdk 30`), not standalone: like the Apple Watch it has no settings of its own. No Hilt; one `WatchStore` object per process.
- **Sync is one Data Layer item:** the phone's `WatchSync` puts `core/wear/WatchSnapshot` (prayer settings + calendar zone, month offsets and confirmed corrections) at `/settings/v1` on every change; Play services dedupes and delivers it. The watch validates it (Swift `WatchSettings.decode`), keeps the last good one in `filesDir`, and also reads the item whenever the app comes to the front.
- **Complications and the tile render timelines** (`core/wear/WatchTimeline`): one entry per prayer or local day, so nothing runs at each boundary. The countdown is a `TimeDifferenceComplicationText` the watch face ticks itself.
- **The tile is ProtoLayout Material 3**, not Glance Wear widgets (Wear OS 6+, alpha). iOS has no tile; it fills the Smart Stack role. No live countdown on the tile (the complication has one).
- **"Open on phone" opens the Play listing** on the phone (`RemoteActivityHelper`), which shows Open or Install.
- **Release:** `fastlane android wear_beta` after `beta` uploads `:wear:bundleRelease` to the Wear OS internal track; version code = 100000 + the phone's. Enable the Wear OS form factor in Play Console first.
- **Not yet checked on a Wear emulator or watch:** sync with a paired phone, complications on a watch face, tile rendering, RTL. Compose previews render.

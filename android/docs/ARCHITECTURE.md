# Architecture

## Stack

Kotlin 2.x · AGP 9 · Compose BOM + Material 3 Expressive (dynamic color, emerald fallback) · Navigation 3 · Hilt · Coroutines/Flow · kotlinx.serialization · Room · DataStore · WorkManager · Glance · CameraX · Maps Compose (optional key) · Play Asset Delivery (`asset-delivery-ktx`) · Ktor client · Adhan Swift 1.5.0 ported into `core/prayer/adhan`.

minSdk 26, compile/target latest. Edge-to-edge, predictive back, per-app language (AppCompat `setApplicationLocales` + `locales_config.xml`). No AGSL; the Today sky uses an animated gradient `Brush`.

## Modules

```
android/
  core/    Pure Kotlin/JVM. Calendar, feed, prayer, solar/moon, qibla, text, tasbih, rakaat detector, models.
  app/     All Android code: ui/<feature>, data, assets, notifications, widgets.
  packs/   PAD modules: hadith, supplications, quran_translations, rulings.
```

## UI

- `NavigationSuiteScaffold` (bar on phones, rail on large screens) with Today, ≤3 user shortcuts, and Tools. Same rules as `AppTool.swift`.
- Nav3: one saved back stack per tab. List-detail scenes for Quran, Hadith, Rulings, Figures, Saved, Settings.
- Each screen: a ViewModel exposing one `StateFlow<UiState>` plus event functions. Composables stay stateless.
- RTL, `sp` text scaling, TalkBack labels. iOS accessibility IDs are reused as test tags.

## Data

| Kind | Store |
|---|---|
| Quran Arabic + English, events, surahs, daily ids | `assets/`, copied once to `noBackupFilesDir` |
| Hadith, Supplications, Rulings, Quran translations | PAD packs |
| Content SQLite (read-only, FTS5 `unicode61 remove_diacritics 2`) | `androidx.sqlite` **BundledSQLiteDriver** (platform SQLite lacks FTS5) |
| Preferences (`preferences.v1`, same JSON shape and validation as `Preferences.swift`) | DataStore (`files/datastore/preferences.v1.json`) behind `core/app/AppModel` |
| Device-local: onboarding step, GPS location, delivered announcements (later: hadith session) | DataStore in `no_backup/device.v1.json` |
| Reader choices (iOS `ReadingPreferencesSync` keys: text size, mode, translation, palette, Saved grouping) | DataStore `files/datastore/reading.v1.json` via `core/app/ReadingPreferences` (backed up) |
| Recent searches per area | DataStore `files/datastore/search-history.v1.json` (backed up) |
| Hadith and Supplications libraries (copied from the pack, books removable) | `no_backup/Libraries/<pack>/library.db`, flags in `no_backup/Libraries/<pack>.state.json` (`core/hadith/HadithAssetStore`) |
| Rulings | Read in place from the `rulings` pack (`core/rulings/RulingsAssetStore`) |
| Hadith reading position | `no_backup/hadith.session.v1.json` (`ui/hadith/HadithSessionStore`) |
| Downloaded Quran translations | `no_backup/QuranTranslations/<generation>/<id>.db` + atomic `index.json` (`core/quran/QuranTranslationFiles`) |
| Highlights, bookmarks, activity, prayer history (`prayer_history`, v2) | Room `databases/user.db` (bundled driver, schemas in `app/schemas`), stores in `core` behind small interfaces; installation id in `no_backup/QuranIdentity` |

Schema checks match iOS: Hadith `application_id` 1230262606, `user_version` 7–8; Rulings 1179809601 v1. Keep the iOS record design (stable IDs, `modifiedAt`, tombstones) so that restore and merge logic stays identical.

## Backup (replaces iCloud)

`dataExtractionRules` (API 31+) and `fullBackupContent` (≤30):
- Include the Room DB and the preferences DataStore.
- Exclude the device-local DataStore, `noBackupFilesDir`, PAD content, and Glance's `GlanceAppWidgetManager` file (which describes this device's home screen).

## Asset packs

| Pack | Mode | Notes |
|---|---|---|
| `hadith` | on-demand | |
| `supplications` | fast-follow | Real file path; iOS "essential" equivalent |
| `quran_translations` | on-demand | Copy validated DBs to `noBackupFilesDir`, then `removePack` (iOS App Group flow); state machine in `core/quran/QuranTranslationStore` |
| `rulings` | on-demand | |

One `AssetPackBackend` interface over `AssetPackManager`, mirroring `AssetPackBackend.swift` events. Handle the confirmation dialogs (cellular / user confirmation) and the post-update "patching" state. Pack content ships with app releases. Packaging extends `apple/AssetPacks/assets.py` with an Android target that reuses the same validators.

## System

- **State:** `core/app/AppModel` (Swift `AppModel` minus iCloud) holds `StateFlow<AppState>`, validates every change (including building a calendar) before saving, and has the feed's stale-response guard. Hilt provides one per process.
- **Location:** GPS only, with no city search and no reverse geocoding. `SavedLocation` is just coordinates and a time zone, and the UI calls it "Device location". There's no saved city in the preferences. Prayer times use a coarse Fused fix: a cached fix up to 10 minutes old, else a new one, else any cached fix. It's zoned with the offline `timezonemap`, stored device-local, and refreshed on start when the device moved more than 5 km. Qibla runs its own precise, high-accuracy session (`DeviceQiblaSensors`) that is never stored.
- **Notifications:** one chained alarm. `AlarmScheduler` sets an alarm for the next alert (exact when `SCHEDULE_EXACT_ALARM` is granted, otherwise a 10-minute window). `AlarmReceiver` posts what's due from current settings and sets the next one. `Rescheduler` follows settings, and `RescheduleReceiver` handles boot, time, zone, locale, update and permission changes. One channel per category; prayer channels are versioned by sound (`prayers.chime.v1`). The adhan clips play fully as channel sounds, so there's no foreground service.
- **Feed:** WorkManager periodic 12 h with a network constraint, plus a refresh on every `ON_START`. Ktor (OkHttp) transport, ETag + last-good cache in `cacheDir`. The host is stored in punycode.
- **Widgets:** Glance in `app/widgets` (prayer, daily ayah, Hijri date). They read `AppModel`, `QuranDatabase` and `QuranTranslations` through `WidgetEntryPoint`. Text is RemoteViews XML so it can use the app font and Hafs. `WidgetUpdater` re-renders on settings, location, corrections or translation changes, after time, zone or locale changes (`RescheduleReceiver`, `onConfigurationChanged`), and at one alarm for the next prayer, sunset or midnight. With no widgets placed it does nothing.
- **Quick Settings and shortcuts:** `NextPrayerTileService` reads the next prayer when the panel opens. Static launcher shortcuts (Quran, Qibla, Tasbih, Calendar), widgets and the tile open the app with an `OpenRequest` extra. `MainActivity` is `singleTop`, and `AppNavigator.open` selects the tool's tab, or pushes the tool onto Tools.
- **Fonts:** IBM Plex Sans Arabic (bundled) for the UI, through `Typography` and the View theme. Reader bodies keep Hafs, Lateef or the system font.

## Testing

- `core`: JUnit ports of `apple/MuntathirTests` logic tests.
- Shared fixtures move to `shared/fixtures/` for both platforms.
- `app`: Compose UI tests (Hilt test modules, no launch-flag branches in production code) and Compose Preview screenshot tests (phone/foldable/tablet × ar/en × light/dark).
- `just android-build`, `just android-test`.

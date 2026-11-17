# Android port — handoff

Native Kotlin + Jetpack Compose version of the iOS app in [`apple/`](../../apple/). It keeps the same behavior with an Android-native design. These docs are the source of truth across sessions.

| Doc | Purpose |
|---|---|
| [TASKS.md](TASKS.md) | Phased checklist. **Start here every session.** |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Stack, modules, data, conventions |
| [MAPPING.md](MAPPING.md) | iOS feature → Swift spec files → Android approach |

## Session workflow

1. Open `TASKS.md`, take the first unblocked `[ ]` task, and mark it `[~]`.
2. Read its Swift spec files in `MAPPING.md`. **The Swift code and READMEs define behavior**; these docs don't restate it.
3. Port the matching Swift tests first, then implement.
4. Run `just android-test`, mark the task `[x]`, and add a note only if something deviated.
5. Record new decisions below.

**Parallel agents:** only for tasks in different packages (e.g. P1 ports, P5 tools). One task ID per agent, each in its own git worktree. Merge one at a time and re-run tests.

## Decisions (2026-11-16)

- One platform per user: no iOS↔Android sync.
- **No login, no backend, no Firestore.** Same-OS continuity uses Android Auto Backup + device-to-device transfer. No live multi-device sync.
- No weather. Google Play only (Play Asset Delivery, no fallback). Wear OS later.
- minSdk 26. Avoid version-gated features.
- Smart search uses the existing `/v1/search` API. No new backend.
- ~~Adhan: the Kotlin port of the same library.~~ **Superseded (P1.3):** `core/prayer/adhan` is a direct port of Adhan Swift 1.5.0 (MIT notice kept). adhan2 0.0.7 lacks Maghrib angles, the Tehran preset and failable results, which the Jafari/Tehran methods and honest high-latitude failures need.
- Simple, modern, minimal code. Three module types only.
- **Umm al-Qura baseline (P1.1):** `shared/ummalqura.json`, exported from Apple's calendar by `shared/scripts/export-ummalqura.swift`, is the baseline on every platform; `HijrahChronology` only covers dates outside 1349/12–1501/1.
- **Reader text (P1.7):** `AndroidView(TextView)` for selectable, highlightable reader text.

## Decisions (2026-11-17, P2)

- **Location is GPS only.** There is no city text search and no `locations` search history. The time zone comes from an offline boundary map (`us.dustinj.timezonemap`), falling back to the device zone. The fix stays in the device-local store.
- **Notification channels are versioned by sound** and there's no Time Sensitive toggle; `timeSensitiveNotifications` stays in the JSON for parity. There's no full-adhan foreground service.
- **One chained alarm** instead of a 10-day batch of 50 requests.
- **`AppModel` lives in `core/app`**, so the iOS AppModel tests (stale feed responses, conflicts, persistence) run on the JVM.
- **Android-only strings** go in `values*/strings_android.xml`, translated by hand for all 15 locales; `strings.py` owns only `strings.xml`.

## Decisions (2026-11-17, P3)

- **Platform-neutral stores in `core`.** The Quran reader (`QuranSql`), translation downloads (`TranslationPack`) and highlights/bookmarks (`UserRecords`) sit behind tiny interfaces, so the Swift tests run on the JVM against the iOS databases; the app only adapts the bundled driver, Play Asset Delivery and Room.
- **Reader choices are their own backed-up file** (`reading.v1.json`) with the iOS sync keys and per-key validation; there's no cloud sync.
- **The smart-search endpoint isn't in the repo.** The build reads the `semanticSearchUrl` Gradle property, else the git-ignored iOS `SemanticSearchConfiguration.plist`; without either the button is hidden. Nothing is sent until the user taps Smart search.
- **DataStores are one per file and process** (cached in companions), since Hilt tests build several components in one process.
- **The asset-pack API can be missing** (Studio and test installs): the translation pack treats its errors as "not downloaded" instead of crashing.

## Decisions (2026-11-17, P4)

- **Hadith keeps full parity with iOS.** Each hadith-schema pack (Hadith, Supplications) is copied into an app-owned `no_backup/Libraries/<pack>/library.db`, then the Play pack is removed, so single books can be removed and restored. A long copy or rewrite runs in the process and is kept alive by an expedited WorkManager job. Staging and an atomic rename make an interrupted install resume on the next start.
- **One SQL and pack interface.** Every content database goes through `core/sql/ContentSql` (bundled driver in the app, sqlite-jdbc in tests), and every download through `core/assets/AssetPack`.
- **Android packs are always v8**, so the v7-only `hadith_literal_rank` SQL function isn't ported (the bundled driver can't register functions).

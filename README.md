# Muntathir · منتظِر

Native iPhone/iPad app, iOS 26+, Swift 6 and SwiftUI. Open `Muntathir.xcodeproj` and run the Muntathir scheme. Select your signing team for device builds; the iCloud Key-Value Store entitlement must be enabled for that app identifier.

## What ships in this implementation

Today focuses on the current date and prayer schedule. Calendar contains observances and the daily ayah. Qibla and Settings complete the navigation; Arabic/English localization; Adhan 1.5.0 prayer calculations; manual month-start corrections; bundled observances and daily Quran verses; saved-place iCloud preferences; local prayer notifications. A foreground GPS fix is remembered locally across launches and never uploaded to iCloud; reverse geocoding is not used.

Prayer method defaults to Tehran. Its Maghrib must be later than calculated sunset; if the library cannot produce that result, the app reports unavailable times. Ramadan Isha intervals for Umm al-Qura/Qatar use the independent Foundation baseline, not manual religious-date corrections. No prayer engine is implemented here.

Foundation's explicit Umm al-Qura calendar supplies the unconfirmed baseline. The app uses midnight in the selected location's time zone. Overrides are Gregorian month-start dates, not global offsets. Explicit neighboring anchors must allow 29/30-day months. Provisional intervening months start with baseline lengths and adjust only as needed to reach the next anchor. Baseline boundaries resume when compatible. Supported correction years: 1300–1600 AH; corrections are limited to seven days from the baseline to catch input errors.

## Corrections feed preparation

Production source catalog and endpoint are intentionally absent. Settings lists method categories as not connected. `FeedClient` and `AppModel.receive` implement retrieval and application, but no fixture is published or represented as a real announcement.

`Shared/Fixtures/corrections-v1.json` documents the version-one wire shape. Gregorian starts are date-only components interpreted in the user's location. Coverage is a union of uppercase country codes and latitude/longitude polygons, with boundaries included and date-line crossing supported. Rows require unique IDs, positive revisions, valid source identity, explicit coverage and non-calculation methods. A conflicting matching month is rejected. Select exactly one source ID; manual overrides win. HTTPS refresh uses ETag and a validated atomic envelope cache; invalid responses leave the last good copy intact.

To connect a real source later: supply a reviewed source catalog and HTTPS endpoint; create a `FeedClient`; call `refresh()` on launch/foreground and in background refresh; pass the result to `AppModel.receive`. Do not add real announcements to the binary. Source coverage and editorial publication remain separate release work.

Local prayer alerts cover ten days (at most 50 requests). Launch, foreground, preference/date/time-zone changes and opportunistic background refresh rebuild them. iOS controls background execution; opening the app regularly is necessary. Permissions are device-local. Announcement IDs/revisions deduplicate future alerts.

## Content provenance

- Quran: bundled Uthmani verses for the daily ayah. Never edit the Arabic text.
- Prayer fixtures: copied from [Adhan Swift 1.5.0](https://github.com/batoulapps/adhan-swift/tree/1.5.0/Tests/Resources/Times); original source/tolerance remains in each JSON. Test-target copies mirror `Shared/Fixtures`.
- Event date facts: [Islam: Faith, Practice & History, Lesson 17](https://al-islam.org/islam-faith-practice-history-sayyid-muhammad-rizvi/lesson-17-twelve-caliphs-or-imams), and [Fundamentals of Islam, Appendix 10](https://al-islam.org/fundamentals-islam-mirza-mahdi-pooya/appendix-10-historical-chart-14-masumeen). No prose from these books is bundled. References identify sections instead of invented page numbers.
- The catalog chooses documented Twelver dates, including 28 Safar for Imam Hasan, 17 Safar for Imam Ridha, and 5 Rajab for Imam Hadi's birth. Alternatives exist. Imam Mahdi has a birth observance only. An event fixed to day 30 is not displayed in a 29-day month; no unreviewed substitution is inferred.

## Verification

Run the Muntathir scheme's tests on an iOS 26+ simulator. Swift Testing covers month boundaries, overrides, event movement, Quran integrity, reference prayer fixtures, high latitudes, notification planning, saved-vs-live location, feed caching and coverage. XCTest covers English/Arabic navigation and manual correction.

Before distribution, complete real-device compass/calibration and notification checks, two-device signed iCloud verification, VoiceOver and accessibility-size review, and editorial review of event dates/Arabic titles. Live source publication, push delivery, Mac, Android and web are deferred.

### Verification performed

Built with Xcode 27 using Swift 6 mode and deployed to iOS 26.4.1 simulators. The full iPad suite passed (17 tests, including parameterized cases); the final English/Arabic UI rerun also passed after fixing always-visible city search. iPhone navigation and manual correction tests passed earlier. Inspected Today on iPhone and iPad. `git diff --check` passed. Device-only and editorial release checks above remain outstanding.


## Prayer and calendar refinements

Mecca regression coordinates: 21.4225° N, 39.8262° E, Asia/Riyadh. On October 17, 2026, Maghrib is 18:09 with Jafari/Qum and 18:11 with Tehran. Jafari uses Adhan's configurable engine with Fajr 16°, Maghrib 4°, and Isha 14° from https://praytimes.org/docs/methods; it is not an Adhan built-in preset.

Settings can hide Asr and Isha from the schedule and next-prayer display without changing notification choices. Both choices survive relaunch and sync with preferences. Device coordinates survive relaunch locally, without reverse geocoding or iCloud upload. City search remains available through MapKit.

The October 17 refinement build passed all 22 simulator tests, including both Mecca methods, preference migration, device-location restoration, and Arabic/English UI navigation. Physical-device heading and notification checks remain required.

## Background feed verification

Background requests use an earliest start of six hours after scheduling; iOS controls actual delivery. Foreground notification rebuilds also resubmit that request, so this is not a fixed six-hour polling timer. Prayer times are calculated locally and do not require a feed.

The background refresh path accepts an optional FeedClient. Production leaves it nil until a real HTTPS endpoint and selected source are configured. Integration tests inject a URLSession transport serving corrections-v1.json and exercise the same refresh entry point, including HTTP 200, ETag/304, malformed JSON recovery, server-error cache recovery, geographic exclusion, and confirmed calendar resolution. These are simulated HTTP responses, not proof of a deployed server or physical-device background delivery.

## iOS and CarPlay widgets

The embedded MuntathirWidgets extension provides Prayer times (countdown plus schedule). It supports small and medium Home Screen widgets; iOS 26 exposes the small versions in CarPlay. Add them through the Home Screen widget gallery, or Settings → General → CarPlay → your car → Widgets.

Open Muntathir once and choose a location. Widgets use the app's method, Asr convention, and hidden-prayer choices. The app shares only those settings and selected coordinates through the local App Group, group.com.aljaroudi.Muntathir. Both targets require that App Group in their signing profiles. GPS coordinates are not uploaded to iCloud.

The extension uses the same Adhan source and pinned dependency as the app. Timelines include three local days of prayer boundaries and midnight changes, with a requested reload after six hours. Minute-spaced timeline entries update the hours/minutes countdown without network polling. WidgetKit controls actual timeline delivery. Settings changes request a widget reload.

Simulator validation covers compilation/embedding, settings serialization, hidden prayers, midnight entries, next-day Fajr, and the exact English 1h 13m countdown format. Physical CarPlay layout and signed-device App Group provisioning still need device validation.

Sunset uses Adhan's neutral calculation parameters without Maghrib adjustments. Islamic midnight is the midpoint from that sunset to the following day's Fajr under the selected method, rounded to the nearest minute. This is not civil or solar midnight. No WeatherKit or network request is needed. Fajr, Dhuhr, and Maghrib remain visible even if old stored preferences contain them in the hidden set; Sunrise, Asr, Sunset, Isha, and Islamic midnight can be hidden. Sunset and midnight are not prayer-notification or next-prayer countdown targets.

### Git hooks

Install SwiftFormat (`brew install swiftformat`), then enable the tracked hook in each clone:

```sh
git config core.hooksPath .githooks
```

The pre-commit hook runs `swiftformat . --swift-version 6`. If Swift files differ from the index afterward, review and stage them before retrying. The hook never stages changes automatically.

The pre-push hook runs the `MuntathirTests` Swift Testing suite using Xcode on the first compatible iPhone simulator. It blocks pushes if tests fail or Xcode/a compatible simulator is unavailable. Install an iOS simulator runtime through Xcode first. Simulator tests run before pushes to keep commits fast; XCTest UI tests remain manual.

Override the simulator when needed:

```sh
TEST_DESTINATION='platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' git push
```

Daily ayah text uses the bundled QPC Hafs Uthmani font at 28 points with Dynamic Type scaling. The app registers `QPCHafs.woff2` through `UIAppFonts`; the card, shared artwork, and daily ayah widgets use its PostScript name, `KFGQPCHAFSUthmanicScript-Regula`.

## Apple Watch

The `MuntathirWatch` scheme builds the watchOS 26+ companion app and its WidgetKit extension. The iPhone target embeds both. The watch shows the visible prayer times; settings remain on the iPhone.

WatchConnectivity transfers the latest location, method, visibility settings, and Hijri month corrections. The watch caches this snapshot and calculates times locally while disconnected. Open the iPhone app after installation or configuration changes. Delivery is opportunistic; changes can take time to reach a disconnected watch. Invalid snapshots preserve the last valid settings.

Three complications are included: Hijri day/month, next prayer time, and countdown. All support inline, circular, rectangular (including Smart Stack), and corner families, with SwiftUI previews. Next-prayer and countdown displays on both platforms exclude hidden prayers and non-prayer times such as sunrise, sunset, and Islamic midnight. The medium Prayer times widget also shows enabled non-prayer times.

Enable the existing `group.com.aljaroudi.Muntathir` App Group for both watch targets when signing. App Groups share data between the watch app and its extension; WatchConnectivity transfers it between devices. Paired-device sync and watch-face rendering require device validation; the current development host has the watchOS SDK but no watchOS simulator runtime.


## Prayer counter (iPhone)

Open the **Prayer counter** tab, choose a prayer, and test placement with the phone face-up on the mat. Start with the sensor uncovered. The black screen shows the current rakaa, starting at 1; the first sujood turns it gray, and the second advances it. The final pair leaves the target number white until exit. No session history is saved.

Proximity monitoring is required; there is no camera, light-sensor, or manual fallback. A cycle requires at least 1 second near and 1 second continuously far. Leaving the app or locking the phone interrupts counting; an interrupted session cannot resume. Proximity-induced display blanking alone must not interrupt the session. Monitoring and idle-lock overrides are released when counting ends or the presentation closes.

Before release, validate mat placement, display recovery, sensor timing, lock/background interruptions, and a full four-rakaa session on physical notch and Dynamic Island iPhones. The simulator can verify unsupported-sensor UI and the pure counting state machine, but cannot establish detection accuracy. These timing thresholds are provisional until those device checks pass.


Prayer calculations now always use standard Asr. Legacy Hanafi preferences are ignored without losing location, visibility, or notification choices. Imsak defaults to a precautionary 10 minutes before calculated Fajr, adjustable from 0–120 minutes in prayer calculations; it syncs to watch and widgets. It never becomes the upcoming prayer or counter default.

The counter selects the most recent visible prayer, checking the previous day before Fajr; without a location it starts with Fajr. Settings → Prayers contains Visibility and Notifications. Fajr, Dhuhr, and Maghrib remain visible; new notification preferences enable those three, while existing choices are preserved. Opening Notifications requests device permission. All listed times can have alerts independently of visibility; the nearest 50 fit the local notification budget.

The combined countdown/schedule widget is now named **Prayer times**, retaining its existing widget kind. The redundant schedule-only widget has been removed; existing copies of that removed widget should be replaced from the widget gallery. The separate iOS **Upcoming prayer** widget has also been removed; watch complications are unchanged.


The daily ayah uses a fine-grained emerald-to-ivory background with soft lighting, shared by the app, widgets, and exported images. The background is static. Its share button opens the native share sheet with a 1080-pixel-wide image that expands vertically for the entire verse, including its verse reference. Rendering uses a fixed readable type size and light appearance, independent of the current screen settings. The displayed verse stays fixed for the local day while Today remains loaded.

`AppIcon.icon` is the shared Icon Composer source for the iPhone/iPad and Apple Watch app targets in Debug and Release. Edit it in Icon Composer; widget extensions use their containing app’s identity. The superseded standalone SVG and preview have been removed.

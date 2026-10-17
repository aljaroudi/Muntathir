# Muntathir · منتظِر

Native iPhone/iPad app, iOS 26+, Swift 6 and SwiftUI. Open `Muntathir.xcodeproj` and run the Muntathir scheme. Select your signing team for device builds; the iCloud Key-Value Store entitlement must be enabled for that app identifier.

## What ships in this implementation

Today focuses on the current date and prayer schedule. Calendar contains observances and the daily ayah. Qibla and Settings complete the navigation; Arabic/English localization; Adhan 1.5.0 prayer calculations; manual month-start corrections; bundled observances and all 6,236 Tanzil ayahs; saved-place iCloud preferences; local prayer notifications. A foreground GPS fix is remembered locally across launches and never uploaded to iCloud; reverse geocoding is not used.

Prayer method defaults to Tehran. Its Maghrib must be later than calculated sunset; if the library cannot produce that result, the app reports unavailable times. Ramadan Isha intervals for Umm al-Qura/Qatar use the independent Foundation baseline, not manual religious-date corrections. No prayer engine is implemented here.

Foundation's explicit Umm al-Qura calendar supplies the unconfirmed baseline. The app uses midnight in the selected location's time zone. Overrides are Gregorian month-start dates, not global offsets. Explicit neighboring anchors must allow 29/30-day months. Provisional intervening months start with baseline lengths and adjust only as needed to reach the next anchor. Baseline boundaries resume when compatible. Supported correction years: 1300–1600 AH; corrections are limited to seven days from the baseline to catch input errors.

## Corrections feed preparation

Production source catalog and endpoint are intentionally absent. Settings lists method categories as not connected. `FeedClient` and `AppModel.receive` implement retrieval and application, but no fixture is published or represented as a real announcement.

`Shared/Fixtures/corrections-v1.json` documents the version-one wire shape. Gregorian starts are date-only components interpreted in the user's location. Coverage is a union of uppercase country codes and latitude/longitude polygons, with boundaries included and date-line crossing supported. Rows require unique IDs, positive revisions, valid source identity, explicit coverage and non-calculation methods. A conflicting matching month is rejected. Select exactly one source ID; manual overrides win. HTTPS refresh uses ETag and a validated atomic envelope cache; invalid responses leave the last good copy intact.

To connect a real source later: supply a reviewed source catalog and HTTPS endpoint; create a `FeedClient`; call `refresh()` on launch/foreground and in background refresh; pass the result to `AppModel.receive`. Do not add real announcements to the binary. Source coverage and editorial publication remain separate release work.

Local prayer alerts cover ten days (at most 50 requests). Launch, foreground, preference/date/time-zone changes and opportunistic background refresh rebuild them. iOS controls background execution; opening the app regularly is necessary. Permissions are device-local. Announcement IDs/revisions deduplicate future alerts.

## Content provenance

- Quran: verbatim Uthmani text downloaded from [Tanzil](https://tanzil.net), with its embedded notice preserved. Full notice is also in Sources and licenses. Never edit the Arabic text.
- Prayer fixtures: copied from [Adhan Swift 1.5.0](https://github.com/batoulapps/adhan-swift/tree/1.5.0/Tests/Resources/Times); original source/tolerance remains in each JSON. Test-target copies mirror `Shared/Fixtures`.
- Event date facts: [Islam: Faith, Practice & History, Lesson 17](https://al-islam.org/islam-faith-practice-history-sayyid-muhammad-rizvi/lesson-17-twelve-caliphs-or-imams), and [Fundamentals of Islam, Appendix 10](https://al-islam.org/fundamentals-islam-mirza-mahdi-pooya/appendix-10-historical-chart-14-masumeen). No prose from these books is bundled. References identify sections instead of invented page numbers.
- The catalog chooses documented Twelver dates, including 28 Safar for Imam Hasan, 17 Safar for Imam Ridha, and 5 Rajab for Imam Hadi's birth. Alternatives exist. Imam Mahdi has a birth observance only. An event fixed to day 30 is not displayed in a 29-day month; no unreviewed substitution is inferred.

## Verification

Run the Muntathir scheme's tests on an iOS 26+ simulator. Swift Testing covers month boundaries, overrides, event movement, Quran integrity, reference prayer fixtures, high latitudes, notification planning, saved-vs-live location, feed caching and coverage. XCTest covers English/Arabic navigation and manual correction.

Before distribution, complete real-device compass/calibration and notification checks, two-device signed iCloud verification, VoiceOver and accessibility-size review, and editorial review of event dates/Arabic titles. Live source publication, push delivery, widgets, Watch, Mac, Android and web are deferred.

### Verification performed

Built with Xcode 27 using Swift 6 mode and deployed to iOS 26.4.1 simulators. The full iPad suite passed (17 tests, including parameterized cases); the final English/Arabic UI rerun also passed after fixing always-visible city search. iPhone navigation and manual correction tests passed earlier. Inspected Today on iPhone and iPad. `git diff --check` passed. Device-only and editorial release checks above remain outstanding.


## Prayer and calendar refinements

Mecca regression coordinates: 21.4225° N, 39.8262° E, Asia/Riyadh. On October 17, 2026, Maghrib is 18:09 with Jafari/Qum and 18:11 with Tehran. Jafari uses Adhan's configurable engine with Fajr 16°, Maghrib 4°, and Isha 14° from https://praytimes.org/docs/methods; it is not an Adhan built-in preset.

Settings can hide Asr and Isha from the schedule and next-prayer display without changing notification choices. Both choices survive relaunch and sync with preferences. Device coordinates survive relaunch locally, without reverse geocoding or iCloud upload. City search remains available through MapKit.

The October 17 refinement build passed all 22 simulator tests, including both Mecca methods, preference migration, device-location restoration, and Arabic/English UI navigation. Physical-device heading and notification checks remain required.

## Background feed verification

Background requests use an earliest start of six hours after scheduling; iOS controls actual delivery. Foreground notification rebuilds also resubmit that request, so this is not a fixed six-hour polling timer. Prayer times are calculated locally and do not require a feed.

The background refresh path accepts an optional FeedClient. Production leaves it nil until a real HTTPS endpoint and selected source are configured. Integration tests inject a URLSession transport serving corrections-v1.json and exercise the same refresh entry point, including HTTP 200, ETag/304, malformed JSON recovery, server-error cache recovery, geographic exclusion, and confirmed calendar resolution. These are simulated HTTP responses, not proof of a deployed server or physical-device background delivery.

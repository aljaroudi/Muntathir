# iPhone and iPad

Today (date, prayer schedule, daily ayah), Calendar, and Tools (Qibla, Tasbih, Quran, Hadith, Supplications, and more). Settings → Tabs lets users pin up to three shortcuts beside the fixed Today and Tools tabs.

## Prayer times

- Methods: Jafari/Qum, Jafari/Tehran (default), and Umm al-Qura. Asr is always standard.
- Tehran's Maghrib must fall after sunset. If the library can't produce that, the app shows times as unavailable.
- Imsak defaults to 10 minutes before Fajr (adjustable from 0 to 120) and is never the "upcoming" prayer.
- Fajr, Dhuhr, and Maghrib are always visible.
- The device's GPS fix is kept locally and never uploaded to iCloud. No reverse geocoding.

## Notifications

- Alerts are planned 10 days ahead and capped at the nearest 50 requests, the iOS local notification budget. They're rebuilt on launch, foreground, settings changes, time-zone changes, and background refresh.
- Adhan clips must stay under 30 seconds (Apple's notification-sound limit).
- Calendar-event reminders are off by default, silent, and fire once at sunset for the observances starting that evening.

## Calendar

Sources: System (Foundation Umm al-Qura), Local naked eye (Middle East, default), and Government (Saudi Arabia). Manual offsets of −2 to +2 days are stored per Hijri month; +1 starts the month a day earlier. Offsets affect observances, daily verses, widgets, and Watch, but never prayer times. See [calendar rules](../Shared/).

## Daily ayah

The verse follows the corrected Hijri month and day. It advances at sunset in the selected location, or at midnight without one. Shared images are 1080 px wide, with height sized to fit the verse. They include the translation shown but not the translator's name.

## Qibla

Qibla opens its own foreground location session. It needs Precise Location, an accuracy of 20 m or better, and a fix under 15 seconds old. It never saves coordinates. The heading glyph appears only when heading error is ≤ 10°. "Aligned" means within 5° and holds until the error passes 8°. Check permissions, heading, and imagery on a physical device. UI tests use debug-only location fixtures.

## Personal data

Highlights (each with a color and an optional note) sync through SwiftData with private iCloud. Narrations are identified by source book, chapter filename, source number, and source ID, never by SQLite row IDs, so highlights survive library rebuilds and deletion. Hadith navigation state stays on the device.

## Onboarding

Onboarding requires a city or device location. Completion is stored per device and doesn't sync. Interrupted setup resumes at the same step, including after the app restarts for a language change.

# iPhone and iPad

Today shows the current date, prayer schedule, and daily ayah. Calendar shows plain observance names, localized through `Localizable.xcstrings`; bundled JSON retains only their IDs and dates. Fresh calendar settings use naked-eye sightings from the Middle East; saved settings are preserved. Tools contains Qibla; Settings is available from the navigation toolbar; 15 interface locales (Arabic, English, French, German, Indonesian, Italian, Japanese, Malay, Persian, Russian, Spanish, Turkish, Urdu, Simplified Chinese, Traditional Chinese); Adhan 1.5.0 prayer calculations; source-relative manual month offsets (−2 through +2 days); bundled observances and daily Quran verses; saved-place iCloud preferences; local prayer notifications. A foreground GPS fix is remembered locally across launches and never uploaded to iCloud; reverse geocoding is not used.

Supported prayer methods are Jafari/Qum, Jafari/Tehran, and Umm al-Qura. New preferences default to Jafari/Tehran. Tehran's Maghrib must be later than calculated sunset; if the library cannot produce that result, the app reports unavailable times. Umm al-Qura's Ramadan Isha interval uses the independent Foundation baseline, not manual religious-date corrections. No prayer engine is implemented here.

## Prayer preferences and notifications

Prayer calculations now always use standard Asr. Legacy Hanafi preferences are ignored without losing location, visibility, or notification choices. Imsak defaults to a precautionary 10 minutes before calculated Fajr, adjustable from 0–120 minutes in prayer calculations; it syncs to watch and widgets. It never becomes the upcoming prayer.

Settings → Prayers contains Visibility and Notifications. Fajr, Dhuhr, and Maghrib remain visible; new notification preferences enable those three, while existing choices are preserved. Opening Notifications requests device permission. Prayer alerts are independent of visibility; the nearest 50 fit the local notification budget. Each alert defaults to the bundled chime (نغمة), with Alhalwachi, Ali Mulla, and Al-Sarraf adhans, bell, system sound, and silent also available. Adhan clips are under 30 seconds, Apple's notification-sound limit. One sound choice applies to all prayer and announcement notifications. The Time Sensitive switch controls interruption level; the entitlement enables the corresponding iOS setting. Sound previews play immediately in the app without requesting notification permission or scheduling a notification.

Local alerts are plannedacross ten days, limited to the nearest 50 requests. Launch, foreground, preferences, date/time-zone changes, and opportunistic background refresh rebuild them. iOS controls background execution; open the app regularly. Permissions stay device-local.

## Daily ayah

The daily ayah uses a fine-grained emerald-to-ivory background with soft lighting, shared by the app, widgets, and exported images. The background is static. Its share button opens the native share sheet with a 1080-pixel-wide image that expands vertically for the entire verse, including its verse reference. Rendering uses a fixed readable type size and light appearance, independent of the current screen settings. The displayed verse follows the corrected Islamic month and day and advances at sunset in the selected location, independent of prayer method, remaining fixed through midnight. Without a location or calculable sunset, it changes at midnight. The card reads bundled Arabic and the selected installed translation from read-only SQLite databases. Sources and licenses credits each translator. Sharing includes the translation currently shown. See [daily verse schedule](../content/daily-verses/) for the complete corrected Hijri month/day schedule.

See [widgets](../MuntathirWidgets/), [calendar and content](../Shared/), and [Apple setup](../).

## Qibla accuracy

Open **Tools → Qibla**. The compass stays blurred with a warning unless a valid true heading has a reported error of 10° or less. Missing, invalid, and nonfinite readings never enable arrow guidance. The calculated bearing from true north remains available separately. Validate interference and recovery on a physical device.

## First-run setup

Onboarding introduces the app, offers an app-language step that opens iOS Settings, requires a city or device location, lets users choose a prayer calculation method (Jafari/Tehran by default), and offers optional notification permission. Denying notifications does not block setup. Location denial or GPS failure leaves city search available; city search requires a network connection.

Completion is stored on this device and does not sync through iCloud. Existing saved locations do not bypass setup. Interrupted setup resumes at the current step and retains saved choices, including when changing the app language restarts the app. The app-language link is also available in Settings. After completion, launch opens Today.

Quran translations use [Apple-hosted on-demand packs](../AssetPacks/). Only Arabic is bundled. Auto matches preferred languages; explicit selection and None persist and also control daily ayah and widgets. Downloads never block Arabic reading.

## Calendar sources and month offsets

Settings offers System calendar (Apple Foundation Umm al-Qura), Local naked eye (Middle East), and Government announcement (Saudi Arabia). Country names follow the app locale. Source selection applies worldwide and is independent of GPS coverage. With no published announcement, the system calendar provides dates.

Calendar’s Adjust this month sheet stores an offset for that Hijri month. Positive values advance the displayed Hijri date: +1 starts the month one Gregorian day earlier than the selected source. The sheet previews the resulting start date. Zero removes that month’s adjustment. All months remain 29 or 30 days; unconfirmed neighboring boundaries may move, and conflicting anchors are rejected without changing saved choices. Offsets survive source changes and apply to observances, dated daily verses, widgets, and Watch snapshots. Prayer calculations and prayer notification times remain unchanged.

Legacy absolute month corrections reset to zero; unrelated settings remain intact. The production feed refreshes on launch/foreground, source changes, and background refresh, using ETag and a last-good cache. Month notifications follow successful refreshes rather than immediate push delivery.

Today reuses current App Group weather on launch and refreshes every 15 minutes while displayed. App and widget retries back off for five minutes after failure, retaining only matching readings younger than one hour. WidgetKit controls actual Home Screen refresh timing; expired weather is hidden rather than shown as current.

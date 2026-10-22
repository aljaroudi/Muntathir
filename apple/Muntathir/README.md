# iPhone and iPad

Today shows the current date, prayer schedule, and daily ayah. Calendar contains observances. Tools contains Qibla; Settings is available from the navigation toolbar; Arabic/English localization; Adhan 1.5.0 prayer calculations; manual month-start corrections; bundled observances and daily Quran verses; saved-place iCloud preferences; local prayer notifications. A foreground GPS fix is remembered locally across launches and never uploaded to iCloud; reverse geocoding is not used.

New preferences default to Jafari/Qum; legacy preferences without a method retain Tehran. Tehran's Maghrib must be later than calculated sunset; if the library cannot produce that result, the app reports unavailable times. Ramadan Isha intervals for Umm al-Qura/Qatar use the independent Foundation baseline, not manual religious-date corrections. No prayer engine is implemented here.

## Prayer preferences and notifications

Prayer calculations now always use standard Asr. Legacy Hanafi preferences are ignored without losing location, visibility, or notification choices. Imsak defaults to a precautionary 10 minutes before calculated Fajr, adjustable from 0–120 minutes in prayer calculations; it syncs to watch and widgets. It never becomes the upcoming prayer.

Settings → Prayers contains Visibility and Notifications. Fajr, Dhuhr, and Maghrib remain visible; new notification preferences enable those three, while existing choices are preserved. Opening Notifications requests device permission. Prayer alerts are independent of visibility; the nearest 50 fit the local notification budget.

Local alerts are plannedacross ten days, limited to the nearest 50 requests. Launch, foreground, preferences, date/time-zone changes, and opportunistic background refresh rebuild them. iOS controls background execution; open the app regularly. Permissions stay device-local.

## Daily ayah

The daily ayah uses a fine-grained emerald-to-ivory background with soft lighting, shared by the app, widgets, and exported images. The background is static. Its share button opens the native share sheet with a 1080-pixel-wide image that expands vertically for the entire verse, including its verse reference. Rendering uses a fixed readable type size and light appearance, independent of the current screen settings. The displayed verse stays fixed until midnight in the selected location’s time zone. The card reads Arabic and English directly from the bundled `db.db` and displays Ali Quli Qara’i’s translation below Arabic. Sources and licenses credits the translator. The share image retains its Arabic-only layout. See [dated schedule preparation](../content/daily-verses/) for the pending migration to a complete corrected Hijri month/day schedule.

See [widgets](../MuntathirWidgets/), [calendar and content](../Shared/), and [Apple setup](../).

## Qibla accuracy

Open **Tools → Qibla**. The compass stays blurred with a warning unless a valid true heading has a reported error of 10° or less. Missing, invalid, and nonfinite readings never enable arrow guidance. The calculated bearing from true north remains available separately. Validate interference and recovery on a physical device.

## First-run setup

Onboarding introduces the app, requires a city or device location, lets users choose a prayer calculation method (Jafari/Qum by default), and offers optional notification permission. Denying notifications does not block setup. Location denial or GPS failure leaves city search available; city search requires a network connection.

Completion is stored on this device and does not sync through iCloud. Existing saved locations do not bypass setup. Interrupted setup restarts at Welcome and retains saved choices. After completion, launch opens Today.

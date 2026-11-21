# iOS and CarPlay widgets

| Widget | Sizes | Notes |
| --- | --- | --- |
| Prayer times | Small (also shown in CarPlay) | Countdown and schedule. No network. |
| Daily ayah | Medium, Lock Screen rectangular | Medium shows the installed translation below the Arabic; Lock Screen is Arabic only. |
| Calendar | Home Screen, Lock Screen | The Home Screen size adds weather (WeatherKit); Lock Screen shows dates only. |

## Setup

Open the app once and choose a location. The app shares its settings, calendar corrections, and coordinates with the widgets through the App Group `group.com.aljaroudi.Muntathir`, which both targets need in their signing profiles. The extension also needs WeatherKit.

## Behavior

- Prayer timelines cover three days and request a reload after six hours. Settings changes reload the widgets.
- Islamic midnight is the midpoint from sunset to the next day's Fajr. Sunset and midnight are never countdown targets.
- Ayah timelines preload the current verse plus seven midnights. The verse follows the corrected Hijri date.
- Only Arabic and English Quran text are bundled. Other translations come from the App Group, and widgets never start downloads.
- Weather is cached in the App Group. Readings older than one hour are hidden, and a failed refresh waits five minutes before retrying.

Check CarPlay layouts and signed App Group provisioning on a real device.

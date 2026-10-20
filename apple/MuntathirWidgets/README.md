# iOS and CarPlay widgets

The embedded MuntathirWidgets extension provides Prayer times (countdown plus schedule). It supports small and medium Home Screen widgets; iOS 26 exposes the small versions in CarPlay. Add them through the Home Screen widget gallery, or Settings → General → CarPlay → your car → Widgets.

Open Muntathir once and choose a location. Widgets use the app's method, Imsak offset, and hidden-prayer choices. The app shares only those settings and selected coordinates through the local App Group, group.com.aljaroudi.Muntathir. Both targets require that App Group in their signing profiles. GPS coordinates are not uploaded to iCloud.

The extension uses the same Adhan source and pinned dependency as the app. Timelines include three local days of prayer boundaries and midnight changes, with a requested reload after six hours. Minute-spaced timeline entries update the hours/minutes countdown without network polling. WidgetKit controls actual timeline delivery. Settings changes request a widget reload.

Simulator validation covers compilation/embedding, settings serialization, hidden prayers, midnight entries, next-day Fajr, and the exact English 1h 13m countdown format. Physical CarPlay layout and signed-device App Group provisioning still need device validation.

Sunset uses Adhan's neutral calculation parameters without Maghrib adjustments. Islamic midnight is the midpoint from that sunset to the following day's Fajr under the selected method, rounded to the nearest minute. This is not civil or solar midnight. No WeatherKit or network request is needed. Fajr, Dhuhr, and Maghrib remain visible even if old stored preferences contain them in the hidden set; Sunrise, Asr, Sunset, Isha, and Islamic midnight can be hidden. Sunset and midnight are not next-prayer countdown targets.

Prayer times retains its existing widget kind. Schedule-only and Upcoming prayer widgets were removed; replace old copies through the widget gallery. Watch complications remain available.

Daily ayah widgets share the bundled Quran font and static emerald-to-ivory artwork with the app. See [iPhone/iPad behavior](../Muntathir/) and [Apple setup](../).

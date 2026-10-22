# Calendar, corrections, and content

## Calendar rules

Foundation's explicit Umm al-Qura calendar supplies the unconfirmed baseline. The app uses midnight in the selected location's time zone. Overrides are Gregorian month-start dates, not global offsets. Explicit neighboring anchors must allow 29/30-day months. Provisional intervening months start with baseline lengths and adjust only as needed to reach the next anchor. Baseline boundaries resume when compatible. Supported correction years: 1300–1600 AH; corrections are limited to seven days from the baseline to catch input errors.

## Corrections feed

Production source catalog and endpoint are intentionally absent. Settings lists method categories as not connected. `FeedClient` and `AppModel.receive` implement retrieval and application, but no fixture is published or represented as a real announcement.

[`Fixtures/corrections-v1.json`](Fixtures/corrections-v1.json) documents the version-one wire shape. Gregorian starts are date-only components interpreted in the user's location. Coverage is a union of uppercase country codes and latitude/longitude polygons, with boundaries included and date-line crossing supported. Rows require unique IDs, positive revisions, valid source identity, explicit coverage and non-calculation methods. A conflicting matching month is rejected. Select exactly one source ID; manual overrides win. HTTPS refresh uses ETag and a validated atomic envelope cache; invalid responses leave the last good copy intact.

To connect a real source later: supply a reviewed source catalog and HTTPS endpoint; create a `FeedClient`; call `refresh()` on launch/foreground and in background refresh; pass the result to `AppModel.receive`. Do not add real announcements to the binary. Source coverage and editorial publication remain separate release work.

## Background refresh

Background requests use an earliest start of six hours after scheduling; iOS controls actual delivery. Foreground notification rebuilds also resubmit that request, so this is not a fixed six-hour polling timer. Prayer times are calculated locally and do not require a feed.

The background refresh path accepts an optional FeedClient. Production leaves it nil until a real HTTPS endpoint and selected source are configured. Integration tests inject a URLSession transport serving corrections-v1.json and exercise the same refresh entry point, including HTTP 200, ETag/304, malformed JSON recovery, server-error cache recovery, geographic exclusion, and confirmed calendar resolution. These are simulated HTTP responses, not proof of a deployed server or physical-device background delivery.

## Content provenance

- Quran: `Resources/Quran/quran.db` contains all 6,236 Arabic verses; each translation is a sibling `<id>.db` keyed by the same verse `index`. The daily ayah temporarily cycles through 31 numeric database IDs, changing at midnight in the selected location’s time zone. A complete dated dataset will select by corrected Hijri month/day; see [daily verse schedule](../content/daily-verses/). Never edit the Arabic text.
- Prayer fixtures: copied from [Adhan Swift 1.5.0](https://github.com/batoulapps/adhan-swift/tree/1.5.0/Tests/Resources/Times); original source/tolerance remains in each JSON. Test-target copies mirror `Shared/Fixtures`.
- Event date facts: [Islam: Faith, Practice & History, Lesson 17](https://al-islam.org/islam-faith-practice-history-sayyid-muhammad-rizvi/lesson-17-twelve-caliphs-or-imams), and [Fundamentals of Islam, Appendix 10](https://al-islam.org/fundamentals-islam-mirza-mahdi-pooya/appendix-10-historical-chart-14-masumeen). No prose from these books is bundled. References identify sections instead of invented page numbers.
- The catalog chooses documented Twelver dates, including 28 Safar for Imam Hasan, 17 Safar for Imam Ridha, and 5 Rajab for Imam Hadi's birth. Alternatives exist. Imam Mahdi has a birth observance only. An event fixed to day 30 is not displayed in a 29-day month; no unreviewed substitution is inferred.

Prayer fixtures remain duplicated in the test bundle because tests load bundled resources. Keep both copies identical. See [test coverage](../MuntathirTests/).

## Event titles

Bundled events store localized titles in a `titles` dictionary keyed by language tags, for example `"titles": {"en": "Islamic New Year", "ar": "رأس السنة الهجرية"}`. Add another language entry without changing the Swift model. Keep English as the default title for every bundled event.

`IslamicEvent.title(locale:)` uses the view's locale. Lookup tries the exact locale, language with script, base language, then English; if none contains a nonblank title, it returns the event ID. Foundation normalizes tags (including case, underscores, and redundant scripts), and duplicate lookup candidates are skipped. Other locale settings, such as calendar and numbering system, do not select a different title.

# Calendar, corrections, and content

## Calendar rules

Foundation's explicit Umm al-Qura calendar supplies the unconfirmed baseline. The app uses midnight in the selected location's time zone. Manual adjustments are stored as Hijri month/offset pairs, limited to −2 through +2 days. A positive offset advances the Hijri date by moving its start earlier relative to the source calendar. The engine derives Gregorian anchors before applying manual precedence; these are not global offsets. Explicit neighboring anchors must allow 29/30-day months. Provisional intervening months start with baseline lengths and adjust only as needed to reach the next anchor. Baseline boundaries resume when compatible. Supported correction years: 1300–1600 AH; corrections are limited to seven days from the baseline to catch input errors.

## Corrections feed

Production uses https://منتظر.com/calendar/corrections-v1.json. The existing website serves a valid empty version-one feed until real announcements are supplied. System calendar has no source ID. Local naked eye uses `naked-eye-middle-east`; government sources use `government-SA`, `government-KW`, `government-BH`, `government-OM`, `government-AE`, and `government-QA`. Country names use Foundation locale display names. Fixtures remain test data and are never published as real announcements.

[`Fixtures/corrections-v1.json`](Fixtures/corrections-v1.json) documents the version-one wire shape. Gregorian starts are date-only components interpreted in the user's location. Coverage is a union of uppercase country codes and latitude/longitude polygons, with boundaries included and date-line crossing supported. Rows require unique IDs, positive revisions, valid source identity, explicit coverage and non-calculation methods. Coverage remains validated for version-one compatibility, but source selection applies worldwide. Rows must match the selected source ID and its expected method. A conflicting matching month is rejected. Select exactly one source ID; manual offsets win. HTTPS refresh uses ETag and a validated atomic envelope cache; invalid responses leave the last good copy intact.

To publish an announcement, update the hosted JSON with reviewed rows using a supported source ID and matching method (`nakedEye` or `government`). Retain schema version 1, valid coverage metadata, unique IDs, and positive revisions. Do not add real announcements to the binary. Editorial verification remains separate release work.

## Background refresh

Background requests use an earliest start of 12 hours after scheduling; iOS controls actual delivery. Foreground notification rebuilds also resubmit that request, so this is not a fixed 12-hour polling timer. Prayer times are calculated locally and do not require a feed.

The background refresh path accepts an injected FeedClient. Production constructs the HTTPS client; tests use isolated mock transports. Launch/foreground and source changes use the same refresh path. Integration tests inject a URLSession transport serving corrections-v1.json and exercise the same refresh entry point, including HTTP 200, ETag/304, malformed JSON recovery, server-error cache recovery, worldwide source matching, and confirmed calendar resolution. These are simulated HTTP responses, not proof of a deployed server or physical-device background delivery.

## Content provenance

- Quran: `Resources/Quran/quran.db` contains all 6,236 Arabic verses; translation source files are sibling `<id>.db` files keyed by the same verse `index`, delivered as [on-demand asset packs](../AssetPacks/) rather than bundled. The daily ayah temporarily cycles through 31 numeric database IDs, changing at midnight in the selected location’s time zone. A complete dated dataset will select by corrected Hijri month/day; see [daily verse schedule](../content/daily-verses/). Never edit the Arabic text.
- Prayer fixtures: copied from [Adhan Swift 1.5.0](https://github.com/batoulapps/adhan-swift/tree/1.5.0/Tests/Resources/Times); original source/tolerance remains in each JSON. Test-target copies mirror `Shared/Fixtures`.
- Event date facts: [Islam: Faith, Practice & History, Lesson 17](https://al-islam.org/islam-faith-practice-history-sayyid-muhammad-rizvi/lesson-17-twelve-caliphs-or-imams), and [Fundamentals of Islam, Appendix 10](https://al-islam.org/fundamentals-islam-mirza-mahdi-pooya/appendix-10-historical-chart-14-masumeen). No prose from these books is bundled. References identify sections instead of invented page numbers.
- The catalog chooses documented Twelver dates, including 28 Safar for Imam Hasan, 17 Safar for Imam Ridha, and 5 Rajab for Imam Hadi's birth. Alternatives exist. Imam Mahdi has a birth observance only. An event fixed to day 30 is not displayed in a 29-day month; no unreviewed substitution is inferred.

Prayer fixtures remain duplicated in the test bundle because tests load bundled resources. Keep both copies identical. See [test coverage](../MuntathirTests/).

## Event titles

Bundled events store localized titles in a `titles` dictionary keyed by language tags, for example `"titles": {"en": "Islamic New Year", "ar": "رأس السنة الهجرية"}`. Add another language entry without changing the Swift model. Keep English as the default title for every bundled event.

`IslamicEvent.title(locale:)` uses the view's locale. Lookup tries the exact locale, language with script, base language, then English; if none contains a nonblank title, it returns the event ID. Foundation normalizes tags (including case, underscores, and redundant scripts), and duplicate lookup candidates are skipped. Other locale settings, such as calendar and numbering system, do not select a different title.

## Migration and source changes

Preferences store `monthOffsets` (month and days); the old `overrides` field is ignored. Unknown legacy source IDs resolve to System calendar. Switching sources clears old confirmations and validates the retained offsets against the source baseline before committing. Incoming feeds are validated with saved offsets before replacing the applied confirmations. Conflicting updates leave the last applied calendar intact. Responses started before a settings/location change are ignored. Valid cached announcements restore synchronously on launch so source-relative offsets remain applied while networking is unavailable. Widgets and Watch receive resolved manual/confirmed anchors through the existing snapshot format.

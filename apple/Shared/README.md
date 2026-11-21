# Calendar, corrections, and content

## Calendar rules

- Baseline: Foundation's Umm al-Qura calendar, with days starting at midnight in the selected location's time zone.
- Manual adjustments are Hijri month/offset pairs from −2 to +2 days. A positive offset moves the month start earlier. Manual offsets take precedence over feed confirmations.
- Months are always 29 or 30 days. Conflicting anchors are rejected and the last applied calendar is kept.
- Supported years are 1350–1500 AH. Corrections more than seven days from the baseline are rejected as input errors.

## Corrections feed

Production URL: https://منتظر.com/calendar/corrections-v1.json. Source IDs:

| Source | ID | Method |
| --- | --- | --- |
| System calendar | (none) | — |
| Local naked eye | `naked-eye-middle-east` | `nakedEye` |
| Saudi government | `government-SA` | `government` |

[`shared/fixtures/corrections-v1.json`](../../shared/fixtures/corrections-v1.json) documents the wire shape. Gregorian starts are date-only and read in the user's time zone. Rows need unique IDs, positive revisions, a valid source ID with its matching method, and coverage metadata. Coverage is still validated, but sources apply worldwide.

The app fetches the feed on launch, on foreground, on source changes, and in background refresh. Requests use ETag, and an invalid response keeps the last good cache.

To publish an announcement, add reviewed rows to the hosted JSON and keep schema version 1. Never put real announcements in the app binary.

Background refresh asks to run no sooner than 12 hours out, and iOS decides when it actually runs. Integration tests serve the feed through an injected URLSession transport, so they don't prove a deployed server works.

## Content

- Quran: `Resources/Quran/quran.db` holds all 6,236 Arabic verses. Translations are sibling `<id>.db` files keyed by verse `index` (see [asset packs](../AssetPacks/)). Never edit the Arabic text.
- Events: repository-root `shared/events.json` stores `id`, `month`, `day`, an optional `year` (AH; negative means before the Hijra), and a `title` dictionary keyed by language code. `en` is required and is the fallback.
- Prayer fixtures: copied from [Adhan Swift 1.5.0](https://github.com/batoulapps/adhan-swift/tree/1.5.0/Tests/Resources/Times). The test bundle carries a copy of [`shared/fixtures`](../../shared/fixtures/); keep the two identical.

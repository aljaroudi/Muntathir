# Religious figures

- `figures.json`: the editable dataset. Its `$schema` points to the adjacent schema, so editors with JSON Schema support validate it.
- `schema.json`: JSON Schema (Draft 2020-12).

The app bundles the dataset, so changes ship with app updates. The web build publishes the verified subset at `/figures/figures.json` and `/figures/schema.json`. That feed keeps legacy string notes and citation arrays so older app versions keep working.

## People

- Give each person a permanent, unique ID (for example `prophet-muhammad`). Names are never identifiers.
- Set `verified: true` after review. Unverified people, and any relationships that involve them, are hidden from the app and the web feed.
- Add every figure's ID to exactly one `browser_groups[].figure_ids`. That array sets the order of the app's sections.
- Add relatives even when little is known about them. Use empty arrays for unknown values, and never invent them.
- `display_names`, `notes`, `birth_place`, and `death_place` map language tags to text.
- `names` maps language tag (for example `ar` or `ar-Latn`) to name kind: `name`, `full_name` (one string each), and `surname`, `kunya`, `laqab`, `nisba`, `nickname`, `title` (string arrays).

## Family links

- `parentages`: each entry is one claim about a child's parents. `father_id` or `mother_id` may be `null`, but not both. `kind` is biological, adoptive, or foster. Ancestry must not contain cycles.
- `unions`: each marriage gets its own ID, including a remarriage to the same person. A parentage may reference a union, and if it does, its parents must match that union's partners. Parenthood alone doesn't imply marriage.
- Store competing accounts as separate parentage entries, and never merge them. More than one accepted biological pair for the same child needs review.
- Never store sibling or child lists; they're derived from biological parentages. Siblings are full when both known parents match, half when exactly one does, and of uncertain degree when a parent is unknown. Never assume uncertain siblings are half-siblings.

## Dates

`birth_dates` and `death_dates` are arrays of independent claims, so keep competing reports side by side. Each claim records its `original` wording, calendar, era, precision, evidence, and optional notes.

- Calendars and eras: `gregorian`/`julian` use `CE`/`BCE`; `hijri` uses `AH`/`BH`.
- `start` holds a positive year plus an optional month and day. There is no year zero.
- Precision: `exact` (only the given parts are asserted), `approximate`, or `range` (needs an inclusive `end` in the same calendar and era). In BH/BCE, larger years come first.
- Never convert Hijri dates silently. If you add a conversion, explain it in the notes.
- The schema only checks component bounds, so review day validity and ordering by hand.

The app estimates age from the first accepted birth/death pair in the same calendar. It doesn't convert lunar years to solar years.

## Evidence

Parentages, unions, and dates carry a `status` and a `citations` array:

- `status` is `accepted`, `disputed`, or `unreviewed`. It's an editorial judgment, not a claim of consensus.
- Each citation has a source ID, a precise `locator`, and an optional short quote.
- Keep unsourced entries `unreviewed`.
- Record differing traditions in the notes and keep each one's citations.

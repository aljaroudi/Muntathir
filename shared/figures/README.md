# Religious figures

Use JSON as the editable source format, matching `shared/events.json`. The web build serves the published subset of the canonical dataset at `/figures/figures.json` and its schema at `/figures/schema.json`. The app bundles the dataset and loads it offline. New data ships with app updates. The web feed retains legacy string notes and required citation arrays for previously released apps.

Set `verified: true` on a person after review. Missing or false flags exclude that person from app browsing and the web feed. Relationships involving excluded people are also omitted. The source stays valid JSON, so editors with JSON Schema support can still check all records.

- `figures.json`: production dataset, starting with the Prophet Muhammad and his family.
- `schema.json`: JSON Schema (Draft 2020-12) describing the format.

## Adding people

Assign every person a permanent, unique ID, for example `prophet-muhammad`. Reuse that ID everywhere; names are not identifiers. Add relatives as people even if little is known about them. Use empty arrays for unknown names or dates; do not invent values.

`display_names` maps language tags to reader-facing names, such as `ar` and `en`. `names` groups arrays of strings by language tag and name kind: `name`, `full_name`, `surname`, `kunya`, `laqab`, `nisba`, `nickname`, or `title`. A historical figure need not have a modern surname. Arabic spellings and transliterations can coexist under separate language keys (for example `ar` and `ar-Latn`). Person `notes` maps language tags to reader-facing notes. The `name` and `full_name` fields contain one string each. Other name kinds contain string arrays.

Optional `birth_place` and `death_place` map language tags to place names. Omit unknown places. The app computes a numeric age estimate from the first accepted birth/death year pair in the same calendar (falling back to recorded alternatives when none are accepted). The calculation accounts for the absence of year zero and does not convert lunar years to solar years. Missing or incompatible dates show no age.

## Family links

Each `parentages` entry records one claim about a child's parent pair. `father_id` and `mother_id` reference people; either can be `null` when unknown, but not both. `kind` distinguishes biological, adoptive, and foster relationships. A parent must never be their own child, and ancestry must not contain cycles.

For biological relationships, derive:

- Parents: the child's selected parentage claim.
- Children: parentage entries containing that person's ID. Each entry carries the child's other parent, including an explicit unknown.
- Full siblings: different children with the same two known parents.
- Half-siblings: different children with one shared known parent and different known parents on the other side.
- Siblings of uncertain degree: a shared known parent where the other parent is unknown for either child. Never assume these are half-siblings.

Do not store duplicate sibling or child lists on people. Adoptive and foster links must remain separate from biological sibling calculations.

`unions` records each marriage or reported partnership independently, using its partner IDs and relationship kind. Multiple marriages, including remarriage to the same person, use separate union IDs. A parentage may reference a union, but does not require one: parenthood alone does not establish marriage. When linked, its two parents must match that union's partners.

Alternative parentage accounts use separate entries for the same child, with their own evidence. Readers must select a consistent account before deriving a family tree; never merge disputed parent pairs into one family. Multiple accepted biological pairs for one child require review.

## Dates and uncertainty

`birth_dates` and `death_dates` are arrays of independent claims. Keep competing reports rather than replacing one with a preferred date. Each claim preserves its `original` wording, calendar, era, precision, evidence, and optional notes.

- Calendars: `gregorian`, `julian`, `hijri`.
- Eras: `CE`/`BCE` for Gregorian or Julian; `AH`/`BH` for Hijri.
- `start` contains a positive year and optional month/day. Omit unknown components. There is no year zero.
- `exact` means the supplied components are asserted directly, not that an omitted day is known. `approximate` preserves an estimate. `range` requires an inclusive `end` in the same calendar and era.
- Order ranges chronologically; in BH/BCE, larger year numbers come first. Claims spanning eras can retain the wording in notes pending a richer representation.

Do not silently convert Hijri dates to Gregorian or collapse differing calendars into separate historical reports. If supplying a conversion, explain the method and relationship in notes. Calendar-specific day validity and chronological ordering require semantic validation; the schema only checks component bounds.

## Evidence and validation

Parentages, unions, and date claims carry `status` (`accepted`, `disputed`, or `unreviewed`) and a `citations` array. Status is an editorial assessment, not a claim of universal agreement. Each citation links to a source ID and a `locator` (page, volume, section, or other precise reference); an optional short quote preserves relevant wording. Sources can record title, author, edition, URL, and notes.

Date citations may be omitted; Swift treats them as an empty array. Claim notes map language tags to text. An empty citations array is allowed while collecting data. Keep unsourced entries `unreviewed`. Record differing traditions and interpretations in notes and preserve their respective citations.

Open `figures.json` in an editor with JSON Schema support. Its `$schema` points to the adjacent schema. Review cross-record references and historical date ranges when editing.

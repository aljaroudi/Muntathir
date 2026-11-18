# Basic offline search and search-screen responsiveness

Quran and Hadith passage search is live: results update 250 ms after typing
pauses, and Submit applies immediately. The last word matches as a prefix once
it has three letters (`صلا` finds `صلاه`; `pray` finds `prayer`), ranked after
whole-word matches. Two-letter prefixes stay whole-word because `"ال"*` matches
nearly every narration. Infixes (`بالصلاه` for `صلاه`) and typos still do not
match. Earlier results stay on screen until new ones arrive. Meaning search
remains an explicit online action. Search history is recorded on Submit or when
a result is opened, never per keystroke.

## Live search changes (November 2026)

Measured with the sqlite3 CLI on the 354 MB Hadith database (Mac, warm): FTS
lookups take 1–20 ms, prefix lookups included, and ranking the largest result
sets (`الله`, `قال*`, about 120k ids) takes about 0.2 s. `"ال"*` took 0.35–0.76 s,
which is why prefixes start at three letters. These SQL timings exclude Swift
processing, rendering, and typing latency; they are not end-to-end measurements.
The changes also target repeated Swift work:

- Highlighting built a `String` and a `Locale` for every character. It now
  reuses one folding locale and memoizes each character's key, with output
  identical to the old implementation (covered by `SearchPreviewTests`).
- Hadith previews parsed the whole narration as markdown (up to 406k
  characters). Long sources are now cut to a window around the first match
  before parsing.
- The Hadith screen rescored about 12k chapter titles and the catalog on every
  keystroke on the main thread. Titles carry a folded key built once by the
  reader, a cheap containment check rejects most titles, and filtering runs once
  per debounced query.
- The Hadith list was rebuilt (and emptied) on every search; it resets when the
  request changes while retaining earlier rows until results arrive. Row identity no longer JSON-encodes per render.
- Each reader call opened a new SQLite connection. Hadith keeps one connection
  per installed file; Quran keeps its Arabic text, searchable set, chapter map
  and the active translation in memory, so a search no longer rereads whole
  tables. "Load more" slices the cached ranked list instead of searching again.
- Quran result highlighting and preview trimming run in the reader actor.
- Smart-search results are resolved and previewed in one batch instead of one
  `detail()` call per result; the service configuration is read once.

## Earlier changes (Submit-only era)

- Hadith partial retrieval fetched candidate Arabic/English text and scored all
  candidates in Swift before pagination. The basic path now selects and ranks
  IDs using SQLite word indexes: exact phrases first, then all-word matches.
  Only the visible 50-row page is hydrated and highlighted.
- Both passage screens had a fixed 250 ms sleep on every nonempty search. Submit
  makes that delay unnecessary, so it was removed.
- Returning to a search could repeat retrieval and briefly clear its rows. Readers
  now retain eight recent result pages/searches in memory. Hadith invalidates
  caches when a database is installed/replaced. Quran keys include language,
  scope, limit, and translation revision; large evaluation searches are not cached.
- Empty Related matches sections were still being constructed. Basic passage
  results now render one local section, with online results separately.

These caches are bounded and in-memory; they do not create another on-disk index
or promise persistence across app termination. SQLite progress handlers and task
cancellation remain in place. Failed searches are not cached.

## Storage measurements

| Artifact | Before | Compact |
| --- | ---: | ---: |
| Latest local Hadith database | 968,339,456 bytes | 354,398,208 bytes |
| Released Hadith v5 archive vs new local archive | 332,581,783 bytes | 111,519,543 bytes |
| All Quran databases | 62,152,704 bytes | 26,943,488 bytes |

Hadith keeps word indexes for Arabic and English, without trigram indexes or
prefix-index duplication. Quran keeps its word index and reader/layout tables;
search morphology and trigrams are removed. Chinese translations retain their
small literal-search fallback. Broader matching belongs to explicit API search.
Reader rows and stable references in the compact Hadith database were compared
bidirectionally against the original using SQL EXCEPT; all were identical.

## Verification and rollout

Python builder tests cover compact schema, exact word retrieval, exclusion of
infixes, source preservation, and refusal to overwrite an existing output.
Swift reader tests cover scoped search, phrase ordering, pagination, cancellation,
cache invalidation, and local-library updates. Simulator UI tests verify that
Quran and Hadith passage results appear while typing, including partial words.

No compact pack has been uploaded. Existing TestFlight builds cannot consume the
new Hadith schema, and old Quran readers require the removed trigram index. A
compatible app build and coordinated pack transition are required; retain old
pack IDs for old clients or introduce separate compact pack IDs.

Physical-device profiling and cold-start/update peak-storage measurements remain
outstanding. The changes remove identified work, but no device latency speedup
is claimed without a controlled measurement.

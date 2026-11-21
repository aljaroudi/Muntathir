# Offline search performance

## Behavior

- Every search screen (Quran, Hadith, Supplications, Rulings, Figures, Saved) runs on Submit only. Typing shows recent searches; picking one submits it; clearing resets the screen. Results stay on screen until the next Submit's results arrive.
- Results, title matches and highlighting are computed once per Submit, never per keystroke or render. History is recorded on Submit or when a result is opened.
- The last word matches as a prefix from three letters (`صلا` → `صلاه`, `pray` → `prayer`), ranked after whole-word matches. Two-letter prefixes stay whole-word: `"ال"*` matches nearly every narration and takes 0.35–0.76 s. Infixes and typos don't match.
- Where meaning search exists, Submit uses it and falls back to local search.

## Design constraints

- Hadith ranks IDs with SQLite word indexes (exact phrase first, then all words) and hydrates/highlights only the visible 50-row page. Long narrations are cut to a window around the first match before Markdown parsing.
- Hadith keeps one connection per installed file and invalidates caches when a database is installed or replaced. Chapter titles carry a folded key built once by the reader.
- Quran keeps its Arabic text, searchable set, chapter map and active translation in memory. "Load more" slices the cached ranked list. Cache keys include language, scope, limit and translation revision; large evaluation searches aren't cached.
- Readers keep eight recent result pages in memory. Caches are bounded and in-memory only; failed searches aren't cached. SQLite progress handlers and task cancellation stay in place.
- Highlighting reuses one folding locale and memoizes per-character keys (`SearchPreviewTests`). Quran highlighting and preview trimming run in the reader actor.
- Smart-search results are resolved and previewed in one batch.

Reference timings (sqlite3 CLI, 354 MB Hadith DB, warm Mac): FTS lookups 1–20 ms; ranking ~120k ids (`الله`, `قال*`) ~0.2 s. These exclude Swift work and rendering.

## Storage

| Artifact | Before | Compact |
| --- | ---: | ---: |
| Local Hadith database | 968,339,456 bytes | 354,398,208 bytes |
| Hadith archive (released v5 vs compact) | 332,581,783 bytes | 111,519,543 bytes |
| All Quran databases | 62,152,704 bytes | 26,943,488 bytes |

Hadith keeps Arabic and English word indexes only (no trigram or prefix duplicates). Quran keeps its word index and reader/layout tables; morphology and trigrams are removed. Chinese translations keep a small literal-search fallback. Broader matching belongs to API search. Compact Hadith reader rows were verified identical to the original with bidirectional SQL `EXCEPT`.

## Tests and rollout

- Python builder tests: compact schema, exact word retrieval, infix exclusion, source preservation, no overwrite of existing output.
- Swift reader tests: scoped search, phrase ordering, pagination, cancellation, cache invalidation, local-library updates.
- Old clients can't read compact packs (new Hadith schema; old Quran readers need the trigram index). Ship compact packs only with a compatible app build, keeping old pack IDs for old clients or using new pack IDs.
- Not yet measured: physical-device latency and cold-start/update peak storage.

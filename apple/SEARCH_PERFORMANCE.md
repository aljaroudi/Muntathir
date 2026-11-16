# Basic offline search and search-screen responsiveness

The selected behavior is keyboard Submit for Quran/Hadith passages, with live
surah/book/chapter title filtering. Meaning search remains an explicit online
action. Query text changes no longer restart passage retrieval after a debounce.

## Causes found and changes

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
neither Quran nor Hadith passage results appear before keyboard Submit.

No compact pack has been uploaded. Existing TestFlight builds cannot consume the
new Hadith schema, and old Quran readers require the removed trigram index. A
compatible app build and coordinated pack transition are required; retain old
pack IDs for old clients or introduce separate compact pack IDs.

Physical-device profiling and cold-start/update peak-storage measurements remain
outstanding. The changes remove identified work, but no device latency speedup
is claimed without a controlled measurement.

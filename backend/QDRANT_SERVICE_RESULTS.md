# Qdrant-only search results — 2026-11-07

The PostgreSQL-free implementation passes the local relevance and capacity gates.
Ten Bun tests, ten current Python tests, six Swift unit cases and the Search UI checks pass.
Public Cloudflare cutover passed; the app URL is configured and Supabase search tables,
functions, cron job and feature secrets are removed. The user subsequently approved local benchmark cleanup: the three stopped benchmark
containers, PostgreSQL benchmark volume, and duplicate Qdrant collection are removed.

## Corpus and relevance

Imported and validated all 212,894 passages from the saved batch artifacts.
No corpus re-embedding was performed. Serving vectors are normalized 1,536-dimensional
prefixes of the original Gemini Embedding 2 vectors. Qdrant uses exact cosine search.

| Check | Result |
|---|---:|
| Main evaluation | 150 queries |
| Additional source-filtered evaluation | 12 queries |
| Exact semantic top-100 agreement | 100% on every query |
| Minimum semantic candidate count | 100 on every query |
| Recall@100 | 0.960563 |
| nDCG@10 | 0.781084 |
| Previous PostgreSQL hybrid Recall@100 | 0.960563 |
| Previous PostgreSQL hybrid nDCG@10 | 0.780596 |

Native BM25 with its default any-term matching regressed nDCG to 0.675644.
Requiring all normalized query terms, matching the prior PostgreSQL behavior,
restored relevance and slightly improved aggregate nDCG. Both diagnostics are
retained in ignored evaluation output. Labels are seed positives, not exhaustive
expert judgments; these numbers establish regression behavior, not religious authority.

## Capacity

Qdrant: Apple Container, 4 vCPU / 8 GiB, v1.20.0. Bun API runs on the host Mac.
Each sustained test sends 120 requests over 60 seconds; bursts send 200 over ten
seconds. Fixtures span Quran, Hadith, Arabic, English and filters.

| Pipeline | 2/s p95 | 20/s p95 | Errors |
|---|---:|---:|---:|
| Retrieval only, warmed, saved query vectors | 44 ms | 26 ms | 0 / 320 |
| Full local HTTP API, caches disabled, live Gemini | 744 ms | 795 ms | 0 / 320 |

The first HTTP harness run incorrectly supplied null optional filters and received
400 responses. The accepted runs omit absent filters per the request contract.
No quota increase was applied to the installed service: load testing used a separate
private port, SQLite file and 3,000/minute IP allowance. Production remains 30/minute/IP,
1,800/minute globally and 150,000 provider calls/day.

A direct reference lookup took 23 ms without Gemini. One cold natural-language
request took 687 ms, of which 651 ms was Gemini; its result-cache hit took 2 ms.
Public HTTPS tests with caches disabled also passed: 120 requests at 2/s had zero
errors and 3,577 ms p95; 200 requests at 20/s had zero errors and 2,572 ms p95.
The production IP quota and caches were restored after the tests.

Qdrant container memory after these tests was 4.71 GiB / 8 GiB, including the retained
old benchmark collection and cache. This is not a minimum-RAM sizing result.

## App and recovery

- Swift app builds; compact JSON decoding and ambiguous Hadith lookup tests pass.
- At initial cutover, the standalone Search tab and offline Quran navigation passed on iPhone/iPad.
  That tab has since been replaced by opt-in fallback in the existing readers.
- Initial cutover: five Search UI scenarios passed on iPad, including Arabic accessibility text size.
- Quran exact-verse and Hadith local-narration deep links pass on iPhone.
- Provider-failure offline state passes on iPhone.
- API crash recovery: 9.05 seconds.
- Qdrant container stop/recovery: 16.14 seconds.
- Per-user launch agent installed; starts after login. A physical Mac reboot was not performed.

## Local-first app follow-up

The Search tab was removed. Quran/Hadith search remains local, with an explicit
**Search by meaning** button only after a completed empty search. Collection/volume
and chapter scope carry through; query changes reset consent and cancel results.

Validation: Swift reference/scope/request tests pass; five iPhone UI scenarios and
six iPad scenarios pass across targeted runs (including Arabic accessibility size,
query reset, provider failure and both reader links). iPad runner installation and
stale test artifacts required a fresh build; the final two reruns passed. No physical
device test was performed. Backend type checks and all 11 tests pass.

Public chapter-scoped reference checks passed, including an empty result for a
missing chapter. One scoped semantic smoke request returned five in-scope results
in 1.34 seconds end to end. This is a smoke measurement, not a new load-test p95.

Fastlane metadata/cleanup checks and all 15 interface localizations pass. Website
privacy copy builds successfully. Store metadata and privacy copy are prepared
locally, not published. Cleanup removed approximately 6 GiB of disposable caches;
IPAs, symbols, media, diagnostics and manually created archives remain.

## Cost projection

At 100,000 searches/day over 30 days, 50 input tokens/search and zero cache hits,
Gemini costs approximately **$30/month**, using the published $0.20 per million text
input tokens. The measured evaluation requests averaged 14.16 tokens including
instructions, corresponding to about **$8.50/month** if real traffic matches that
mix. This is an estimate, not a spending ceiling. Cached queries reduce provider calls.

Source: [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing).
Local electricity, ISP costs, taxes and any optional Cloudflare paid features are
excluded. Supabase billing remains until its resources/subscription are retired;
no account-wide billing cancellation has been performed.

## Remaining operational limits

No physical Mac reboot was performed; launch agent starts after user login.
Supabase search resources are gone, but project/account billing was not cancelled.
Approved local benchmark containers, PostgreSQL volume and duplicate Qdrant collection
are removed. The active corpus still contains 212,894 passages; public search returned
HTTP 200 after cleanup. Saved import artifacts remain.
Automatic review also rejected broad local Supabase credential removal; those
existing account credentials are retained, unused by search. The final app build
with the public endpoint passed.

Raw measurements: `backend/work/qdrant-only-*.json`, `backend/work/qdrant-api-*.json`,
`backend/work/public-*.json`.

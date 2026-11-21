# Qdrant-only search results — 2026-11-07

The PostgreSQL-free service passed the local relevance and capacity gates and the public
Cloudflare cutover. Supabase search resources and the local benchmark containers/volume
are removed. Operations: [SEARCH_SERVICE.md](SEARCH_SERVICE.md).

## Corpus and relevance

All 212,894 passages imported from saved batch artifacts (no re-embedding); serving
vectors are normalized 1,536-dim prefixes of Gemini Embedding 2; exact cosine search.

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

Native BM25 with default any-term matching dropped nDCG to 0.675644; requiring all
normalized query terms (the prior behavior) restored it. Labels are seed positives, not
exhaustive expert judgments.

## Capacity

Qdrant 1.20.0 in Apple Container (4 vCPU / 8 GiB); Bun API on the host. Sustained =
120 requests over 60 s; burst = 200 over 10 s; fixtures cover Quran, Hadith, Arabic,
English and filters.

| Pipeline | 2/s p95 | 20/s p95 | Errors |
|---|---:|---:|---:|
| Retrieval only, warmed, saved query vectors | 44 ms | 26 ms | 0 / 320 |
| Full local HTTP API, caches disabled, live Gemini | 744 ms | 795 ms | 0 / 320 |

- Public HTTPS, caches disabled: 2/s → 0 errors, 3,577 ms p95; 20/s → 0 errors,
  2,572 ms p95.
- Single requests: direct reference 23 ms; cold natural-language query 687 ms (651 ms
  Gemini); cached repeat 2 ms.
- Load tests used a separate private port, SQLite file and 3,000/min IP allowance.
  Production quotas: 30/min per IP, 1,800/min global, 150,000 provider calls/day.
- Qdrant memory after tests: 4.71 GiB / 8 GiB (incl. a since-removed duplicate
  collection and cache; not a sizing result).

## Recovery

- API crash recovery: 9.05 s. Qdrant container stop/recovery: 16.14 s.
- Launch agent starts after login; a physical Mac reboot was not tested.
- App checks: compact decoding, Hadith lookup, deep links, provider-failure state and
  chapter-scoped reference checks passed (simulator/UI tests; no physical device).

## Cost projection

Gemini at $0.20 per million input tokens
([pricing](https://ai.google.dev/gemini-api/docs/pricing)), 100,000 searches/day for
30 days, no cache hits:

- 50 tokens/search: ≈ **$30/month**.
- Measured average 14.16 tokens/search: ≈ **$8.50/month**.

Estimates only; excludes electricity, ISP and Cloudflare paid features. Supabase
project/account billing was not cancelled.

Raw measurements: ignored `backend/work/qdrant-only-*.json`,
`backend/work/qdrant-api-*.json`, `backend/work/public-*.json`.

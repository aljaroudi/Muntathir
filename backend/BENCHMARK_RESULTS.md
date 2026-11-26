# Search benchmark results — 7 November 2026 (historical)

> Retired PostgreSQL/Supabase experiment; its scripts (`local_benchmark.py`,
> `dimension_benchmark.py`) no longer exist. Live service:
> [SEARCH_SERVICE.md](SEARCH_SERVICE.md). The follow-up
> [Qdrant comparison](QDRANT_BENCHMARK.md) led to the current design.

## Conclusions

- **1,536 dimensions**: same judged Recall@100 as 3,072, best nDCG@10, much faster.
  768 is smaller but has larger individual ranking regressions.
- **Supabase Micro failed** the load and ANN-accuracy gates even at 1,536 dims, and exact
  search timed out. The Mac was the faster database candidate.
- HNSW settings tested failed the 98% per-query top-100 overlap gate, especially with
  selective filters.

## Supabase Micro retest (1,536 dims)

Micro (~978 MB RAM, 1 GB WAL limit), no compute upgrade. Full 212,894-passage corpus with
normalized 1,536 float32 serving vectors, inline storage and `halfvec(1536)` HNSW;
original 3,072 vectors retained for rollback (no re-embedding).

End-to-end uncached API (Edge Function, live Gemini, cache/quota, hybrid search), unique
query suffixes, no language/source filter. Sustained = 2/s for 60 s (120 requests);
burst = 20/s for 10 s (200 requests). Latency includes failures; timeouts count as failures.

| Traffic | Sustained p95 | Sustained failures | Burst p95 | Burst failures |
|---|---:|---:|---:|---:|
| Quran | 8.29 s | 5 / 120 | 20.07 s | 107 / 200 |
| Hadith | 9.00 s | 79 / 120 | 20.07 s | 187 / 200 |
| Mixed | 11.39 s | 114 / 120 | 20.06 s | 196 / 200 |

- Bursts followed sustained runs without cooldown. Hadith/mixed sustained rows are repeat
  runs after active searches drained.
- Isolated hadith run: provider p95 (successful requests) 1.13 s; ~49.7% CPU I/O wait,
  1.59 GB disk reads. Of 1,000 sampled function logs, 800 errors were database-backed
  (654 in search), none in the provider stage.
- Exact 1,536 hybrid RPC at 2/s for 60 s: **120 / 120 failed** (5.96 s p95), PostgreSQL
  statement timeout (SQLSTATE 57014).

Quality (150 fixture queries): Recall@100 **96.06%**, nDCG@10 **0.7806**. ANN/exact
top-100 overlap averaged **92.61%** (min 64%); 86/150 below the 98% gate. 12
source-filtered queries: 90.92% average, min 80%, 11 failed; filtered retrieval p95
12.59 s.

HNSW index sizes: 357,228,544 bytes (Quran), 515,383,296 bytes (hadith), about half the
3,072 sizes. Database size 6,281,098,931 bytes including retained canonical vectors.

Raw artifacts: ignored `backend/work/micro-1536-*.json`.

## Mac dimension comparison (exact retrieval)

Apple Container 1.6.1, PostgreSQL 17.11, pgvector 0.8.7, 8 vCPU, 16 GB RAM, 4 GB shared
buffers on an M3 Ultra (28 cores, 96 GB). 6,236 verses + 62,725 narrations = 212,894
passages, same saved Gemini vectors. Database-only latency (no Gemini, HTTP, cache,
Cloudflare or client networking).

| Dimensions | Judged Recall@100 | nDCG@10 | DB p95 at 2/s | DB p95 at 20/s | SQL errors / 320 |
|---|---:|---:|---:|---:|---:|
| 3,072 | 96.06% | 0.7728 | 495 ms | 14105 ms | 0 |
| 1,536 | 96.06% | 0.7792 | 180 ms | 153 ms | 0 |
| 768 | 96.06% | 0.7706 | 158 ms | 108 ms | 0 |

- Burst p95 including executor queue: 157 ms (1,536), 115 ms (768). The 3,072 baseline
  measured SQL only.
- Smaller vectors are renormalized Matryoshka prefixes
  ([Google guidance](https://ai.google.dev/gemini-api/docs/embeddings)). Lower-dim columns
  used `STORAGE PLAIN` (inline); 3,072 cannot fit inline, so speedups combine dimension
  reduction and avoiding out-of-row access
  ([pgvector](https://github.com/pgvector/pgvector)).
- Gemini bills by input tokens, not dimensions, so embedding cost does not drop
  ([pricing](https://ai.google.dev/gemini-api/docs/pricing)).
- Reviewed 80-query subset: Recall@100 92.22% at every size; nDCG@10 0.5673 / 0.5766 /
  0.5700 (3,072 / 1,536 / 768). Flagged regressions: small-gift narrations at 1,536,
  mother/companionship narrations at 768.
- Source-filter checks (12 queries per smaller dimension) returned 100 eligible
  candidates with zero violations.

Judgments are incomplete seed positives (80 reviewed + 70 seed queries); treat these as
regression indicators, not certified relevance.

## HNSW vs exact at 3,072 dims

| Runtime | HNSW DB burst p95 | Exact DB burst p95 | Worst HNSW/exact top-100 overlap |
|---|---:|---:|---:|
| Native macOS, unrestricted resources | 493 ms | 20,051 ms | 57% |
| Apple Container, 8 CPUs / 16 GB | 2,444 ms | 14,105 ms | 61% |

Not a matched-resource comparison. HNSW use was verified with execution plans (the
native planner otherwise sometimes chose an exhaustive halfvec scan).

Raw reports: ignored `backend/work/local-benchmark/`.

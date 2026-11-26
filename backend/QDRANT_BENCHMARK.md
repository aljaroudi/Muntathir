# Qdrant comparison — 7 November 2026 (historical)

> Retired experiment; `qdrant_benchmark.py` and the benchmark containers no longer exist.
> Live service: [SEARCH_SERVICE.md](SEARCH_SERVICE.md); current results:
> [QDRANT_SERVICE_RESULTS.md](QDRANT_SERVICE_RESULTS.md).

**Qdrant won. Use exact retrieval for this corpus:** it matched every exact top-100
reference set and was about 2.6–3.2× faster than PostgreSQL exact search. Tuned HNSW
passed the recall gate but added little speed.

Scope: only the vector stage was swapped; keyword search, RRF fusion, dedup, excerpts and
metadata stayed in PostgreSQL. Qdrant's native BM25/hybrid was not measured here.

## Results

Same total budget, **8 vCPU / 16 GB**, Apple Container 1.6.1 on the M3 Ultra:
PostgreSQL alone 8 CPU / 16 GB; Qdrant pipeline split 4 CPU / 8 GB each.

| Local search pipeline | p95 at 2/s | p95 at 20/s | Errors | Semantic top-100 overlap |
|---|---:|---:|---:|---|
| PostgreSQL exact | 169 ms | 140 ms | 0 / 320 | 100% (reference) |
| Qdrant exact + PostgreSQL text/fusion | 64 ms | 44 ms | 0 / 320 | 100% |
| Qdrant indexed + PostgreSQL text/fusion | 59 ms | 45 ms | 0 / 320 | 98% minimum |

- Sustained 60 s (120 requests), burst 10 s (200 requests), each after a full 150-query
  warmup. Compare engines within a rate, not across rates.
- Includes local transport, queueing, keyword retrieval, fusion and hydration. Excludes
  Gemini, public HTTP/caches/rate limiting, Cloudflare and user network.

## Quality

Full 212,894-passage corpus, existing normalized 1,536-dim vectors (no re-embedding).

- Qdrant exact matched **100%** of exact top-100 IDs on 150 main + 12 source-filtered
  queries, preserving Recall@100 96.06% and nDCG@10 0.779186 (filtered set: 100% /
  0.834815). The reference was computed independently and cross-checked against
  PostgreSQL exact for all 162 queries.
- Indexed: float32, HNSW `m=32`, `ef_construct=200`, payload indexes on kind, source,
  language, revision; fetch 200, keep 100 with score/ID tie-breaking; no quantization.
  - `hnsw_ef=400`: 99.61% average, worst 88% — **fails** the per-query 98% gate.
  - `hnsw_ef=1000`: 99.95% average, minimum 98%, filtered 100% — passes.

## Configuration

Qdrant 1.20.0 (`222b2e44ab1c3f17e8246396ead6558e45041df7`), cosine, float32, in-memory,
single node. PostgreSQL 17.11 / pgvector 0.8.7, inline 1,536 float32 projection, 4 GB
shared buffers standalone (2 GB split), 32 MB work memory, no parallel gather workers.

End-of-burst memory snapshots (incl. cache, not sizing guidance): PostgreSQL alone
**4.07 GB**; Qdrant **2.61 GB** + PostgreSQL text stage **0.45 GB**.

Raw reports: ignored `backend/work/qdrant/`.

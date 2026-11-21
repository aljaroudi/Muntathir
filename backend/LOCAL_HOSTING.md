# Local hosting benchmark (historical)

> Retired experiment. The PostgreSQL/Supabase tooling (`local_benchmark.py`,
> `dimension_benchmark.py`), the `muntathir-benchmark-pg` container and its volume no
> longer exist. For the live service see [SEARCH_SERVICE.md](SEARCH_SERVICE.md);
> results are in [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md).

## What was compared

- Native PostgreSQL 17.11 + pgvector 0.8.7 (4 GB shared buffers, Unix socket only)
  versus the same in Apple Container 1.6.1 (8 vCPU, 16 GB RAM, loopback port, named
  volume).
- Full corpus: 68,961 items, 212,894 passages, 3,072-dim vectors (`vector` float32
  storage, `halfvec` HNSW expression indexes).
- Full hybrid SQL (semantic + keyword retrieval, fusion, item collapse, excerpts,
  attribution, fixture filters), exact retrieval versus HNSW.

## Method notes

- Indexed runs set `enable_sort=off` and `jit=off` so the planner actually used HNSW;
  exact runs used the default planner with `p_exact=true`.
- Tests ran serially with warm query embeddings and pages, no result cache.
- Latencies exclude Gemini, HTTP, Cloudflare and client networking — database
  measurements only, not endpoint latency.
- Apple CPU/memory/disk figures came from `container stats`.
- Raw reports: ignored `backend/work/local-benchmark/`.

## Deployment conclusions carried forward

- Expose only the HTTP API via a named Cloudflare Tunnel; keep the database private.
- Apple Container assigns per-container resources without touching Docker; use a named
  volume, not a host bind mount. It gives no availability when the Mac or network is down.
- Production needs automatic startup, sleep/power planning and provider rate limits.

Sources: [Apple Container](https://github.com/apple/container),
[resource controls](https://github.com/apple/container/blob/main/docs/resource-usage.md),
[volumes](https://github.com/apple/container/blob/main/docs/volumes.md),
[pgvector](https://github.com/pgvector/pgvector),
[Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/).

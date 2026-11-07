# Qdrant comparison — 7 November 2026

> Historical benchmark report. The PostgreSQL/Supabase tooling and benchmark services
> have been retired. Commands below describe the original experiment, not current setup.
> Use [SEARCH_SERVICE.md](SEARCH_SERVICE.md) for the live Qdrant service.


**Qdrant won this local comparison. Use exact retrieval for this corpus:** it
matched every exact top-100 reference set and was about 2.6–3.2 times faster
than the current PostgreSQL-only exact-search pipeline. Indexed Qdrant passed
our recall gate after tuning but offered little extra speed in these tests.

This measures a Qdrant vector-search stage plus the existing PostgreSQL keyword
search, reciprocal-rank fusion, deduplication, text excerpts, attribution, and
navigation metadata. It does not measure a complete Qdrant-only implementation
or Qdrant's native BM25/hybrid ranking. Keeping the rest of the pipeline identical
isolates the vector-retrieval change.

## Results

All configurations had the same total allocation: **8 virtual CPUs and 16 GB RAM**
on the M3 Ultra Mac, using Apple Container 1.6.1 and Linux ARM64.
PostgreSQL alone received 8 CPUs / 16 GB. The Qdrant pipeline split that allocation
into Qdrant 4 CPUs / 8 GB and PostgreSQL 4 CPUs / 8 GB.

| Local search pipeline | p95 at 2/s | p95 at 20/s | Errors | Semantic top-100 overlap |
|---|---:|---:|---:|---|
| PostgreSQL exact | 169 ms | 140 ms | 0 / 320 | 100% (reference) |
| Qdrant exact + PostgreSQL text/fusion | 64 ms | 44 ms | 0 / 320 | 100% |
| Qdrant indexed + PostgreSQL text/fusion | 59 ms | 45 ms | 0 / 320 | 98% minimum |

Sustained tests ran for 60 seconds (120 requests); bursts ran for 10 seconds
(200 requests). Each timed run followed a complete 150-query warmup. Latency
includes local transport, client connection setup, executor queueing, keyword
retrieval, fusion, item collapse, and result hydration. It excludes Gemini query
embedding, public HTTP authentication/rate limiting/caches, Cloudflare, and the
user's network. Saved query embeddings were reused; no result cache bypassed
search work. Earlier partial-warmup PostgreSQL reports are retained as
`postgres-initial-*` but excluded from this table.

Both engines used the same cyclic query sequence and filters at each rate.
The 120- and 200-request windows cover different fixture prefixes; compare
engines within a rate, not the rates as a controlled latency-scaling experiment.
These are short controlled runs, not a long-duration capacity or uptime guarantee.

## Quality

The complete **212,894-passage** corpus used existing normalized 1,536-dimensional
Gemini vectors. No corpus or query re-embedding calls were made.

Qdrant exact retrieval matched **100% of the exact top-100 IDs on all 150 main
queries and 12 additional source-filtered queries**. It also preserved judged
Recall@100 (96.06%) and nDCG@10 (0.779186) from the PostgreSQL exact baseline.
The extra source-filtered set had judged Recall@100 of 100% and nDCG@10 of 0.834815.
Judgments remain incomplete; matching the reference does not certify religious
relevance independently of that fixture.

Indexed Qdrant used float32 vectors, HNSW `m=32`, `ef_construct=200`, and four
indexing threads, with keyword payload indexes on kind, source, language, and
revision. It fetched 200 candidates and selected 100 with deterministic score/ID
ordering. No quantization or paid reranker was used.

- `hnsw_ef=400`: main-query overlap averaged 99.61%, but the worst query was 88%.
  This configuration failed the per-query 98% gate despite its high average.
- `hnsw_ef=1000`: average overlap was 99.95%, minimum 98%; all 12 source-filtered
  queries had 100% overlap. This configuration passed and was used for indexed
  load tests.

All tested queries returned 100 candidates. The full-precision exact reference
was independently computed from the original import vectors, then cross-checked
against PostgreSQL exact retrieval for every one of the 162 queries: all sets
were identical. The collection was
fully indexed, green, and complete before measurements.

## Configuration and resources

Qdrant 1.20.0, commit `222b2e44ab1c3f17e8246396ead6558e45041df7`;
PostgreSQL 17.11 with pgvector 0.8.7. Qdrant used cosine distance, float32 vectors,
in-memory vector/payload configuration, and no replicas beyond the local node.
PostgreSQL used the existing inline 1,536 float32 projection and exact retrieval.
Its standalone allocation used 4 GB shared buffers; the split pipeline used 2 GB.
Both PostgreSQL configurations used 32 MB work memory and disabled parallel
workers per gather, matching the existing baseline. This is not an exhaustive
comparison against every possible PostgreSQL tuning configuration.

End-of-burst container memory readings, including cache, were approximately
**4.07 GB for PostgreSQL alone** versus **2.61 GB for Qdrant plus 0.45 GB for its
PostgreSQL text/metadata stage**. These are snapshots, not minimum RAM requirements
or peak measurements; they exclude the client and additional host/VM overhead.
Do not infer a hosted instance size or monthly price directly from them.

The [Qdrant query API](https://api.qdrant.tech/api-reference/search/query-points)
and [collection API](https://api.qdrant.tech/api-reference/collections/create-collection)
provide the exact-search, filter, and index controls used in the benchmark.

## Reproduction and state

`backend/qdrant_benchmark.py` provides `prepare`, `quality`, and `load` commands.
It accepts only loopback Qdrant URLs and the existing restricted local PostgreSQL
benchmark DSNs. Install `backend/requirements-eval.txt`; no new Python dependencies
were required. `prepare` reads the retained private `benchmark_embeddings_1536`
table, uploads deterministic UUIDs in resumable batches, checks the complete
count, and enables indexing. The default Qdrant URL is `http://127.0.0.1:56333`.

Example commands, with `PGPASSFILE` pointing to the ignored private benchmark
credential file and the resource allocations configured as above:

```sh
backend/.venv/bin/python backend/qdrant_benchmark.py prepare --output backend/work/qdrant/import.json
backend/.venv/bin/python backend/qdrant_benchmark.py quality --exact --output backend/work/qdrant/exact-quality.json
backend/.venv/bin/python backend/qdrant_benchmark.py quality --ef 1000 --output backend/work/qdrant/indexed-quality.json
backend/.venv/bin/python backend/qdrant_benchmark.py load --exact --rate 20 --seconds 10 --output backend/work/qdrant/exact-burst.json
backend/.venv/bin/python backend/qdrant_benchmark.py load --engine postgres --rate 20 --seconds 10 --output backend/work/qdrant/postgres-burst.json
```

Run the source-filtered quality fixture with `--queries` and the corresponding
`--reference`. Wait for indexing to complete before timed runs. The PostgreSQL
only baseline uses the 8-CPU container; stop it before mounting its data volume
in the 4-CPU metadata container. Never run both against the same data volume.

19 Python tests passed, including target restrictions and filter/tie handling.
The real-data quality checks exercised the private SQL fusion helper. All three
benchmark containers are stopped; neither local port has a listener. Corpus data
and ignored reports remain under `backend/work/qdrant/` and named volumes for
reproduction. Supabase and the app were not changed by this experiment.

**Remaining work before adoption:** integrate Qdrant into the real API, validate
revision activation/rollback across both stores, and measure end-to-end latency.
Qdrant Cloud pricing and performance were not tested.

# Search benchmark results — 7 November 2026

> Historical benchmark report. The PostgreSQL/Supabase tooling and benchmark services
> have been retired. Commands below describe the original experiment, not current setup.
> Use [SEARCH_SERVICE.md](SEARCH_SERVICE.md) for the live Qdrant service.


A later [Qdrant comparison](QDRANT_BENCHMARK.md) measures a faster local vector-search alternative with the same total CPU/RAM budget.

## Supabase retest: 1,536 dimensions on Micro

**The switch is deployed, but Micro still fails the agreed load and quality gates.**
Keep 1,536 dimensions. Keep search disabled until the deployment can meet those
gates. The Mac remains the faster measured database candidate; its full hosted
API, provider, network, and tunnel path still need an end-to-end test.

No compute upgrade was used during this retest. The project remains on Micro
(about 978 MB reported RAM), with its existing disk and 1 GB WAL limit.
Gemini queries now request 1,536 dimensions. The complete 212,894-passage corpus
and retained 579-passage pilot have normalized 1,536 float32 serving vectors,
inline storage, and `halfvec(1536)` HNSW indexes. Original 3,072 vectors are retained
for rollback, so no corpus re-embedding was paid for.

### Uncached API capacity

Each sustained test sends **2 searches/second for 60 seconds**, 120 requests.
Each request runs the Edge Function, live Gemini embedding, cache/quota operations,
full hybrid database search, and result formatting. Queries select Quran or
hadith but have no language/source filter, matching the app's current flow.
Mixed traffic alternates those selections. Every query gets a unique test suffix
to prevent query/result-cache hits.

| Traffic | Endpoint p95 | Failed requests |
|---|---:|---:|
| Quran | 8.29 s | 5 / 120 |
| Hadith | 9.00 s | 79 / 120 |
| Mixed Quran/hadith | 11.39 s | 114 / 120 |

Latency includes failures, measured from this Mac. The Quran row is the first
sustained test. Hadith and mixed rows are repeat runs after three consecutive
checks found no active database searches, avoiding carry-over from burst tests.
Quran's second 30 seconds improved to 4.59 s p95 with no failures; the complete
run still failed, and that warmed result did not generalize to hadith or mixed traffic.

The original sequence also tested **20 searches/second for 10 seconds**, 200
requests per burst. These bursts followed sustained runs without a cooldown:

| Burst traffic | Endpoint p95 | Failed requests |
|---|---:|---:|
| Quran | 20.07 s | 107 / 200 |
| Hadith | 20.07 s | 187 / 200 |
| Mixed | 20.06 s | 196 / 200 |

Client timeouts are included as failures. Provider/database timings are available
only for successful requests, so they must not be treated as all-request p95s.
In the isolated hadith run, successful-request provider p95 was 1.13 seconds,
while the host spent about 49.7% of CPU time waiting on I/O and read 1.59 GB from
disk. A sample of 1,000 recent function logs contained 800 errors in database-backed
stages (654 in search), with no provider-stage errors in that sample.
Log sampling uses [Supabase's current unified logs API](https://supabase.com/docs/reference/api/v1-get-project-logs).

### Exact-search alternative

After the API tests restored disabled search and normal quotas, and active
searches drained again, a private REST RPC test ran exact 1,536-dimensional hybrid
retrieval at 2 searches/second for 60 seconds, alternating Quran/hadith.
**120 / 120 requests failed**, with 5.96 s p95.
That latency describes failed requests, not successful exact search. A subsequent single-request probe confirmed PostgreSQL statement timeout
(SQLSTATE 57014). This test
excludes Gemini and Edge Function cache/quota overhead. Exact search therefore
does not rescue this Micro configuration under the tested load.

### Retrieval quality and storage

All 150 fixture queries completed. Judged Recall@100 was **96.06%**, nDCG@10
**0.7806**. ANN/exact top-100 overlap averaged **92.61%**, with a **64% minimum**;
86 of 150 queries fell below the 98% gate. Twelve additional source-filtered
queries averaged 90.92% overlap, minimum 80%; 11 failed the gate. Every query
returned the requested 100 candidates, so missing exact neighbors were not
detected by the underfill fallback. Filtered candidate retrieval reached 12.59 s p95.
These are approximate-index misses, separate from the dimensional comparison
below. Seed judgments remain incomplete; similar average relevance scores do
not certify equivalent result sets.

Execution plans confirmed both per-kind HNSW indexes were used. Their sizes are
357,228,544 bytes (Quran) and 515,383,296 bytes (hadith), approximately half their
previous 3,072-dimensional sizes. Database size after projection/index construction
was 6,281,098,931 bytes, including retained canonical vectors; cache activity adds
some storage. Keeping originals means whole-database storage increases
rather than halving during this reversible transition.

### Implementation and verification

The declarative schema remains the source of truth. Migrations, query profile,
Gemini request size, vector validation, importer projection trigger, resumable
backfill, evaluation references, and benchmark utilities were updated together.
Full-corpus activation now uses an aggregate validation query to avoid the old
`EXISTS` plan's repeated random lookups. All original text-offset, revision,
profile, count, and missing-vector checks remain; full-corpus validation passed.
The importer uses a bounded administrative query for large-corpus activation
when an access token is configured.

17 Python tests, four Deno tests, type/lint checks, and disposable PostgreSQL
schema/migration, projection/retry, permission, reference, and rollback tests
passed. Final rollout state remains **disabled**, normal IP quota is restored,
and Micro was retained. No local public service or Cloudflare tunnel was created.

Raw artifacts are ignored under `backend/work/micro-1536-*.json`, including
isolated sustained tests, burst tests, exact RPC results, quality evaluations,
query plans, error-stage summaries, and final state checks.

## Earlier Mac dimension comparison

The Mac tests recommended 1,536 dimensions: judged Recall@100 stayed the same,
its average nDCG@10 was highest in this fixture, and exact retrieval was fast.
768 remains a smaller option with larger individual ranking regressions.
Review those regressions before public rollout; keep original vectors for rollback.

## Dimension comparison

Apple Container 1.6.1, Linux ARM64, PostgreSQL 17.11, pgvector 0.8.7,
8 virtual CPUs, 16 GB RAM, 4 GB shared buffers. Host: M3 Ultra, 28 physical
CPU cores, 96 GB RAM. Corpus: 6,236 verses and 62,725 narrations;
212,894 passages. All tests use the same saved Gemini Embedding 2 vectors.

| Dimensions | Judged Recall@100 | nDCG@10 | DB p95 at 2/s | DB p95 at 20/s | SQL errors / 320 requests |
|---|---:|---:|---:|---:|---:|
| 3,072 | 96.06% | 0.7728 | 495 ms | 14105 ms | 0 |
| 1,536 | 96.06% | 0.7792 | 180 ms | 153 ms | 0 |
| 768 | 96.06% | 0.7706 | 158 ms | 108 ms | 0 |

Sustained tests last 60 seconds (120 requests); bursts last 10 seconds
(200 requests). Full hybrid SQL runs every time: semantic retrieval, keyword
candidates, reciprocal-rank fusion, translation/item collapse, excerpts and
attribution. Filters follow the 150-query fixture. Query vectors and OS pages
may be warm; no result-cache hits skip the database work.

At 1,536 dimensions, burst latency including the benchmark executor queue was
**157 ms p95**, with **153 ms SQL p95**. At 768, it was **115 ms including the
queue**, with **108 ms SQL p95**. The earlier 3,072 baseline measured SQL only;
its full request latency would be at least the reported SQL duration.

These are database measurements, **not end-to-end API measurements**. Gemini,
HTTP, cache/quota calls, Cloudflare, client networking and client timeouts are
excluded. Zero SQL errors does not make the slow 3,072 burst acceptable.

## Why smaller vectors helped here

Gemini Embedding 2 supports useful Matryoshka prefixes. The smaller corpus and
query vectors were derived from the existing embeddings and renormalized;
there were no paid re-embedding calls. Google recommends 768, 1,536, and 3,072
as supported choices. [Google embedding guidance](https://ai.google.dev/gemini-api/docs/embeddings)

Float32 payload is about 12 KB per 3,072-dimensional vector, 6 KB at 1,536,
and 3 KB at 768. The lower-dimensional test columns use PostgreSQL `STORAGE
PLAIN`, since those rows fit within a normal page. The 3,072 vector cannot fit
inline. Reported speedups therefore include both dimensional reduction and
avoiding out-of-row vector access; they are not a claim that dimension alone
caused the entire speedup. [pgvector storage guidance](https://github.com/pgvector/pgvector)

Vector payload is halved at 1,536 and quartered at 768. Whole-database/index
sizes do not shrink in the same ratio because text and graph overhead remain.
Gemini bills text embeddings by input tokens, not selected dimensions, so
provider-call cost is not proportionally reduced. [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing)

## Quality limits

The 150-query fixture contains 80 previously reviewed queries and 70 additional
seed queries requiring review. Relevance judgments are incomplete. Empty
relevance sets are excluded from the relevance averages; these are regression
indicators, not certified religious relevance judgments.

The previously reviewed subset also had identical Recall@100 at every size
(92.22%). Its nDCG@10 was 0.5673 / 0.5766 / 0.5700 for 3,072 / 1,536 / 768.
Average similarity does not eliminate individual regressions. Examples flagged
for review include small-gift narrations at 1,536 and mother/companionship
narrations at 768. Unjudged authentic variants may also explain some changes.

## Original halfvec HNSW comparison

Both runtimes retained float32 vectors and halfvec expression indexes. HNSW
was verified with execution plans; otherwise the native planner sometimes
selected an exhaustive halfvec scan, which would give misleading ANN results.
Indexed measurements discouraged full sorts and disabled JIT; exact tests
used the default planner. Required small sorts still execute.

| Runtime at 3,072 | HNSW DB burst p95 | Exact DB burst p95 | Worst HNSW/exact top-100 overlap |
|---|---:|---:|---:|
| Native macOS, unrestricted host resources | 493 ms | 20,051 ms | 57% |
| Apple Container, 8 CPUs / 16 GB | 2,444 ms | 14,105 ms | 61% |

This is not a matched-resource virtualization-overhead comparison. The current
HNSW settings fail the original 98% overlap gate, particularly under selective
filters. That is separate from dimensional relevance loss. The lower-dimensional
results above use **exact full-precision retrieval**, without ANN omissions;
lower-dimensional HNSW settings were not evaluated in that Mac run; the Supabase retest above evaluates them.

## Validation and next step

All 24 source-filter checks (12 queries at each smaller dimension) returned
100 eligible candidates with zero source/type violations. Quran and hadith
structured references passed. Benchmark utility tests passed. The local database
port was verified as loopback-only; no Cloudflare tunnel or public API was created.

The Supabase retest above now covers the 1,536 profile, live query dimensions,
index/filter behavior, and complete endpoint. Micro did not meet the tested load
or ANN accuracy gates. The Mac remains a database candidate; public deployment
still needs full API measurements, automatic startup, backups and uptime planning.

Scripts: `backend/local_benchmark.py`, `backend/dimension_benchmark.py`.
Raw reports are in ignored `backend/work/local-benchmark/`.

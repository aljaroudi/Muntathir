# Local hosting benchmark

> Historical benchmark report. The PostgreSQL/Supabase tooling and benchmark services
> have been retired. Commands below describe the original experiment, not current setup.
> Use [SEARCH_SERVICE.md](SEARCH_SERVICE.md) for the live Qdrant service.


This is a private benchmark, not a public deployment. Supabase remains on Micro;
its corpus texts and credentials are preserved. Hosted serving now uses 1,536
dimensions; see the Supabase retest in `BENCHMARK_RESULTS.md`. No Cloudflare tunnel has been created.

## What is being compared

- Native PostgreSQL 17.11, pgvector 0.8.7, 4 GB shared buffers, Unix socket only.
- Apple Container 1.6.1 (Homebrew), PostgreSQL 17.11 / pgvector 0.8.7,
  eight virtual CPUs, 16 GB RAM, 4 GB shared buffers, password-protected port
  `127.0.0.1:55439`, and a persistent named volume.
- The complete 68,961-item corpus: 212,894 passages with 3,072-dimensional vectors.
- Full hybrid SQL: semantic retrieval, keyword retrieval, fusion, item collapse,
  excerpts, attribution, and the evaluation fixture's content/language filters.
- Exact full-precision retrieval versus actual `halfvec` HNSW retrieval.

`pgvector` is the PostgreSQL extension. `vector` stores float32 values;
`halfvec` is its float16 type used by the HNSW expression indexes. Current serving
vectors/indexes use 1,536 dimensions; canonical vectors retain 3,072 dimensions. Both
runtimes retain the same storage design. Testing exact search does not change it.

The planner can choose a full halfvec scan instead of HNSW. The indexed benchmark
uses `enable_sort=off` and `jit=off` to ensure the measured semantic path uses
HNSW. Required small sorts still execute. The exact benchmark uses the default
planner and `p_exact=true`. Neither setting changes the hosted Supabase functions.

## Reproduce the measurements

Install `backend/requirements-eval.txt` in the backend virtual environment.
The source manifest and vectors live in ignored `backend/work/full/`; existing
Gemini query vectors are reused. Missing vectors require an explicit Gemini key.
Do not compare a pilot-sized database with the full corpus.

The isolated native cluster lives at `backend/work/local-benchmark/pgdata`, with
its private socket at `backend/work/local-benchmark/socket` and port 55438. It
has no TCP listener. Start/stop it with the PostgreSQL 17 `pg_ctl` executable.
The Apple database uses the `muntathir-benchmark-pg` container and named volume.
Its temporary credentials are in ignored, mode-600 `apple.env` and `apple.pgpass`
files in the same work directory. Never print `container inspect` environments.
Use a PGDATA subdirectory of the named volume to avoid its `lost+found` directory.

```sh
backend/.venv/bin/python backend/local_benchmark.py prepare
backend/.venv/bin/python backend/local_benchmark.py quality \
  --output backend/work/local-benchmark/native-hnsw-quality.json
backend/.venv/bin/python backend/local_benchmark.py load --exact --rate 2 --seconds 60 \
  --output backend/work/local-benchmark/native-exact-sustained.json
backend/.venv/bin/python backend/local_benchmark.py load --exact --rate 20 --seconds 10 \
  --output backend/work/local-benchmark/native-exact-burst.json
```

Omit `--exact` for verified HNSW. For Apple Container, set `PGPASSFILE` to the
absolute `apple.pgpass` path and add:

```text
--dsn 'host=127.0.0.1 port=55439 dbname=muntathir_benchmark_apple user=postgres'
--runtime apple_container_8cpu_16gb
```

The benchmark rejects remote database hosts and database names outside its
`muntathir_benchmark` namespace. Bulk COPY is transactional; vector dimensions,
finite values, input hashes, constraints, and corpus completeness are checked.
It defers index construction until after loading. `prepare` does not erase data.
Use a new isolated database if table counts are inconsistent after interruption.

Tests run serially to avoid competing benchmark workloads. Query embeddings and
filesystem pages may be warm; no result cache skips the hybrid SQL. Latencies
exclude Gemini, HTTP, Cloudflare, and client networking. They are not endpoint
latency claims. CPU/memory/disk figures for Apple come from `container stats`.

## Candidate deployment

A local deployment can reuse PostgreSQL/pgvector, the existing importer and search
functions, and the current TypeScript request validation/provider logic. A small
server adapter would replace Supabase-specific database calls. Expose only the
HTTP API through a named Cloudflare Tunnel; keep PostgreSQL private. Production
requires automatic startup, sleep/power planning, provider rate limits, and tested
offsite backups before changing the app's search URL.

Apple Container is attractive here because resources are assigned per container
without changing or restarting the existing Docker environment. Use a named
volume for database files, not a host bind mount. Container isolation does not
provide availability when the Mac or internet connection is offline.

Sources: [Apple Container](https://github.com/apple/container),
[resource controls](https://github.com/apple/container/blob/main/docs/resource-usage.md),
[volumes](https://github.com/apple/container/blob/main/docs/volumes.md),
[pgvector](https://github.com/pgvector/pgvector), and
[Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/).

## Results and shutdown

See [measured results](BENCHMARK_RESULTS.md), including the subsequent dimension
comparison. Native PostgreSQL and the Apple database container were stopped after
testing. Their data remains private for reproduction. Start the container with
`container start muntathir-benchmark-pg`; stop it with
`container stop --time 30 muntathir-benchmark-pg`. The named volume persists.

`dimension_benchmark.py` creates private 1,536/768-dimensional tables from the
original vectors, with float32 inline storage, and a dimension dispatcher in the
benchmark database only. It evaluates exact hybrid retrieval. It does not alter
the declarative production schema. Use `local_benchmark.py load --exact
--dimensions 1536` (or `768`) against that database for throughput tests. These
smaller-dimensional tests do not certify HNSW recall.

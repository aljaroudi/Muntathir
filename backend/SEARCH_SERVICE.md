# Qdrant search service

Gemini Embedding 2 (1,536 dims), Qdrant 1.20.0, a Bun HTTP server, and a local
SQLite file for caches and quotas. `ingest.py` prepares and submits embeddings;
`qdrant_import.py` imports saved artifacts without Gemini calls. Corpus refresh is
in [README.md](README.md).

## API

`POST https://search.xn--pgbou4cf.com/v1/search` (no client API key; server
credentials never ship in the app):

```json
{"query":"kindness to parents","kinds":["quran"],"limit":20}
```

- `limit`: default 20, max 50. Query 1–512 Unicode characters; body ≤ 8 KiB.
- `sources` (stable source/book IDs) and `languages` filter before ranking.
- `chapter`:
  - Hadith: a stable chapter file (e.g. `1.json`); requires `kinds: ["hadith"]` and
    exactly one `sources` entry.
  - Quran: decimal string `"1"`–`"114"`; requires `kinds: ["quran"]`.
- Filters apply to semantic, keyword and explicit-reference retrieval and are part of
  the result-cache key.
- Omitting `kinds` searches Quran, Hadith, Dua and Rulings. `figure` must be requested
  explicitly.

```json
{"results":[{"kind":"quran","chapter":2,"verse":255,"score":0.78}]}
```

- Hadith results: `kind`, `book`, `chapter` (chapter file), `number`, `score`.
  Dua: `kind`, `id`, optional `passage`/`locator`, `score`. Rulings: see README.
- `score` is cosine similarity (max over the item's passages), not confidence; null for
  explicit references and keyword-only hits. Order is hybrid RRF rank, optionally
  reranked, so scores need not decrease. No default threshold.
- Keyword candidates must contain every normalized query term; BM25 ranks them.
- Translations/passages collapse to one content item.
- Errors: 400/413 invalid input, 429 quota, 503 unavailable. An empty success is final;
  clients fall back to local search only on failure.
- Quran text/meaning search excludes verses with fewer than seven normalized Arabic
  letters (also when matching translations). Explicit references still work.

Deploy-order gotchas:

- Deploy the API with the legacy kind filter before activating an index containing
  figures; smoke-test unscoped and scoped requests against the candidate.
- To revert the API, first switch the alias back to the retained previous collection
  and wait out the 30-second alias cache.

## Local operation

`backend/.env` (ignored): `GEMINI_API_KEY`, `SEARCH_RATE_SALT`,
`QDRANT_URL=http://127.0.0.1:56333`, optional `QDRANT_API_KEY`. The API listens on
loopback port 8788. Bind Qdrant to loopback too; never expose it through the tunnel.

```sh
sh backend/setup_qdrant.sh
python3 backend/qdrant_import.py import --workdir backend/work/full
python3 backend/qdrant_import.py activate --workdir backend/work/full
python3 backend/serve.py
```

- Import is idempotent and checkpointed after acknowledged writes; a changed manifest
  cannot resume an existing checkpoint. Activation validates IDs, input hashes,
  profile and corpus fingerprint first.
- The API caches the `search` alias target for 30 s (invalidated on a collection 404).
- `python3 backend/install_service.py` installs a per-user launch agent that supervises
  the API and tunnel and restarts the Qdrant container if unhealthy. It starts only
  **after login** (FileVault); it does not change reboot or sleep settings.
- Deploy API code: `just backend-deploy` from the launch agent's checkout on the
  hosting Mac (typechecks and tests, then restarts the service).
- Container: `muntathir-search-qdrant`. This Mac uses the named volume
  `muntathir-benchmark-qdrant`, which **is production data — keep it**. Fresh installs
  default to a `muntathir-search-qdrant` volume.
- Collections created before short-verse eligibility need a payload-only backfill
  (no re-embedding) before running the current API against them:

  ```sh
  python3 backend/qdrant_import.py backfill-eligibility --workdir backend/work/full
  ```

  New imports set `search_eligible` automatically. Old exact-reference files are
  rejected; regenerate them with `exact_reference.py`.

## Cloudflare

- `python3 backend/cloudflare_setup.py` creates the named tunnel and DNS record with
  `CLOUDFLARE_API_TOKEN` (scopes: tunnel write, DNS edit, zone read) and saves the
  tunnel token to the ignored env file. It never overwrites a conflicting DNS record.
- The supervisor reads the token from a mode-600 file, not the command line.
- `SEARCH_TRUST_TUNNEL=true` requires `CF-Connecting-IP` from the loopback tunnel;
  direct requests without it fail closed. Other local users/processes are inside the
  trust boundary.
- `python3 backend/configure_search.py` generates the rate-limit salt; `--app` checks the
  public compact response and writes the ignored app URL plist. Clients default to the
  public endpoint; override via that plist or the app URL setting for staging.

## Jev reranking

Set in `backend/.env`, then restart the supervisor:
`SEARCH_RERANK_PROVIDER=jev`, `JEV_API_KEY` (or `TYPESAFE_API_KEY`),
`SEARCH_RERANK_MODEL=jev-1.14.0`. Roll back with `SEARCH_RERANK_PROVIDER=off` and a
restart; the collection alias is unaffected.

- Only explicit meaning searches are reranked; direct references bypass it.
- Only the fused top 20 passages have `text` fetched for reranking; responses stay compact.
- Failures, timeouts, cooldown and busy (>4 in flight per process) keep baseline order.
  HTTP/validation failures start a 30 s cooldown; timeouts do not.
- Measured cost ≈ $0.00022 per uncached query (reranker only), see
  [JEV_BENCHMARK_RESULTS.md](JEV_BENCHMARK_RESULTS.md).

## Verification

```sh
bun install --cwd backend/api
bun run --cwd backend/api check
bun test backend/api
backend/.venv/bin/python -m unittest discover -s backend -p 'test_*.py'
bun backend/api/verify.ts quality
TEST_RATE=2 TEST_SECONDS=60 bun backend/api/verify.ts load backend/work/qdrant-only-sustained.json
TEST_RATE=20 TEST_SECONDS=10 bun backend/api/verify.ts load backend/work/qdrant-only-burst.json
```

- The verifier uses saved query embeddings and never calls Gemini. Load mode measures
  retrieval only, not HTTP/Gemini/tunnel latency.
- `Server-Timing` and structured logs split retrieval/provider time and cache hits.
  Logs exclude queries and raw IPs. Quotas survive restarts.
- Cache TTLs: embeddings 1 h, results 5 min, cleanup every 10 min.
- The host Mac and its connection are single points of failure.

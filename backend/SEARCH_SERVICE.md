# Qdrant search service

The replacement uses Gemini Embedding 2 (1,536 dimensions), Qdrant 1.20.0,
Bun's HTTP server, and a local SQLite file for caches and quota counters.
No PostgreSQL is used in this serving path. Python preparation and batch submission
remain in `ingest.py`; `qdrant_import.py` imports its saved artifacts without Gemini calls.

## API

`POST https://search.xn--pgbou4cf.com/v1/search` with JSON:

```json
{"query":"kindness to parents","kinds":["quran"],"limit":20}
```

Optional `sources` (stable source/book IDs) and `languages` filter candidates before ranking.
Hadith `chapter` accepts a stable chapter file (for example `1.json`), and requires
`kinds: ["hadith"]` and exactly one entry in `sources`. A collection maps to all
its volume IDs; a chapter maps to its one volume and file. Quran `chapter` accepts
a decimal string from `"1"` to `"114"` with `kinds: ["quran"]`; retrieval matches
the numeric Quran chapter payload. These filters apply to
semantic, keyword and explicit-reference retrieval and result-cache keys. Limit defaults
to 20 and caps at 50. Query length is 1–512 Unicode characters; body is at most 8 KiB.
No client API key is required. Server credentials never ship in the app.

Deploy Quran chapter-filter support before releasing chapter-scoped search in the app.

```json
{"results":[{"kind":"quran","chapter":2,"verse":255,"score":0.78}]}
```

Hadith results use `kind`, `book`, `chapter` (stable chapter file), `number`, and
`score`. Dua results reserve `kind`, `id`, optional `passage`, and `score`.
Scores are cosine similarities, not confidence. Explicit references return null.
Array order is hybrid RRF rank, optionally reranked by LM Studio, so scores need not decrease monotonically.
Keyword candidates must contain every normalized query term, matching the previous
search semantics; native BM25 ranks those candidates.
Duplicate translations/passages collapse to a content item; the reported score is
the maximum cosine among its retrieved candidate passages. Clients may filter
scores but cannot recover omitted results; no default threshold is applied.
HTTP 400/413 indicate invalid input, 429 quota exhaustion, 503 unavailability.
The app hydrates reader text from local assets. Local search runs first; every
completed text search offers **Search by meaning**, with an online consent button.
Typing alone never calls Gemini. Query/scope changes cancel and reset online results.
Translation preferences control local previews; online retrieval remains multilingual.
There is no separate Search tab.

## Local operation

Keep credentials in ignored `backend/.env`. Set `GEMINI_API_KEY`,
`SEARCH_RATE_SALT`, `QDRANT_URL=http://127.0.0.1:56333`, and optionally
`QDRANT_API_KEY`. The API listens only on loopback port 8788. Qdrant's port must
also be bound to loopback; never publish its API through the tunnel.

```sh
sh backend/setup_qdrant.sh
python3 backend/qdrant_import.py import --workdir backend/work/full
python3 backend/qdrant_import.py activate --workdir backend/work/full
python3 backend/serve.py
```

Import batches are idempotent and checkpointed only after acknowledged writes.
A changed manifest cannot resume into an existing checkpoint. Validation checks
all IDs, input hashes, profile, and corpus fingerprint before alias activation.
The API resolves the alias to a concrete collection for each request, so cache
entries and in-flight searches remain isolated across revision changes.

`python3 backend/install_service.py` installs a per-user launch agent. It starts
**after login**, supervises the API and tunnel, and restarts the Apple container
if its health endpoint fails. This does not bypass FileVault's login requirement.
No forced Mac reboot or system-wide sleep setting changes are performed.

## Cloudflare

`python3 backend/cloudflare_setup.py` creates the dedicated named tunnel and DNS
record using `CLOUDFLARE_API_TOKEN`, then saves the tunnel token in the ignored env
file. Required scopes: tunnel write, DNS edit and zone read for the chosen account
and domain. An existing conflicting DNS record is never overwritten.

The supervisor uses a mode-600 token file, not a secret command-line argument.
`SEARCH_TRUST_TUNNEL=true` requires `CF-Connecting-IP` from the loopback tunnel.
Direct requests without this header fail closed in public mode. The local listener
must remain private; other local users/processes are within the host trust boundary.

Run `python3 backend/configure_search.py` to generate a private rate-limit salt.
After the public latency gate passes, `python3 backend/configure_search.py --app`
checks the public compact-reference response and writes the ignored app URL plist.

Before cutover, validate the permanent URL, then configure the app's
`SEMANTIC_SEARCH_URL` with the complete `/v1/search` URL (or generated ignored plist).
Supabase search resources were removed after public cutover, relevance and load checks passed.
No backups are requested; deletion is irreversible. Working import artifacts remain.

The running container is `muntathir-search-qdrant`. This Mac reuses the existing
named data volume `muntathir-benchmark-qdrant`; that volume is production data
and must be retained. The old benchmark container has been deleted. Fresh
installs use the `muntathir-search-qdrant` volume by default.

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

The verifier reads existing saved query embeddings and never invokes Gemini.
Its load mode measures the full retrieval pipeline, not HTTP/Gemini/tunnel latency;
those need separate endpoint measurements before public cutover.
`Server-Timing` and structured logs separate retrieval/provider time and cache hits.
Logs do not include queries or raw IPs. Quotas survive restarts. Cache expiry is
one hour for embeddings, five minutes for results, with ten-minute cleanup.

This host and internet connection remain single points of failure. Reboot recovery,
public latency, and expert relevance review must be reported separately from tests.

## Literal search and optional reranking

The app ranks normalized whole-word phrases before literal substrings. Root, typo,
and stem-only matches are delegated to explicit **Search by meaning**. API results
remain below local results, with duplicates removed. Questions use the same input.
Search underlines are temporary and are never saved or exported.

Quran text/meaning searches exclude verses with fewer than seven normalized Arabic
letters, including when searching translations. Explicit references still work.
Before running this API revision against an existing collection, backfill metadata:

```sh
python3 backend/qdrant_import.py backfill-eligibility --workdir backend/work/full
```

This updates payloads only; it never regenerates embeddings. New imports populate
`search_eligible` automatically. The new pipeline cache key invalidates old results.
Regenerate exhaustive reference files with `exact_reference.py` before the ordinary
quality check; old references include short verses and are explicitly rejected.

Reranking is disabled unless both environment variables are configured:

```dotenv
SEARCH_RERANK_URL=http://192.168.7.55:1234/v1
SEARCH_RERANK_MODEL=google/gemma-4-26b-a4b-qat
SEARCH_RERANK_TIMEOUT_MS=2000
```

Do not enable until evaluation passes. The server sends the original query and up
to 20 retrieved excerpts (1,000 characters each) to the configured LAN service.
It accepts only a complete permutation of candidate IDs. References and cosine
scores do not change. Direct references bypass the model. One request runs at a
time; busy, invalid, unavailable, or timed-out requests return baseline ranking.
Failures trigger a 30-second cooldown. Timeout is bounded to 1–2,000 ms,
and inference is shortened or skipped when the app request budget is nearly spent.
Transient fallbacks are not stored as successful reranked cache entries.

Compare both rankings using saved embeddings and existing Arabic/English fixtures,
including question queries:

```sh
bun backend/api/verify.ts rerank backend/work/rerank-evaluation.json
```

Set the variables in the benchmark environment, not production, until the gate
passes. The gate requires a completed evaluation and improved mean NDCG@10.
Gemma 4 26B A4B QAT timed out at two seconds on its first evaluation request.
The other 149 requests used baseline ranking during cooldown, so the run could
not establish a relevance gain. Reranking remains disabled. Inspect outcome
counts as well as aggregate latency.

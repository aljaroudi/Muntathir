# Semantic search

Qdrant + Gemini Embedding 2, served by a Bun API on the hosting Mac through
Cloudflare Tunnel. The API tries hybrid retrieval, falls back to keyword search,
and reranks with Jev when enabled. Apple and Android clients hydrate results from
local content and fall back to local search when the service fails.

- [Service API and operations](SEARCH_SERVICE.md)
- [Current validation and capacity results](QDRANT_SERVICE_RESULTS.md)
- [Reranker benchmark](RERANK_BENCHMARK.md) · [Jev results](JEV_BENCHMARK_RESULTS.md)
- Historical (retired PostgreSQL/Supabase): [Qdrant comparison](QDRANT_BENCHMARK.md),
  [benchmark results](BENCHMARK_RESULTS.md), [local hosting](LOCAL_HOSTING.md)

## Setup

Python 3.11+ with `backend/requirements.txt` (`requirements-eval.txt` for
evaluation). Put credentials in ignored `backend/.env`. Only `submit` and `poll`
need `GEMINI_API_KEY` and incur cost.

## Refresh production after database changes

From the repository root:

```sh
python3 build/build.py               # rebuild/package libraries, embed, validate, activate
python3 build/build.py --dry-run     # estimate only, from existing databases
python3 build/build.py --assets-only # local packaging, no search refresh
```

- Costs up to $10 are auto-approved; change with `--max-budget USD`. Above it, the
  script asks in the terminal.
- Rerun the same command to poll outstanding batches and continue.
- Needs the backend virtualenv plus the validated manifest and vectors of the active
  Qdrant collection. Vectors from other `backend/work/*` dirs with the same embedding
  profile are reused, so nothing is embedded twice.

## Manual corpus pipeline (recovery path)

Use a new workdir per revision; keep the previous validated workdir and its
provenance. Do not resubmit the already-imported full corpus in `backend/work/full`.

```bash
work=backend/work/refresh-YYYY-MM-DD
prior=backend/work/full
quran=apple/Muntathir/Resources/Quran
translations=()
for db in "$quran"/*.db; do
  edition=${db##*/}
  edition=${edition%.db}
  case "$edition" in
    quran) continue ;;
    zh.jian) language=zh-Hans ;;
    zh.majian) language=zh-Hant ;;
    *) language=${edition%%.*} ;;
  esac
  translations+=(--translation "$language:$edition:$db")
done
backend/.venv/bin/python backend/ingest.py prepare --workdir "$work" \
  --quran "$quran/quran.db" --hadith build/hadith/dist/hadith.db \
  --rulings build/rulings/dist/rulings.db \
  --provenance backend/work/provenance.json "${translations[@]}"
backend/.venv/bin/python backend/ingest.py estimate --workdir "$work" --reuse "$prior"
```

Review the estimate, export `GEMINI_API_KEY`, and set `--max-usd` to the approved cap
(it includes prior accepted or unresolved batches; recheck the estimate before raising
it for retries). The estimate uses UTF-8 bytes as a conservative token proxy at the
[Gemini Embedding 2 Batch rate](https://ai.google.dev/gemini-api/docs/pricing/#gemini-embedding-2).

```bash
backend/.venv/bin/python backend/ingest.py submit --workdir "$work" --reuse "$prior" --max-usd 15
backend/.venv/bin/python backend/ingest.py poll --workdir "$work"
backend/.venv/bin/python backend/ingest.py estimate --workdir "$work" --reuse "$prior"
```

Repeat poll/submit until pending and missing are both zero (poll resumes without
redownloading; submit retries missing/failed entries). Then stage and validate:

```bash
backend/.venv/bin/python backend/ingest.py upload --workdir "$work"
backend/.venv/bin/python backend/exact_reference.py --corpus "$work" --output "$work/exact-1536.json"
collection=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["collection"])' "$work/qdrant-progress.json")
SEARCH_COLLECTION="$collection" bun backend/api/verify.ts quality "$work/quality.json" backend/evaluation.json "$work/exact-1536.json"
SEARCH_COLLECTION="$collection" TEST_RATE=2 TEST_SECONDS=60 bun backend/api/verify.ts load "$work/sustained.json"
SEARCH_COLLECTION="$collection" TEST_RATE=20 TEST_SECONDS=10 bun backend/api/verify.ts load "$work/burst.json"
```

Record the active collection for rollback. Once all checks pass and the matching
Hadith pack is available to testers, activate (atomic alias switch after completeness
validation), then smoke-test Quran and scoped Hadith search against the running API:

```bash
backend/.venv/bin/python backend/ingest.py activate --workdir "$work"
```

For a quick pilot, add `--limit 100` (or `--pilot` for judged positives plus a
representative sample) to `prepare`.

### Notes

- `--reuse <workdir>` (repeatable) reuses vectors with matching input hashes.
  Artifacts keep 3,072 dimensions; upload derives normalized 1,536-dim prefixes.
- Content IDs preserve source identity; the index keeps text, edition/attribution and
  code-point passage offsets internally (the API response omits them). `--provenance`
  overrides source metadata; preserve credits and source terms.
- Duas: `--dua file.json` (the app's dua reader is deferred). Short duas stay whole;
  long ones are chunked by paragraph. Titles are labels, not identity.

  ```json
  [{"id":"stable-dua-id","title":"Name","source_id":"collection","source_name":"Collection",
    "texts":[{"language":"ar","edition":"edition-id","attribution":"Source","text":"Full supplication"}]}]
  ```

- Rulings: `--rulings build/rulings/dist/rulings.db`; API kind `rulings`. One item per
  authority/language/site ID (includes book introductions and standalone rules with
  chapter context). Filter with `kinds: ["rulings"]`, `sources: ["sistani"]`,
  `languages: ["ar"]`; filters apply before ranking. Results (`kind`, `authority`,
  `language`, `id`, `score`) are hydrated from the app's `Rulings/rulings.db`.
- Production additions must build on the currently active corpus, not an unactivated
  local refresh.

Current rollout (2026-11-22): active
`search_6e7450bd147940f0ae95c6d384705644_a3667cba9881` (245,174 items, 397,920 passages).
Artifacts: `backend/work/refresh-0d6f494de5fa3ab2978db00c9e9db933b3445a29a0ad2f9e405534344960ae36/`.

- Rollback target `search_c6d8394dc7714732937c9f30d7176249_fdcc5a4c48a8`. Switch the alias
  **and** set the `sources` limit in `api/core.ts` back to 20, then `just backend-deploy`:
  the older index lacks Bihar and Wasa'il, and an empty success stops clients falling back
  to local search.

  ```sh
  curl -X POST 127.0.0.1:56333/collections/aliases -H 'content-type: application/json' -d '{"actions":[{"delete_alias":{"alias_name":"search"}},{"create_alias":{"alias_name":"search","collection_name":"search_c6d8394dc7714732937c9f30d7176249_fdcc5a4c48a8"}}]}'
  ```

- nDCG@10 is measured on the judged books (`judged_sources` in `evaluation.json`). Its
  minimum was lowered from 0.780596 to 0.780157 for this rollout, whose corrected chapter
  titles re-embedded 26,472 passages of older books. Unscoped it is 0.762881.
- Only the `rulings-v2` pack is supported. iOS 1.1.0 reads the retired `rulings` pack and
  fails a Rulings smart search if any hit is missing from it.

Removed 2026-11-22: `search_a6924d0407894f02a372bca8bce23f25_163940aeaabf` (unused, used
by the historical rerank benchmark). Rebuild it without Gemini calls:
`backend/.venv/bin/python backend/ingest.py upload --workdir backend/work/refresh-2026-11-14`.

## Verification

```sh
backend/.venv/bin/python -m unittest discover -s backend -p 'test_*.py'
bun install --cwd backend/api
bun run --cwd backend/api check
bun test backend/api
bun backend/api/verify.ts quality backend/work/qdrant-only-quality.json
python3 apple/scripts/check_localizations.py
```

The quality check enforces exact-vector agreement, candidate counts and the accepted
relevance baseline, using saved query embeddings (no Gemini calls). The 150-query
fixture has 80 reviewed queries and 70 seed-positive queries awaiting expert review;
judgments are not exhaustive. Regenerate exhaustive references with
`exact_reference.py`.

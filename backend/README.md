# Semantic search

Qdrant + Gemini Embedding 2, served by a TypeScript Bun API on this Mac through
Cloudflare Tunnel. The Swift app searches locally first in its Quran/Hadith readers. After local
text search, it offers **Search by meaning** in the same search bar. Online requests
require a tap, retain the current collection/chapter, and hydrate compact references
from local reader data. PostgreSQL and Supabase are no
longer used by this feature.

- [Service API and operations](SEARCH_SERVICE.md)
- [Current validation and capacity results](QDRANT_SERVICE_RESULTS.md)
- [Historical engine comparison](QDRANT_BENCHMARK.md)

## Corpus preparation

Use Python 3.11+ with `backend/requirements.txt`. Optional evaluation dependencies
are in `requirements-eval.txt`. Credentials belong in ignored `backend/.env`.

```sh
python3 backend/ingest.py prepare --workdir backend/work/pilot \
  --quran apple/Muntathir/Resources/Quran/quran.db --limit 100
python3 backend/ingest.py estimate --workdir backend/work/pilot
python3 backend/ingest.py submit --workdir backend/work/pilot --max-usd 1
python3 backend/ingest.py poll --workdir backend/work/pilot
python3 backend/ingest.py upload --workdir backend/work/pilot
python3 backend/ingest.py activate --workdir backend/work/pilot
```

Supply `GEMINI_API_KEY` in the process environment for submit/poll. Preparation,
upload and activation do not make paid embedding calls. Upload now targets Qdrant.
Activation atomically switches the serving alias after completeness validation;
run relevance and load checks before a production revision switch.

For the full corpus, omit `--limit`, add `--hadith build/hadith/dist/hadith.db`, and
add translations explicitly with `--translation language:edition:SQLite-path`.
`--pilot` chooses judged positives plus a deterministic representative sample.
Existing full-corpus artifacts in `backend/work/full` have already been imported.
Do not submit the completed full corpus again.

Submission saves batch manifests. Poll can resume without redownloading completed
jobs; submit retries missing/failed entries. `--reuse <old-workdir>` reuses saved
vectors with matching input hashes. Canonical artifacts keep 3,072 dimensions;
upload derives normalized 1,536-dimensional prefixes without re-embedding.

### Refresh production after database changes

From the repository root, run `python3 build/build.py` to rebuild and package the
four libraries, estimate new Gemini Batch embeddings, and activate the candidate
after validation. Use `--dry-run` to estimate from the existing databases or
`--assets-only` for local packaging. Costs up to $10 are approved by default.
Set `--max-budget USD` to change that threshold. Above it, the script asks for
approval in a terminal. Rerun the same command to poll outstanding batches and
continue the refresh. The script needs the backend virtualenv and the validated
manifest and vectors for the active Qdrant collection. New reader references
without installed-pack compatibility evidence block activation.

The commands below document the manual recovery path. Use a new workdir for each
revision and retain the previous validated workdir and its source provenance.

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
  --provenance backend/work/provenance.json "${translations[@]}"
backend/.venv/bin/python backend/ingest.py estimate --workdir "$work" --reuse "$prior"
```

Review the estimate, export `GEMINI_API_KEY`, and replace `15` with the approved
USD cap for the revision. The offline estimate deduplicates new inputs and uses
UTF-8 bytes as a conservative token proxy at the
[Gemini Embedding 2 Batch text rate](https://ai.google.dev/gemini-api/docs/pricing/#gemini-embedding-2).
The cap includes prior accepted or unresolved batches. Recheck the estimate
before increasing it to cover retries of failed billed inputs.

```bash
backend/.venv/bin/python backend/ingest.py submit --workdir "$work" --reuse "$prior" --max-usd 15
backend/.venv/bin/python backend/ingest.py poll --workdir "$work"
backend/.venv/bin/python backend/ingest.py estimate --workdir "$work" --reuse "$prior"
```

Poll and resubmit as needed until pending and missing are both zero, then stage
the candidate and read its collection name from `$work/qdrant-progress.json`.

```bash
backend/.venv/bin/python backend/ingest.py upload --workdir "$work"
backend/.venv/bin/python backend/exact_reference.py --corpus "$work" --output "$work/exact-1536.json"
collection=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["collection"])' "$work/qdrant-progress.json")
SEARCH_COLLECTION="$collection" bun backend/api/verify.ts quality "$work/quality.json" backend/evaluation.json "$work/exact-1536.json"
SEARCH_COLLECTION="$collection" TEST_RATE=2 TEST_SECONDS=60 bun backend/api/verify.ts load "$work/sustained.json"
SEARCH_COLLECTION="$collection" TEST_RATE=20 TEST_SECONDS=10 bun backend/api/verify.ts load "$work/burst.json"
```

Record the active collection for rollback. Once all checks pass and the matching
Hadith pack is available to external testers, run
`backend/.venv/bin/python backend/ingest.py activate --workdir "$work"`. Smoke-test
Quran and scoped Hadith search against the running API.

Content IDs preserve source identity. Text revisions retain original text,
translation edition/attribution and exact code-point passage offsets. The compact
API omits this metadata, but the importer and index retain it internally.
Optional `--provenance file.json` overrides known source metadata; license metadata
is not an embedding prerequisite. Preserve available credits and source terms.

Dua input (`--dua file.json`) is supported now; the app's dua reader remains deferred:

```json
[{"id":"stable-dua-id","title":"Name","source_id":"collection","source_name":"Collection",
  "texts":[{"language":"ar","edition":"edition-id","attribution":"Source","text":"Full supplication"}]}]
```

Titles are labels, not identity. Short duas remain whole; longer texts use meaningful
paragraph chunks. Passage numbering is not assumed to align across translations.

## Verification

```sh
backend/.venv/bin/python -m unittest discover -s backend -p 'test_*.py'
bun install --cwd backend/api
bun run --cwd backend/api check
bun test backend/api
bun backend/api/verify.ts quality backend/work/qdrant-only-quality.json
python3 apple/scripts/check_localizations.py
```

The quality command enforces exact-vector agreement, candidate counts, and the
accepted relevance baseline. It uses saved query embeddings. The 150-query fixture
contains 80 previously reviewed queries and 70 seed-positive additions needing
expert review; judgments are not exhaustive.

`exact_reference.py` can generate new exhaustive references from corpus artifacts.
Historical PostgreSQL benchmark reports remain for comparison; their retired
commands and infrastructure are not part of current deployment.

### Hosted reranker benchmark

See [RERANK_BENCHMARK.md](RERANK_BENCHMARK.md) for the frozen-candidate comparison of OpenAI Decisions, Jev, and Gemini Flash-Lite. Preparation and dry runs need no provider keys; paid runs require explicit execution. Production uses Jev for eligible meaning-search reranking.

### Rulings

Pass `--rulings build/rulings/dist/rulings.db` to corpus preparation. The source folder, API kind, and asset pack are `rulings`. Each item is
one authority/language/site-ID combination, regardless of SQLite row IDs or topic
placements. The text retains the original question and answer; empty answer fields
remain empty when the source supplies its text in the question field.

Requests use `kinds: ["rulings"]`, `sources: ["sistani"]`, and `languages: ["ar"]`.
Compact results contain `kind`, `authority`, `language`, `id`, and `score`.
The app hydrates these references from its downloaded `Rulings/rulings.db`.
Authority and language filters apply before semantic and lexical ranking.

Production corpus additions must retain the currently active corpus, not an
unactivated local refresh. Reuse saved vectors, validate the candidate collection,
and retain the previous alias target for rollback before activating.

The November 14, 2026 rollout activated
`search_c6d8394dc7714732937c9f30d7176249_fdcc5a4c48a8` (81,921 items;
225,870 passages). Rollback target retained:
`search_a521108e91d54bda8fbe324c4e3bea67_476773511098`.
Candidate validation passed 150 relevance queries, all 11 authority/language
scopes, and 320 load requests without errors. Public Quran, Hadith, and Arabic
and English Sistani searches passed after activation. Artifacts are stored locally
under `work/rulings-production-2026-11-14/`.

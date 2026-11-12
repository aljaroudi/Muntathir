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
python3 backend/ingest.py submit --workdir backend/work/pilot
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

# Arabic source library

Keep the OpenITI release (currently `OpenITI_data_2025-1-9`) and its metadata TSV in `data/`. That folder is ignored by Git.

## Classify before importing

Classify by the work itself, not by its filename or markup:

- **Narrations** (numbered reports and chapters) go in the Hadith library.
- **Supplications** (individually titled prayers) go in Tools → Supplications.
- **Books** (continuous prose) need a Books reader, which doesn't exist yet. Don't force them into narration records.

## Add an edition

1. Find the URI in the TSV. Inspect its headings, numbering, volumes, commentary, and editorial matter.
2. Add the URI to `build/hadith/build.py`, along with an edition-specific parser (`parse_openiti` or `import_collections.py`). Preserve the text, printed numbers, and page references. For prayer collections, also extend `extract_supplications`.
3. Pin its SHA-256 and entry counts in `build/hadith/data/openiti-editions.json`, then add boundary tests. Never infer Arabic titles from English summaries.
4. Run `python3 -m unittest discover -s build/hadith`, then `uv run build/hadith/build.py --sittah --four`, and a full build with `--output /tmp/hadith-full.db`. Check gaps, IDs, foreign keys, and search. Package with `just apple-packs`.

Commit parsers and reviewed mappings, never source files or generated databases. See [asset packs](../../apple/AssetPacks/README.md).

## Source limits

- وسائل الشيعة: آل البيت edition, 30 volumes.
- بحار الأنوار: 106 volumes; 103 and 108–110 are missing. Entry counts include commentary, so they aren't hadith totals.
- الوافي: not in this release. Don't substitute الصافي or الوافي بالوفيات.

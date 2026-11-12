# Arabic source library

Keep the OpenITI release and metadata TSV in `data/` (local, ignored by Git).
The current release is `OpenITI_data_2025-1-9` with its matching metadata TSV.

## Classify before importing

- **Narrations:** numbered reports, chapters, and accompanying commentary → Hadith library.
- **Supplications:** individually titled prayers → Tools → Supplications; the source book is a section. Search names/content, without next/previous navigation.
- **Books:** continuous prose without either structure → a separate Books reader. This reader is not implemented yet; do not force these texts into narration records.

Classification follows the work, not the filename or missing OpenITI markup.

## Add an edition

1. Find the exact URI in the TSV; inspect the file's metadata, headings, numbering, volumes, commentary, and editorial matter.
2. Add the URI to `build/hadith/build.py` and a reviewed, edition-specific parser (`parse_openiti` or `import_collections.py`). Preserve text, printed source numbers, and page/edition references; use deterministic internal IDs where numbering is absent. For another prayer collection, extend `extract_supplications` and the supplication reader queries as well.
3. Pin its SHA-256, reading-entry count, and per-volume counts in `build/hadith/data/openiti-editions.json`. Add boundary tests. Never infer missing Arabic titles from English summaries.
4. Run `python3 -m unittest discover -s build/hadith`; build both `uv run build/hadith/build.py --sittah --four` and a full build with `--output /tmp/hadith-full.db`. Check gaps, identities, foreign keys, and search. The builder writes `hadith.db` and a separate `supplications.db`. Package locally with `python3 apple/AssetPacks/assets.py package apple/build/AssetPacks/archives --content all`.

The pinned additions load in full and `--four` builds; only الاستبصار belongs to the Four Books. Track parsers and reviewed mappings, never bulk sources or generated databases. See [asset workflow](../../apple/AssetPacks/README.md).

## Source limits

- وسائل الشيعة: آل البيت edition, 30 volumes.
- بحار الأنوار: 106 supplied volumes; 103 and 108–110 are absent. Reading entries include commentary and unnumbered prose; counts are not canonical hadith totals.
- الوافي: absent from this release; pending a supplied source. Do not substitute الصافي or الوافي بالوفيات.

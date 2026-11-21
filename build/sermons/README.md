# Bundled sermons

Run `just data-build --assets-only` at the repository root after editing publication inputs. The deterministic
builder writes `shared/sermons/sermons.db`, bundled by both apps and rebuilt by the unified
content build. Run `python3 -m unittest discover -s build/sermons` to check the published file.
Each sermon's `speaker_id` is a verified figure ID from `shared/figures/figures.json`; the apps show that figure's name and link to its profile.

## Fadak editions

The Arabic reader starts with the narrator’s introduction (s006). Its speech and dialogue
run from s008 through s182. Editions can cover individual clauses or contiguous ranges.
All editions use the same Arabic reading paragraphs. Source ranges must fit inside one paragraph. An uncovered passage
remains readable in Arabic. Credits identify the human sources.

The 13 human editions span ten languages. The English Ahl al-Bayt World Assembly edition (from WikiShia) uses its numbered bilingual text.
The other twelve editions have source-specific range mappings in `fadak/human/`. These retain
the supplied translation in source order within each passage and omit unmatched commentary.
The four English and Simplified Chinese literal and simplified editions use the same reader.

### Source differences

- **German** — [WikiShia, revision 14317](https://de.wikishia.net/index.php?title=Khutba_al-Fadakiyya&oldid=14317)
  continues past the local file’s mid-sentence cutoff. Its German version ends with Fatima’s
  address to her listeners. The corresponding canonical passages extend to s143. The later
  exchange beginning at s144 has no German counterpart on that page.
- **Spanish and English Ordoni** — the sources give excerpts. Only matching portions of the
  speech appear. Russian and Turkish also omit portions of the later canonical exchange.
- **Basmala** — a `basmala` field records a publisher-supplied conventional rendering separately
  from the credited source text. It is used for Azerbaijani, Persian, Indonesian, Swahili,
  Urdu, and the al-Jibouri and HubeAli English editions. The builder checks the rest of the
  spoken text before adding it. The German and English Ahl al-Bayt World Assembly editions supply their own opening.
- **Poetry** — match individual verses where the source order differs. Source-only verses
  and commentary stay in the authoring documents.

## Authoring

For a human edition, edit its JSON under `fadak/human/`. Keep the source filename and
credit with the edition. Each passage contains its source wording, a starting `segmentId`,
and an optional inclusive `endSegmentId`. Order passages by the canonical Arabic and omit
a row when the edition has no corresponding wording. Put a supplied basmala in the separate
`basmala` field. The builder displays it only when the remaining spoken passages are covered.
Run `just data-build --assets-only` after updating an edition.

From `build/sermons/fadak/`, run `bun install --frozen-lockfile` to set up the authoring tools.
Keep provider credentials in the ignored local `.env`. Normal app and content builds work offline.

- `bun run segments` regenerates the Arabic segment input from the source Markdown.
- `bun run translate --lang en` generates translation candidates. This calls configured providers.
- `bun run align --lang en` aligns generated editions to Arabic passages.
- After reviewing the result, `bun run publish --lang en` copies the aligned machine passages into
  versioned publication inputs. Run `just data-build --assets-only` and inspect the resulting diff.
- `bun run status`, `bun test`, and `bun run typecheck` report progress and check the tooling.

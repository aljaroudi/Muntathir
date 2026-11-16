# Hosted reranker comparison

The standalone `api/benchmark.ts` compares OpenAI Decisions, Jev, and Gemini Flash-Lite with deterministic retrieval. It never changes the production reranker, collection alias, embeddings, or asset packs. No provider keys are needed for preparation or dry runs.

## Prepared experiment

The current snapshot is `backend/work/refresh-2026-11-14/rerank-candidates.json`. It freezes the top 20 fused candidates per evaluation query from `search_a6924d0407894f02a372bca8bce23f25_163940aeaabf`. All providers receive the same complete winning passage text and candidate order. Source references remain attached for review. No relevance labels or split metadata enter provider prompts.

OpenAI and Jev independently score passage relevance; Gemini returns an ordered list of IDs. Scores break ties with the original ranking. Invalid IDs, duplicate IDs, refusals, malformed responses, HTTP errors, and timeouts retain the baseline. Requests are sequential, have a two-second deadline, and never retry. Latency includes HTTP and response parsing, but excludes retrieval. This is a single-pass latency sample, not a load test.

Run from the repository root:

```sh
# Read-only Qdrant retrieval using existing query vectors; no embedding API calls.
SEARCH_COLLECTION=search_a6924d0407894f02a372bca8bce23f25_163940aeaabf \
  bun backend/api/benchmark.ts prepare backend/work/refresh-2026-11-14/rerank-candidates.json

# Entirely offline. Pricing is deliberately unset until verified for the selected models.
bun backend/api/benchmark.ts dry-run \
  backend/work/refresh-2026-11-14/rerank-candidates.json backend/benchmark.example.json
```

Preparation refuses to overwrite the snapshot. Use another filename to prepare a new corpus. Snapshot and query-file hashes identify the exact inputs. Generated snapshots and output logs live under ignored `backend/work/`.

## When keys are available

Set `OPENAI_API_KEY`, `JEV_API_KEY` (or `TYPESAFE_API_KEY`), and `GEMINI_API_KEY` in the local environment or ignored `backend/.env`; do not commit or paste secrets into this document. Bun commands below can use `bun --env-file=backend/.env ...` if needed.

Copy `backend/benchmark.example.json` into `backend/work/benchmark.json`. Verify model availability, select explicit model versions where supported, and fill current input/output USD per million token rates. The template models are starting points, not claims about the best current provider model. Dry-run again before execution. The estimate assumes one input token per serialized UTF-8 byte and, conservatively, repeats shared input for every decision question; it reserves 2,048 output tokens per call. This is a planning allowance, not a provider-enforced spending cap. Account for provider-specific billing and check provider usage after running.

Only after approving the displayed estimate:

```sh
bun backend/api/benchmark.ts run \
  backend/work/refresh-2026-11-14/rerank-candidates.json \
  backend/work/benchmark.json backend/work/benchmark-results.jsonl --execute

bun backend/api/benchmark.ts report backend/work/benchmark-results.jsonl
```

Paid execution requires filled pricing, all selected keys, and `--execute`. It refuses an existing result file. Each request is journaled and flushed before sending; each result saves raw provider usage, requested/resolved model, latency, outcome, IDs, and baseline/reranked metrics. There is deliberately no automatic resume: an interrupted attempt may have been billed. Reconcile it before creating another run. Never overwrite an interrupted log.

## Judgments and acceptance

Review `SEARCH_RELEVANCE_REVIEW.md` first. Existing evaluation labels include incomplete seed positives; unknown candidates are not verified negatives. The report exposes unjudged top-ten results and separates provider/model, split, language, and review status. NDCG@10 and top-result accuracy are provisional until candidate pools are reviewed. Candidate recall measures the frozen top-20 pool, not full-corpus recall, and reranking cannot change it.

Use tuning queries to change prompts; keep held-out release judgments separate. Before selection, require improved held-out NDCG@10, no reviewed language-group regressions, correct references, acceptable p95 latency and failure rate, and verified usage cost per search. Include negative queries and inspect ambiguous religious intent manually. All-negative queries have undefined NDCG/positive recall; inspect their rankings separately. These reports never authorize automatic activation. Existing exact-match and full-corpus relevance/load gates still apply.

## API contracts

Adapters follow [OpenAI Decisions](https://developers.openai.com/api/docs/guides/decisions), [Jev's HTTP quickstart](https://docs.typesafe.ai/introduction/quickstart), and [Gemini structured output](https://ai.google.dev/gemini-api/docs/structured-output). They are covered by offline contract tests. Live authentication, current model availability, billing, and real latency remain unverified until keys arrive.

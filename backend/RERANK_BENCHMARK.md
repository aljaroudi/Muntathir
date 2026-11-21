# Hosted reranker comparison

`backend/api/benchmark.ts` compares OpenAI Decisions, Jev and Gemini Flash-Lite on frozen
retrieval candidates. It never touches the production reranker, alias, embeddings or
packs. Production uses Jev ([results](JEV_BENCHMARK_RESULTS.md)).

## Snapshot

`backend/work/refresh-2026-11-14/rerank-candidates.json` freezes the top 20 fused
candidates per evaluation query from
`search_a6924d0407894f02a372bca8bce23f25_163940aeaabf`.

- Every provider gets the same full passage text and order; no labels or split metadata
  in prompts.
- OpenAI and Jev score passages; Gemini returns ordered IDs. Ties fall back to baseline
  order. Invalid/duplicate IDs, refusals, malformed responses, HTTP errors and timeouts
  keep the baseline.
- Sequential requests, 2 s deadline, no retries. Latency covers HTTP + parsing, not
  retrieval; it is a single-pass sample, not a load test.

## Prepare and dry run (no keys, no paid calls)

From the repository root:

```sh
# Read-only Qdrant retrieval using saved query vectors.
SEARCH_COLLECTION=search_a6924d0407894f02a372bca8bce23f25_163940aeaabf \
  bun backend/api/benchmark.ts prepare backend/work/refresh-2026-11-14/rerank-candidates.json

# Offline cost estimate.
bun backend/api/benchmark.ts dry-run \
  backend/work/refresh-2026-11-14/rerank-candidates.json backend/benchmark.example.json
```

`prepare` refuses to overwrite an existing snapshot; use a new filename.

## Paid run

1. Set `OPENAI_API_KEY`, `JEV_API_KEY` (or `TYPESAFE_API_KEY`) and `GEMINI_API_KEY` in
   the environment or `backend/.env` (use `bun --env-file=backend/.env ...`). Never commit
   keys.
2. Copy `backend/benchmark.example.json` to `backend/work/benchmark.json`; pin model
   versions and fill current input/output USD per million tokens (template models are
   only starting points).
3. Dry-run again. The estimate (1 token per UTF-8 byte, shared input repeated per
   question, 2,048 output tokens reserved per call) is an allowance, not a spending cap.
4. After approving the estimate:

```sh
bun backend/api/benchmark.ts run \
  backend/work/refresh-2026-11-14/rerank-candidates.json \
  backend/work/benchmark.json backend/work/benchmark-results.jsonl --execute

bun backend/api/benchmark.ts report backend/work/benchmark-results.jsonl
```

`run` requires pricing, all keys and `--execute`, and refuses an existing result file.
Each request is journaled before sending. **There is no resume:** an interrupted run may
have been billed — reconcile provider usage before starting another, and never overwrite
the interrupted log.

## Acceptance

- Review [SEARCH_RELEVANCE_REVIEW.md](SEARCH_RELEVANCE_REVIEW.md) first. Labels are
  incomplete seed positives; unjudged candidates are not negatives, so NDCG@10 and
  top-result accuracy are provisional. Candidate recall is fixed by the top-20 pool.
- Tune prompts on tuning queries only; keep held-out judgments separate.
- Selection requires improved held-out NDCG@10, no reviewed language-group regression,
  correct references, acceptable p95 latency and failure rate, and verified cost.
  Inspect all-negative and ambiguous queries manually.
- Reports never authorize activation; the full-corpus relevance/load gates still apply.

Adapters follow [OpenAI Decisions](https://developers.openai.com/api/docs/guides/decisions),
[Jev quickstart](https://docs.typesafe.ai/introduction/quickstart) and
[Gemini structured output](https://ai.google.dev/gemini-api/docs/structured-output), with
offline contract tests.

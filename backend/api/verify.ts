// Uses saved embeddings only; never sends evaluation fixtures to Gemini.
import { Qdrant, retrieve } from "./search.ts";
import { hash, PROFILE } from "./core.ts";
import { writeFileSync } from "node:fs";
const [
  mode = "quality",
  output = "backend/work/qdrant-only-quality.json",
  queriesPath = "backend/evaluation.json",
  referencePath = "backend/work/exact-1536.json",
] = process.argv.slice(2);
const queries = (await Bun.file(queriesPath).json()).queries;
const db = new Qdrant(
  process.env.QDRANT_URL ?? "http://127.0.0.1:56333",
  process.env.QDRANT_API_KEY,
);
const collection = process.env.SEARCH_COLLECTION ?? (await db.active());
const vectors: number[][] = [];
for (const q of queries) {
  const file = `backend/work/query-vectors/${await hash(`gemini-embedding-2:3072:search-v1:${q.query}`)}.json`;
  const vector = (await Bun.file(file).json()).slice(0, 1536);
  const norm = Math.sqrt(vector.reduce((s: number, x: number) => s + x * x, 0));
  vectors.push(vector.map((x: number) => x / norm));
}
const input = (q: any, limit = 100) => ({
  query: q.query,
  kinds: q.kinds ?? null,
  sources: q.sources ?? null,
  languages: q.languages ?? null,
  limit,
});
const percentile = (values: number[]) =>
  values.sort((a, b) => a - b)[
    Math.max(0, Math.ceil(values.length * 0.95) - 1)
  ];
if (mode === "quality") {
  const reference = await Bun.file(referencePath).json();
  const details: any[] = [];
  if (reference.dimensions !== 1536)
    throw new Error("Reference dimensions mismatch");
  for (let i = 0; i < queries.length; i++) {
    const q = queries[i],
      start = performance.now();
    const result = await retrieve(db, collection, input(q), vectors[i], null);
    const ids = result.itemIDs!,
      semantic = result.semanticIDs!,
      expected = new Set(reference.results[q.id]);
    if (!expected.size) throw new Error(`Missing exact reference: ${q.id}`);
    const positives = Object.keys(q.relevant);
    const recall = positives.length
      ? positives.filter((id) => ids.includes(id)).length / positives.length
      : null;
    function dcg(values: number[]) {
      return values.reduce((s, v, j) => s + (2 ** v - 1) / Math.log2(j + 2), 0);
    }
    const ideal = dcg(
      Object.values(q.relevant)
        .map(Number)
        .sort((a, b) => b - a)
        .slice(0, 10),
    );
    details.push({
      id: q.id,
      overlap: semantic.filter((id) => expected.has(id)).length / expected.size,
      count: semantic.length,
      recall_at_100: recall,
      ndcg_at_10: ideal
        ? dcg(ids.slice(0, 10).map((id) => q.relevant[id] ?? 0)) / ideal
        : null,
      ms: performance.now() - start,
      item_ids: ids,
    });
    if ((i + 1) % 25 === 0) console.log("Evaluated", i + 1);
  }
  function mean(key: string) {
    const values = details.map((d: any) => d[key]).filter((v) => v !== null);
    return values.reduce((s, v) => s + v, 0) / values.length;
  }
  const report = {
    collection,
    profile: PROFILE,
    queries: details.length,
    recall_at_100: mean("recall_at_100"),
    ndcg_at_10: mean("ndcg_at_10"),
    minimum_overlap: Math.min(...details.map((d) => d.overlap)),
    p95_ms: percentile(details.map((d) => d.ms)),
    details,
  };
  const baseline = queriesPath === "backend/evaluation.json";
  const gatePassed =
    report.minimum_overlap === 1 &&
    details.every((d) => d.count === 100) &&
    (!baseline ||
      (report.recall_at_100 + 1e-9 >= 0.9605633802816902 &&
        report.ndcg_at_10 + 1e-9 >= 0.780596));
  writeFileSync(
    output,
    JSON.stringify({ ...report, gate_passed: gatePassed }, null, 2),
  );
  console.log(
    JSON.stringify({ ...report, details: undefined, gate_passed: gatePassed }),
  );
  if (!gatePassed) process.exitCode = 1;
} else {
  const rate = Number(process.env.TEST_RATE ?? 2),
    seconds = Number(process.env.TEST_SECONDS ?? 60);
  // Warm every fixture; measure retrieval only with saved embeddings and no result cache.
  for (let i = 0; i < queries.length; i++)
    await retrieve(db, collection, input(queries[i], 20), vectors[i], null);
  const start = performance.now(),
    pending = [];
  for (let i = 0; i < rate * seconds; i++) {
    const scheduled = start + (i * 1000) / rate;
    await Bun.sleep(Math.max(0, scheduled - performance.now()));
    pending.push(
      (async () => {
        try {
          const j = i % queries.length;
          const result = await retrieve(
            db,
            collection,
            input(queries[j], 20),
            vectors[j],
            null,
          );
          return {
            ok: true,
            ms: performance.now() - scheduled,
            count: result.results.length,
          };
        } catch {
          return { ok: false, ms: performance.now() - scheduled };
        }
      })(),
    );
  }
  const details = await Promise.all(pending);
  const report = {
    collection,
    rate,
    seconds,
    requests: details.length,
    errors: details.filter((d) => !d.ok).length,
    p95_ms: percentile(details.map((d) => d.ms)),
    details,
  };
  writeFileSync(output, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ...report, details: undefined }));
  if (report.errors || report.p95_ms >= 300) process.exitCode = 1;
}

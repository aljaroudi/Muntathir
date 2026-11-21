import fs from "node:fs/promises";
import path from "node:path";
import { alignTranslation } from "./align";
import { findManualKagiTranslation, loadContextBundle } from "./context";
import { resolveTargetLanguage } from "./languages";
import { loadRows, saveRows } from "./rows";
import { buildSegments, type TranslationRow, toRows } from "./segments";

/**
 * Give already-finished translations segment IDs without re-translating:
 *   bun run align --lang en [--file <md> --label <name> [--register literal|simplified]] [--force]
 * Default sources: output/<code>/{literal,simplified}.md (ai), data/kagi/<code>-kagi.md (kagi),
 * and, for English, the WikiShia aligned file (needs no model).
 */
function flag(argv: string[], name: string): string | undefined {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
}

async function main() {
  const argv = Bun.argv.slice(2);
  const rootDir = path.resolve(import.meta.dir, "..");
  const dataDir = path.join(rootDir, "data");
  const lang = resolveTargetLanguage(flag(argv, "lang") ?? "en");
  const force = argv.includes("--force");
  const model = (flag(argv, "model") ?? process.env.MODEL_ALIGN ?? process.env.MODEL_GEMINI ?? "google/gemini-4-carbon") as never;

  const outDir = path.join(rootDir, "output", lang.code);
  const rowsFile = path.join(outDir, "translations.json");
  const bundle = await loadContextBundle(dataDir, lang);
  const segments = buildSegments(bundle.fullArabicText, bundle.alignedReference);
  const existing = await loadRows(rowsFile);
  const has = (source: string, register: TranslationRow["register"]) =>
    existing.some((r) => r.source === source && r.register === register);

  // [source, register, text]
  const jobs: Array<{ source: string; register: TranslationRow["register"]; text: string }> = [];
  const file = flag(argv, "file");
  if (file) {
    const label = flag(argv, "label");
    if (!label) throw new Error("--file needs --label <name>");
    const register = (flag(argv, "register") as TranslationRow["register"]) ?? null;
    jobs.push({ source: `human:${label}`, register, text: await fs.readFile(file, "utf8") });
  } else {
    for (const register of ["literal", "simplified"] as const) {
      const text = await fs.readFile(path.join(outDir, `${register}.md`), "utf8").catch(() => "");
      if (text.trim()) jobs.push({ source: "ai", register, text });
    }
    const kagi = await findManualKagiTranslation(dataDir, lang);
    if (kagi) jobs.push({ source: "kagi", register: null, text: kagi.text });
  }

  // WikiShia is already aligned by segment number, so it needs no model.
  if (!file && lang.code === "en" && (force || !has("human:wikishia", null))) {
    const byId = new Map(
      segments.filter((s) => s.wikishiaIndex !== undefined).map((s) => [
        s.id,
        bundle.alignedReference.find((a) => a.index === s.wikishiaIndex)?.english ?? "",
      ]),
    );
    await saveRows(rowsFile, toRows(segments.filter((s) => byId.has(s.id)), byId, "human:wikishia", null));
    console.log(`human:wikishia  ${byId.size} segments (direct, no model)`);
  }

  let totalCost = 0;
  for (const job of jobs) {
    const name = `${job.source}${job.register ? `/${job.register}` : ""}`;
    if (!force && has(job.source, job.register)) {
      console.log(`${name}  already aligned (use --force to redo)`);
      continue;
    }
    const { byId, result } = await alignTranslation({
      segments,
      translation: job.text,
      language: lang,
      label: `align ${name}`,
      warn: (m) => console.warn(m),
      gateway: {
        model,
        apiKey: process.env.AI_GATEWAY_API_KEY,
        baseUrl: process.env.AI_GATEWAY_BASE_URL,
        timeoutMs: 1_800_000,
      },
    });
    await saveRows(rowsFile, toRows(segments, byId, job.source, job.register));
    totalCost += result.usage.costUsd ?? 0;
    console.log(`${name}  ${segments.length} segments | $${(result.usage.costUsd ?? 0).toFixed(4)} | ${(result.durationMs / 1000).toFixed(0)}s`);
  }
  if (totalCost > 0) console.log(`Total $${totalCost.toFixed(4)} -> ${path.relative(rootDir, rowsFile)}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

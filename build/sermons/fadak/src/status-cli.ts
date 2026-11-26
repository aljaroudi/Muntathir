import fs from "node:fs/promises";
import path from "node:path";
import { listTargetLanguages, type TargetLanguage } from "./languages";
import { manualKagiPath } from "./context";
import type { RunMetricsReport } from "./types";
import type { TranslationRow } from "./segments";

const CHECK = "✅";

function mark(count: number): string {
  if (count <= 0) return "—";
  if (count === 1) return CHECK;
  return `${CHECK} +${count - 1}`;
}

async function countHuman(dataDir: string, lang: TargetLanguage): Promise<number> {
  const dir = path.join(dataDir, "translations", `${lang.code} - ${lang.name}`);
  try {
    return (await fs.readdir(dir)).filter((f) => f.endsWith(".md")).length;
  } catch {
    return 0;
  }
}

async function hasKagi(dataDir: string, lang: TargetLanguage): Promise<boolean> {
  try {
    const text = await fs.readFile(manualKagiPath(dataDir, lang), "utf8");
    return text.trim().length > 0;
  } catch {
    return false;
  }
}

async function aiStatus(outDir: string): Promise<{ done: boolean; costUsd: number | null }> {
  try {
    const st = await fs.stat(path.join(outDir, "literal.md"));
    if (st.size === 0) return { done: false, costUsd: null };
  } catch {
    return { done: false, costUsd: null };
  }
  try {
    const metrics = JSON.parse(
      await fs.readFile(path.join(outDir, "metrics.json"), "utf8"),
    ) as RunMetricsReport;
    return { done: true, costUsd: metrics.grandTotals.costUsd };
  } catch {
    return { done: true, costUsd: null };
  }
}

async function alignedSources(outDir: string): Promise<string[]> {
  try {
    const rows = JSON.parse(
      await fs.readFile(path.join(outDir, "translations.json"), "utf8"),
    ) as TranslationRow[];
    return [
      ...new Set(
        rows.map((r) => (r.register ? `${r.source}/${r.register}` : r.source)),
      ),
    ].sort();
  } catch {
    return [];
  }
}

function usd(n: number | null): string {
  return typeof n === "number" ? `$${n.toFixed(2)}` : "—";
}

async function main() {
  const rootDir = path.resolve(import.meta.dir, "..");
  const dataDir = path.join(rootDir, "data");
  const outputDir = path.join(rootDir, "output");

  const rows: string[] = [];
  let humanDone = 0;
  let machineDone = 0;
  let aiDone = 0;
  let totalCost = 0;

  for (const lang of listTargetLanguages()) {
    const out = path.join(outputDir, lang.code);
    const human = await countHuman(dataDir, lang);
    const kagi = await hasKagi(dataDir, lang);
    const ai = await aiStatus(out);
    const aligned = await alignedSources(out);

    const machineCount = Number(kagi) + Number(ai.done);
    if (human > 0) humanDone++;
    if (machineCount > 0) machineDone++;
    if (ai.done) {
      aiDone++;
      if (ai.costUsd) totalCost += ai.costUsd;
    }

    const speakers =
      typeof lang.muslimSpeakersM === "number" ? String(lang.muslimSpeakersM) : "—";
    rows.push(
      `| ${lang.code} | ${lang.name} | ${speakers} | ${mark(human)} | ${mark(machineCount)} | ${usd(ai.costUsd)} | ${aligned.length ? aligned.join(", ") : "—"} |`,
    );
  }

  const md = [
    "# Translation outputs",
    "",
    "Each subdirectory is a target language code (`--lang <code>`).",
    "",
    "- **Speakers:** estimated Muslim speakers in millions (primary ranking). `—` = kept because material already exists",
    "- **Human:** files under `data/translations/<code> - <Name>/`",
    "- **Machine:** Kagi file in `data/kagi/<code>-kagi.md` and/or finished AI run in `output/<code>/`",
    "- **AI cost:** gateway spend from that language's `metrics.json` (translation only; alignment is separate)",
    "- **Aligned:** sources present in `output/<code>/translations.json` (segment IDs for the bundled reader)",
    "",
    "`✅` = present. `✅ +N` = N extra of that type. `—` = none.",
    "",
    "Regenerate this table: `bun run status`",
    "",
    `**Progress:** ${humanDone} human · ${machineDone} machine · ${aiDone} AI done · AI spend ${usd(totalCost)}`,
    "",
    "| Code | Language | Speakers (M) | Human | Machine | AI cost | Aligned |",
    "|---|---|---:|---|---|---|---|",
    ...rows,
    "",
  ].join("\n");

  await fs.writeFile(path.join(outputDir, "README.md"), md, "utf8");
  console.log(`Wrote output/README.md (${listTargetLanguages().length} languages)`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

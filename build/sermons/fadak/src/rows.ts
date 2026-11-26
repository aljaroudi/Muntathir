import fs from "node:fs/promises";
import type { TranslationRow } from "./segments";

export async function loadRows(file: string): Promise<TranslationRow[]> {
  try {
    return JSON.parse(await fs.readFile(file, "utf8")) as TranslationRow[];
  } catch {
    return [];
  }
}

/** Merge into the language's `translations.json`; rows of the same source+register are replaced. */
export async function saveRows(file: string, rows: TranslationRow[]): Promise<void> {
  const replaced = new Set(rows.map((r) => `${r.source}|${r.register}|${r.segmentId}`));
  const kept = (await loadRows(file)).filter(
    (r) => !replaced.has(`${r.source}|${r.register}|${r.segmentId}`),
  );
  await fs.writeFile(file, `${JSON.stringify([...kept, ...rows], null, 1)}\n`, "utf8");
}

/** Keep each published passage on one diffable line. */
export function formatRows(rows: readonly unknown[]): string {
  return "[\n" + rows.map(row => "  " + JSON.stringify(row)).join(",\n") + "\n]";
}

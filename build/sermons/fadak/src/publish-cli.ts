import fs from "node:fs/promises";
import path from "node:path";
import { resolveTargetLanguage } from "./languages";
import { formatRows, loadRows } from "./rows";

// Publish aligned literal and simplified passages. Other rows remain authoring inputs.
const args = Bun.argv.slice(2);
if (args.length !== 2 || args[0] !== "--lang") throw new Error("Usage: bun run publish --lang <code>");
const { code } = resolveTargetLanguage(args[1]);
const root = path.resolve(import.meta.dir, "..");
const segments: { id: string; wikishiaIndex?: number }[] = JSON.parse(await fs.readFile(path.join(root, "data/segments.json"), "utf8"));

const known = new Set(segments.map(segment => segment.id));
const rows = (await loadRows(path.join(root, "output", code, "translations.json"))).filter(row => row.source === "ai");
if (!rows.length) throw new Error("No aligned translation passages");
for (const register of ["literal", "simplified"]) {
  const selected = rows.filter(row => row.register === register);
  const ids = new Set(selected.map(row => row.segmentId));
  if (ids.size !== selected.length || selected.some(row => !known.has(row.segmentId) || !row.text.trim())) {
    throw new Error(`Unknown, empty, or duplicate passages in ${code}/${register}`);
  }
}
await fs.writeFile(path.join(root, "editions", `${code}.json`), formatRows(rows) + "\n");

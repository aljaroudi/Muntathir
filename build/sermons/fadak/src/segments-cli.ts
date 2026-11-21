import { formatRows } from "./rows";
import fs from "node:fs/promises";
import path from "node:path";
import { loadContextBundle } from "./context";
import { buildSegments } from "./segments";

/** Write data/segments.json: the canonical Arabic segments for the bundled reader. */
const dataDir = path.resolve(import.meta.dir, "../data");
const bundle = await loadContextBundle(dataDir);
const segments = buildSegments(bundle.fullArabicText, bundle.alignedReference);
await fs.writeFile(path.join(dataDir, "segments.json"), `${formatRows(segments)}\n`, "utf8");
console.log(`${segments.length} segments -> data/segments.json`);

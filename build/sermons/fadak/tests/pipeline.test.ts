import { describe, expect, test } from "bun:test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { resolveTargetLanguage } from "../src/languages";
import { runPipeline } from "../src/pipeline";
import type { PipelineConfig } from "../src/types";

describe("translation pipeline", () => {
  test("runPipeline translates full continuous document by default and picks up manual en-kagi.md", async () => {
    const tmpOut = await fs.mkdtemp(path.join(os.tmpdir(), "muntathir-tr-"));
    const dataDir = path.resolve(import.meta.dir, "../data");
    const targetLanguage = resolveTargetLanguage("en");

    const config: PipelineConfig = {
      dataDir,
      outputDir: tmpOut,
      targetLanguage,
      dryRun: true,
      skipMt: false,
      quiet: true,
      models: {
        gemini: "google/gemini-4-carbon",
        grok: "spacexai/grok-4.7",
        claude: "anthropic/claude-fable-5.2",
        gpt: "openai/gpt-6.2-astra",
      },
      googleLocation: "global",
    };

    const results = await runPipeline(config);
    expect(results.length).toBe(1);
    expect(results[0].sectionId).toBe("full-document");
    expect(results[0].targetLanguage).toBe("en");
    const kagiCandidate = results[0].candidates.find((c) => c.providerId === "kagi");
    expect(kagiCandidate?.kind).toBe("mt");
    expect(kagiCandidate?.literal).toContain("Sermon of Fadak");

    const literalMd = await fs.readFile(path.join(tmpOut, "en", "literal.md"), "utf8");
    const simplifiedMd = await fs.readFile(path.join(tmpOut, "en", "simplified.md"), "utf8");
    const rankingsMd = await fs.readFile(path.join(tmpOut, "en", "rankings.md"), "utf8");

    expect(literalMd).toContain("DRY RUN Final Literal (en)");
    expect(simplifiedMd).toContain("DRY RUN Final Simplified (en)");
    expect(rankingsMd).toContain("en-kagi.md");
  });
});

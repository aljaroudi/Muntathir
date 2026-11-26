import { describe, expect, test } from "bun:test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  normalizeRankCache,
  normalizeTextCache,
  readRankCache,
  readTextCache,
  toRankEnvelope,
  toTextEnvelope,
  writeRankCache,
  writeTextCache,
} from "../src/cache";
import type { CallMetrics } from "../src/types";

function baseMetrics(overrides: Partial<CallMetrics> = {}): CallMetrics {
  return {
    step: "step3-llm",
    sectionId: "full-document",
    providerId: "gpt",
    providerLabel: "GPT",
    durationMs: 10,
    inputTokens: 100,
    outputTokens: 50,
    totalTokens: 150,
    costUsd: 0.12,
    inputChars: 400,
    outputChars: 200,
    ...overrides,
  };
}

describe("cache envelope dual-read", () => {
  test("normalizes legacy flat text cache and v1 envelope", () => {
    const metrics = baseMetrics();
    const legacy = normalizeTextCache({ text: "hello", metrics });
    expect(legacy?.text).toBe("hello");
    expect(legacy?.metrics.costUsd).toBe(0.12);

    const envelope = normalizeTextCache(toTextEnvelope({ text: "hello", metrics }));
    expect(envelope?.text).toBe("hello");
    expect(envelope?.metrics.costUsd).toBe(0.12);
  });

  test("normalizes legacy flat rank cache and v1 envelope", () => {
    const metrics = baseMetrics({ step: "step4-rank", providerId: "claude-rank" });
    const legacyPayload = {
      rankings: [{ providerId: "gpt", rank: 1, score: 90, strengths: "ok", issues: "none" }],
      synthesisNotes: "notes",
      finalTranslation: "final",
      metrics,
    };
    const legacy = normalizeRankCache(legacyPayload);
    expect(legacy?.finalTranslation).toBe("final");
    expect(legacy?.rankings).toHaveLength(1);

    const envelope = normalizeRankCache(toRankEnvelope(legacy!));
    expect(envelope?.finalTranslation).toBe("final");
    expect(envelope?.metrics.costUsd).toBe(0.12);
  });

  test("writeTextCache persists v1 envelope that readTextCache can load", async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "muntathir-cache-"));
    const file = path.join(dir, "sample.json");
    const metrics = baseMetrics();
    await writeTextCache(file, { text: "cached text", metrics });

    const raw = JSON.parse(await fs.readFile(file, "utf8")) as Record<string, unknown>;
    expect(raw.version).toBe(1);
    expect(raw.kind).toBe("text");

    const loaded = await readTextCache(file);
    expect(loaded?.text).toBe("cached text");
    expect(loaded?.metrics.costUsd).toBe(0.12);
  });

  test("readTextCache still reads existing flat legacy files", async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "muntathir-cache-legacy-"));
    const file = path.join(dir, "legacy.json");
    await fs.writeFile(
      file,
      JSON.stringify({ text: "legacy", metrics: baseMetrics({ costUsd: 1.5 }) }, null, 2),
      "utf8",
    );
    const loaded = await readTextCache(file);
    expect(loaded?.text).toBe("legacy");
    expect(loaded?.metrics.costUsd).toBe(1.5);
  });

  test("writeRankCache / readRankCache round-trip", async () => {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "muntathir-cache-rank-"));
    const file = path.join(dir, "rank.json");
    await writeRankCache(file, {
      rankings: [{ providerId: "claude", rank: 1, score: 99, strengths: "a", issues: "b" }],
      synthesisNotes: "syn",
      finalTranslation: "# Final",
      metrics: baseMetrics({ step: "step4-rank", costUsd: 0.5 }),
    });
    const loaded = await readRankCache(file);
    expect(loaded?.finalTranslation).toBe("# Final");
    expect(loaded?.metrics.costUsd).toBe(0.5);
  });
});

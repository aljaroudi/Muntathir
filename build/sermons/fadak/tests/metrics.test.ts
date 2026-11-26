import { describe, expect, test } from "bun:test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { MockLanguageModelV4, simulateReadableStream } from "ai/test";
import { resolveTargetLanguage } from "../src/languages";
import { runPipeline } from "../src/pipeline";
import type { PipelineConfig, RunMetricsReport } from "../src/types";

describe("timing, token accounting, per-call caching, and file logging", () => {
  test("aggregates exact in/out/reasoning tokens & cost via Vercel AI SDK and skips Kagi API when manual file exists", async () => {
    const tmpOut = await fs.mkdtemp(path.join(os.tmpdir(), "muntathir-metrics-"));
    const dataDir = path.resolve(import.meta.dir, "../data");
    let kagiApiCalled = false;

    const mockFetch = (async (input: string | URL | Request) => {
      const url = String(input);
      if (url.includes("translation.googleapis.com")) {
        return new Response(
          JSON.stringify({ translations: [{ translatedText: "Google full literal translation" }] }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      }
      if (url.includes("translate.kagi.com")) {
        kagiApiCalled = true;
        return new Response(JSON.stringify({ translation: "Should not be called" }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }
      throw new Error(`Unexpected fetch URL: ${url}`);
    }) as typeof fetch;

    const modelResolver = (modelId: string) =>
      new MockLanguageModelV4({
        modelId,
        doStream: async (callOpts) => {
          // Echo every segment marker found in the prompt, as a well-behaved model would.
          const ids = [...new Set(JSON.stringify(callOpts.prompt).match(/⟦s\d+⟧/g) ?? [])];
          const marked = (label: string) => ids.map((m) => `${m} ${label}`).join("\n\n");
          const isStructuredRank = callOpts.responseFormat?.type === "json";
          const textPayload = isStructuredRank
            ? JSON.stringify({
                rankings: [
                  {
                    providerId: "claude",
                    rank: 1,
                    score: 97,
                    strengths: "Continuous precision",
                    issues: "None",
                  },
                ],
                synthesisNotes: "Synthesized full continuous sermon.",
                finalTranslation: marked(`Synthesized by ${modelId}`),
              })
            : marked(`${modelId} translation`);

          const inTok = isStructuredRank ? 2000 : 1000;
          const outTok = isStructuredRank ? 500 : 300;
          const rsnTok = isStructuredRank ? 100 : 50;

          return {
            stream: simulateReadableStream({
              chunks: [
                { type: "text-start", id: "t1" },
                { type: "text-delta", id: "t1", delta: textPayload },
                { type: "text-end", id: "t1" },
                {
                  type: "finish",
                  finishReason: { unified: "stop", raw: "stop" },
                  usage: {
                    inputTokens: { total: inTok, noCache: inTok, cacheRead: 0, cacheWrite: 0 },
                    outputTokens: { total: outTok, text: outTok - rsnTok, reasoning: rsnTok },
                  },
                  providerMetadata: { gateway: { cost: "0.05" } },
                },
              ],
            }),
          };
        },
      });

    const config: PipelineConfig = {
      dataDir,
      outputDir: tmpOut,
      targetLanguage: resolveTargetLanguage("en"),
      dryRun: false,
      skipMt: false,
      quiet: true,
      modelResolver,
      models: {
        gemini: "google/gemini-4-carbon",
        grok: "spacexai/grok-4.7",
        claude: "anthropic/claude-fable-5.2",
        gpt: "openai/gpt-6.2-astra",
      },
      googleProjectId: "test-proj",
      googleLocation: "global",
      googleAccessToken: "test-goog-token",
    };

    const results = await runPipeline(config, mockFetch);
    expect(results.length).toBe(1);
    expect(kagiApiCalled).toBe(false); // Loaded from data/kagi/en-kagi.md instead!

    const metricsPath = path.join(tmpOut, "en", "metrics.json");
    const logPath = path.join(tmpOut, "en", "translation.log");
    const rankingsPath = path.join(tmpOut, "en", "rankings.md");

    const metrics = JSON.parse(await fs.readFile(metricsPath, "utf8")) as RunMetricsReport;
    const logText = await fs.readFile(logPath, "utf8");
    const rankingsMd = await fs.readFile(rankingsPath, "utf8");

    // Step 2 MT: Google API + Manual Kagi file
    expect(metrics.totalsByStep["step2-mt"].callCount).toBe(2);

    // Step 3 LLM: 4 models * 2 registers = 8 calls * (1000 in, 300 out, 50 reasoning) = 8000 in, 2400 out
    expect(metrics.totalsByStep["step3-llm"].callCount).toBe(8);
    expect(metrics.totalsByStep["step3-llm"].inputTokens).toBe(8000);
    expect(metrics.totalsByStep["step3-llm"].outputTokens).toBe(2400);
    expect(metrics.totalsByStep["step3-llm"].reasoningTokens).toBe(400);

    // Step 4 Rank: 2 registers (literal + simplified) * (2000 in, 500 out) = 4000 in, 1000 out
    expect(metrics.totalsByStep["step4-rank"].callCount).toBe(2);
    expect(metrics.totalsByStep["step4-rank"].inputTokens).toBe(4000);
    expect(metrics.totalsByStep["step4-rank"].outputTokens).toBe(1000);

    // Grand totals: 12000 in, 3400 out, 15400 total, 10 SDK calls * $0.05 = $0.50
    expect(metrics.grandTotals.callCount).toBe(12);
    expect(metrics.grandTotals.inputTokens).toBe(12000);
    expect(metrics.grandTotals.outputTokens).toBe(3400);
    expect(metrics.grandTotals.totalTokens).toBe(15400);
    expect(metrics.grandTotals.costUsd).toBeCloseTo(0.5, 5);

    expect(logText).toContain("kagi: en-kagi.md");
    expect(logText).toContain("Tokens in=12,000 out=3,400 (reasoning=600) total=15,400");
    expect(rankingsMd).toContain("### Literal Rankings");
    expect(rankingsMd).toContain("### Simplified Rankings");
  });
});

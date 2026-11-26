import { describe, expect, test } from "bun:test";
import { MockLanguageModelV4, simulateReadableStream } from "ai/test";
import { z } from "zod";
import { resolveTargetLanguage } from "../src/languages";
import {
  callGatewayStreamStructured,
  callGatewayStreamText,
  extractJsonPayload,
} from "../src/llm/gateway";
import {
  buildRegisterRankingPrompt,
  buildSingleRegisterPrompt,
  RankedSynthesisSchema,
} from "../src/llm/prompts";

function createTextMockModel(text: string) {
  return new MockLanguageModelV4({
    doStream: async () => ({
      stream: simulateReadableStream({
        chunks: [
          { type: "text-start", id: "t1" },
          { type: "text-delta", id: "t1", delta: text },
          { type: "text-end", id: "t1" },
          {
            type: "finish",
            finishReason: { unified: "stop", raw: "stop" },
            usage: {
              inputTokens: { total: 500, noCache: 500, cacheRead: 0, cacheWrite: 0 },
              outputTokens: { total: 120, text: 100, reasoning: 20 },
            },
            providerMetadata: { gateway: { cost: "0.0125" } },
          },
        ],
      }),
    }),
  });
}

describe("Vercel AI SDK gateway and prompts", () => {
  test("extractJsonPayload handles fenced markdown JSON", () => {
    const raw = '```json\n{"literal":"In the name of God","simplified":"In God\'s name"}\n```';
    const parsed = extractJsonPayload<{ literal: string; simplified: string }>(raw);
    expect(parsed.literal).toBe("In the name of God");
    expect(parsed.simplified).toBe("In God's name");
  });

  test("buildSingleRegisterPrompt builds continuous whole-document prompt per register", () => {
    const lit = buildSingleRegisterPrompt({
      targetLanguage: resolveTargetLanguage("fr"),
      register: "literal",
      sectionTitle: "Full Document",
      arabicText: "اَلْحَمْدُللَّـهِ عَلی ما اَنْعَمَ",
      historicalCommentary: "شرح المجلسي في بحار الأنوار ج 29",
      wikiShiaExcerpts: ["[2] AR: اَلْحَمْدُللَّـهِ | EN: Praise be to Allah"],
      mtBaselines: [{ providerLabel: "Google v3", literal: "Louange à Dieu" }],
    });

    expect(lit.system).toContain("French (fr)");
    expect(lit.system).toContain("ONE CONTINUOUS WHOLE DOCUMENT");
    expect(lit.system).toContain("LITERAL");
    expect(lit.user).toContain("Google v3");
  });

  test("buildRegisterRankingPrompt anchors simplified synthesis to finalized literal", () => {
    const { system, user } = buildRegisterRankingPrompt({
      targetLanguage: resolveTargetLanguage("es"),
      register: "simplified",
      sectionTitle: "Full Document",
      arabicText: "بِسْمِ اللهِ",
      historicalCommentary: "بحار الأنوار",
      referenceFinalLiteral: "En el Nombre de Alá",
      candidates: [
        {
          providerId: "gemini",
          providerLabel: "Gemini 4 Carbon",
          kind: "llm",
          text: "En el nombre de Dios",
        },
      ],
    });
    expect(system).toContain("Spanish");
    expect(user).toContain("Finalized Literal Spanish Anchor");
    expect(user).toContain("En el Nombre de Alá");
  });

  test("callGatewayStreamText streams text and extracts token usage, reasoning tokens, and cost", async () => {
    const res = await callGatewayStreamText({
      model: "anthropic/claude-fable-5.2",
      modelResolver: () => createTextMockModel("In the Name of Allah"),
      system: "sys",
      user: "usr",
    });

    expect(res.data).toBe("In the Name of Allah");
    expect(res.usage.inputTokens).toBe(500);
    expect(res.usage.outputTokens).toBe(120);
    expect(res.usage.reasoningTokens).toBe(20);
    expect(res.usage.totalTokens).toBe(620);
    expect(res.usage.costUsd).toBe(0.0125);
  });

  test("callGatewayStreamStructured validates schema with Output.object and Zod", async () => {
    const payload = {
      rankings: [
        {
          providerId: "claude",
          rank: 1,
          score: 96,
          strengths: "Accurate",
          issues: "None",
        },
      ],
      synthesisNotes: "Synthesized cleanly.",
      finalTranslation: "# Final Markdown",
    };

    const res = await callGatewayStreamStructured({
      model: "anthropic/claude-fable-5.2",
      modelResolver: () => createTextMockModel(JSON.stringify(payload)),
      schema: RankedSynthesisSchema,
      system: "sys",
      user: "usr",
    });

    const checkType: z.infer<typeof RankedSynthesisSchema> = res.data;
    expect(checkType.rankings[0].providerId).toBe("claude");
    expect(checkType.finalTranslation).toBe("# Final Markdown");
  });
});

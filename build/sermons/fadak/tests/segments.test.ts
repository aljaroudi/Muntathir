import { describe, expect, test } from "bun:test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { MockLanguageModelV4, simulateReadableStream } from "ai/test";
import { alignTranslation } from "../src/align";
import { loadContextBundle } from "../src/context";
import { resolveTargetLanguage } from "../src/languages";
import { loadRows, saveRows } from "../src/rows";
import {
  buildSegments,
  markerOf,
  parseMarked,
  renderMarkdown,
  type Segment,
  toRows,
} from "../src/segments";

const seg = (n: number, text = `ar${n}`): Segment => ({
  id: `s00${n}`,
  sectionId: "02-sermon",
  kind: "text",
  prefix: "",
  arabic: text,
});

describe("segments", () => {
  test("real source: 175 WikiShia clauses + header/intro/aftermath lines, stable sequential IDs", async () => {
    const bundle = await loadContextBundle(path.resolve(import.meta.dir, "../data"));
    const segments = buildSegments(bundle.fullArabicText, bundle.alignedReference);
    expect(segments.length).toBe(206);
    expect(segments.map((s) => s.id).slice(0, 3)).toEqual(["s001", "s002", "s003"]);
    expect(segments.filter((s) => s.wikishiaIndex !== undefined).length).toBe(175);
    expect(new Set(segments.map((s) => s.sectionId))).toEqual(
      new Set(["00-header", "01-intro", "02-sermon", "03-grave-elegy", "04-abu-bakr-dialogue", "05-ali-dialogue"]),
    );
  });

  test("parseMarked accepts a complete answer and reports every kind of damage", () => {
    const segs = [seg(1), seg(2), seg(3)];
    const good = `${markerOf("s001")} A\n\n${markerOf("s002")} B\n${markerOf("s003")} C`;
    const ok = parseMarked(good, segs);
    expect(ok.ok).toBe(true);
    expect(ok.byId.get("s002")).toBe("B");

    const missing = parseMarked(`${markerOf("s001")} A\n${markerOf("s003")} C`, segs);
    expect(missing.problems.join()).toContain("missing 1: s002");
    const dup = parseMarked(`${good}\n${markerOf("s002")} again`, segs);
    expect(dup.problems.join()).toContain("duplicate marker s002");
    const swapped = parseMarked(`${markerOf("s002")} B\n${markerOf("s001")} A\n${markerOf("s003")} C`, segs);
    expect(swapped.problems).toContain("segments out of order");
    expect(parseMarked(`intro\n${good}`, segs).problems).toContain("text before the first marker");
  });

  test("renderMarkdown restores heading/note prefixes and strips stray Markdown from the model", () => {
    const segs: Segment[] = [{ ...seg(1), kind: "heading", prefix: "## " }, seg(2)];
    const md = renderMarkdown(segs, new Map([["s001", "## Title"], ["s002", "Body"]]));
    expect(md).toBe("## Title\n\nBody");
  });

  test("saveRows replaces rows of the same source+register and keeps the rest", async () => {
    const file = path.join(await fs.mkdtemp(path.join(os.tmpdir(), "rows-")), "translations.json");
    const segs = [seg(1), seg(2)];
    await saveRows(file, toRows(segs, new Map([["s001", "a"], ["s002", "b"]]), "ai", "literal"));
    await saveRows(file, toRows(segs, new Map([["s001", "x"], ["s002", "y"]]), "kagi", null));
    await saveRows(file, toRows(segs, new Map([["s001", "A"], ["s002", "B"]]), "ai", "literal"));
    const rows = await loadRows(file);
    expect(rows.length).toBe(4);
    expect(rows.find((r) => r.source === "ai" && r.segmentId === "s001")?.text).toBe("A");
  });
});

function mockModel(answers: string[]) {
  let call = 0;
  return () =>
    new MockLanguageModelV4({
      doStream: async () => ({
        stream: simulateReadableStream({
          chunks: [
            { type: "text-start", id: "t1" },
            { type: "text-delta", id: "t1", delta: answers[Math.min(call++, answers.length - 1)] },
            { type: "text-end", id: "t1" },
            {
              type: "finish",
              finishReason: { unified: "stop", raw: "stop" },
              usage: {
                inputTokens: { total: 10, noCache: 10, cacheRead: 0, cacheWrite: 0 },
                outputTokens: { total: 10, text: 10, reasoning: 0 },
              },
              providerMetadata: { gateway: { cost: "0.01" } },
            },
          ],
        }),
      }),
    });
}

describe("alignTranslation", () => {
  const segs = [seg(1), seg(2)];
  const translation = "Praise be to God. He is great.";
  const run = (answers: string[]) =>
    alignTranslation({
      segments: segs,
      translation,
      language: resolveTargetLanguage("en"),
      label: "test",
      warn: () => {},
      gateway: { model: "google/x" as never, modelResolver: mockModel(answers) },
    });

  test("accepts verbatim split", async () => {
    const { byId, result } = await run([`${markerOf("s001")} Praise be to God.\n${markerOf("s002")} He is great.`]);
    expect(byId.get("s001")).toBe("Praise be to God.");
    expect(result.attempts).toBe(1);
  });

  test("an answer that rewrites the text is rejected, then retried once (costs add up)", async () => {
    const { byId, result } = await run([
      `${markerOf("s001")} Glory to God.\n${markerOf("s002")} He is great.`,
      `${markerOf("s001")} Praise be to God.\n${markerOf("s002")} He is great.`,
    ]);
    expect(byId.get("s001")).toBe("Praise be to God.");
    expect(result.attempts).toBe(2);
    expect(result.usage.costUsd).toBeCloseTo(0.02, 5);
  });

  test("gives up if the retry is also invalid", async () => {
    await expect(run([`${markerOf("s001")} Glory to God.`])).rejects.toThrow("invalid output after retry");
  });
});

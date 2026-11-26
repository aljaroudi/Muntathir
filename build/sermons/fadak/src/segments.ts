import { extractFullArabicDocument, slugifySectionTitle } from "./context";
import type { AlignedSegment } from "./types";

/**
 * Canonical segmentation of the Arabic source. Every translation (AI, Kagi, human) is matched
 * to the original through `Segment.id`, used by both mobile readers.
 *
 * Segments are the 175 WikiShia aligned clauses for the sermon body, plus one segment per
 * remaining source line (title block, narration intro, post-sermon sections).
 */
export interface Segment {
  /** Stable, ordered ID (`s001`...). Only changes if the source file changes. */
  id: string;
  /** Section the segment belongs to (`00-header`, `01-intro`, `02-sermon`, ...). */
  sectionId: string;
  kind: "heading" | "note" | "text";
  /** Markdown prefix re-applied when rendering (`## `, `> `, or empty). */
  prefix: string;
  arabic: string;
  /** WikiShia segment number, when the segment comes from the WikiShia alignment. */
  wikishiaIndex?: number;
}

const DIACRITICS = /[\u064B-\u065F\u0670\u0640\u06D6-\u06ED]/g;

export function normalizeArabic(s: string): string {
  return s
    .replace(DIACRITICS, "")
    .replace(/[إأآٱ]/g, "ا")
    .replace(/ى/g, "ي")
    .replace(/[^\p{L}\p{N}]+/gu, "");
}

export function buildSegments(sourceMd: string, aligned: AlignedSegment[]): Segment[] {
  const segments: Segment[] = [];
  const wikiNorm = aligned.map((a) => normalizeArabic(a.arabic));
  let sectionCount = 0;
  let sectionId = "00-header";
  let wikiPos = 0;
  let consumed = 0;
  let group: string[] = [];

  const push = (kind: Segment["kind"], prefix: string, arabic: string, wikishiaIndex?: number) => {
    segments.push({
      id: `s${String(segments.length + 1).padStart(3, "0")}`,
      sectionId,
      kind,
      prefix,
      arabic,
      ...(wikishiaIndex !== undefined ? { wikishiaIndex } : {}),
    });
  };

  for (const raw of extractFullArabicDocument(sourceMd).split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || /^-{3,}$/.test(line)) continue;

    const heading = line.match(/^(#{1,6})\s+(.+)$/);
    if (heading) {
      const title = heading[2].trim();
      const level = heading[1].length;
      if (level >= 2 && level <= 3 && !title.startsWith("لسيدة نساء")) {
        sectionId = slugifySectionTitle(title, sectionCount++);
      }
      push("heading", `${heading[1]} `, title);
      continue;
    }

    const note = line.match(/^>\s?(.*)$/);
    if (note) {
      push("note", "> ", note[1].trim());
      continue;
    }

    // A line belongs to the current WikiShia segment when it continues it exactly.
    const n = normalizeArabic(line);
    if (wikiPos < aligned.length && n && wikiNorm[wikiPos].startsWith(n, consumed)) {
      group.push(line);
      consumed += n.length;
      if (consumed >= wikiNorm[wikiPos].length) {
        push("text", "", group.join(" "), aligned[wikiPos].index);
        wikiPos++;
        consumed = 0;
        group = [];
      }
      continue;
    }
    if (group.length > 0) {
      throw new Error(`Source line does not continue WikiShia segment ${aligned[wikiPos].index}`);
    }
    push("text", "", line);
  }

  if (wikiPos !== aligned.length) {
    throw new Error(
      `Only ${wikiPos}/${aligned.length} WikiShia segments matched the Arabic source in order`,
    );
  }
  return segments;
}

// --- Markers: how segment IDs travel through the LLM and back -----------------------------

export const markerOf = (id: string) => `⟦${id}⟧`;

/** Arabic text with a marker before each segment, as sent to the models. */
export function renderMarkedArabic(segments: Segment[]): string {
  return segments.map((s) => `${markerOf(s.id)} ${s.arabic}`).join("\n\n");
}

export interface MarkerCheck {
  ok: boolean;
  problems: string[];
  /** segment id -> translated text (only meaningful when ok). */
  byId: Map<string, string>;
}

const MARKER_RE = /⟦(s\d+)⟧/g;

/** Split a marked translation and verify every expected segment appears once, in order. */
export function parseMarked(text: string, segments: Segment[]): MarkerCheck {
  const problems: string[] = [];
  const found: Array<{ id: string; start: number; end: number }> = [];
  for (const m of text.matchAll(MARKER_RE)) {
    found.push({ id: m[1], start: m.index, end: m.index + m[0].length });
  }

  const expected = segments.map((s) => s.id);
  const expectedSet = new Set(expected);
  const seen = new Set<string>();
  const byId = new Map<string, string>();

  if (found.length > 0 && text.slice(0, found[0].start).trim()) {
    problems.push("text before the first marker");
  }
  found.forEach((f, i) => {
    const body = text.slice(f.end, found[i + 1]?.start ?? text.length).trim();
    if (!expectedSet.has(f.id)) problems.push(`unknown marker ${f.id}`);
    else if (seen.has(f.id)) problems.push(`duplicate marker ${f.id}`);
    else if (!body) problems.push(`empty segment ${f.id}`);
    seen.add(f.id);
    byId.set(f.id, body);
  });
  const missing = expected.filter((id) => !seen.has(id));
  if (missing.length) problems.push(`missing ${missing.length}: ${missing.slice(0, 8).join(", ")}${missing.length > 8 ? "…" : ""}`);

  const order = found.map((f) => f.id).filter((id) => expectedSet.has(id));
  const inOrder = [...new Set(order)];
  if (inOrder.some((id, i) => id !== expected.filter((e) => seen.has(e))[i])) {
    problems.push("segments out of order");
  }
  return { ok: problems.length === 0, problems, byId };
}

/** Remove any Markdown prefix a model may have added to a segment body. */
export function cleanSegmentText(text: string): string {
  return text.replace(/^(?:#{1,6}|>)\s+/, "").trim();
}

/** Translation as readable Markdown (markers removed, heading/note prefixes restored). */
export function renderMarkdown(segments: Segment[], byId: Map<string, string>): string {
  return segments
    .map((s) => `${s.prefix}${cleanSegmentText(byId.get(s.id) ?? "")}`)
    .join("\n\n");
}

/** One row per (segment, translation): the publication input for aligned editions. */
export interface TranslationRow {
  segmentId: string;
  /** `ai`, `kagi`, or `human:<label>`. */
  source: string;
  /** `literal` | `simplified` | null when the source has no register. */
  register: "literal" | "simplified" | null;
  text: string;
}

export function toRows(
  segments: Segment[],
  byId: Map<string, string>,
  source: string,
  register: TranslationRow["register"],
): TranslationRow[] {
  return segments.map((s) => ({
    segmentId: s.id,
    source,
    register,
    text: cleanSegmentText(byId.get(s.id) ?? ""),
  }));
}

import type { TargetLanguage } from "./languages";
import { callGatewayStreamText, type GatewayCallOptions, type GatewayDetailedResult } from "./llm/gateway";
import { callUntilMarked } from "./llm/marked";
import { markerOf, parseMarked, renderMarkedArabic, type Segment } from "./segments";

type GatewayBase = Omit<GatewayCallOptions, "system" | "user">;

const squash = (s: string) => s.replace(/\s+/g, "");
const stripMarkers = (s: string) => s.replace(/⟦s\d+⟧/g, "");

/**
 * Split an existing whole-document translation (AI output, Kagi, or a human file) into the
 * canonical segments. The model only inserts markers; the text must come back verbatim.
 */
export async function alignTranslation(
  opts: {
    segments: Segment[];
    translation: string;
    language: TargetLanguage;
    label: string;
    warn: (message: string) => void;
    gateway: GatewayBase;
  },
  fetchFn: typeof fetch = fetch,
): Promise<{ byId: Map<string, string>; result: GatewayDetailedResult<string> }> {
  const langLabel = `${opts.language.name} (${opts.language.code})`;
  const system = `You align an existing ${langLabel} translation of Khutbat al-Fadakiyyah to its Arabic original.
You do NOT translate or edit. Copy the ${langLabel} text VERBATIM, inserting a marker before the part that renders each Arabic segment.
- Every character of the translation must appear exactly once, in its original order. Do not fix, paraphrase, shorten, or reformat anything.
- Arabic segments are introduced by markers of the form ${markerOf("sNNN")}. Emit each marker exactly once, in order, followed by the matching part of the translation.
- Material that has no Arabic counterpart (introductions, notes, separators) stays attached to the nearest neighbouring segment.
Output ONLY the marked translation.`;

  const result = await callUntilMarked<string>({
    segments: opts.segments,
    label: opts.label,
    warn: opts.warn,
    text: (data) => data,
    extraCheck: (out) =>
      squash(stripMarkers(out)) === squash(opts.translation) ? [] : ["translation text was altered"],
    call: (repairNote) =>
      callGatewayStreamText(
        {
          ...opts.gateway,
          system,
          user: `## Arabic segments\n${renderMarkedArabic(opts.segments)}\n\n## ${langLabel} translation to split\n${opts.translation}${repairNote ? `\n\n## Correction needed\n${repairNote}` : ""}`,
        },
        fetchFn,
      ),
  });

  return { byId: parseMarked(result.data, opts.segments).byId, result };
}

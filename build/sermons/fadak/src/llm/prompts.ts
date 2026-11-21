import { z } from "zod";
import type { TargetLanguage } from "../languages";
import type { TranslationRegister } from "../types";

export const RankedCandidateSchema = z.object({
  providerId: z.string().describe("Candidate provider ID (e.g. google-v3, kagi, gemini, grok, claude, gpt)"),
  rank: z.number().int().describe("Rank from 1 (best) to N"),
  score: z.number().describe("Quality score from 0 to 100"),
  strengths: z.string().describe("Specific lexical, theological, and stylistic strengths"),
  issues: z.string().describe("Specific mistranslations, omissions, or register violations"),
});

export const RankedSynthesisSchema = z.object({
  rankings: z.array(RankedCandidateSchema),
  synthesisNotes: z
    .string()
    .describe("Editorial explanation of key lexical choices grounded in Bihar al-Anwar / Arabic"),
  finalTranslation: z
    .string()
    .describe(
      "Complete synthesized translation in the target language, with every ⟦sNNN⟧ marker of the Arabic input repeated once, in order",
    ),
});

export type RankedSynthesisOutput = z.infer<typeof RankedSynthesisSchema>;

/** Rules that make segment IDs survive the round trip through a model. */
export const MARKER_RULES = `The Arabic text is divided into numbered segments, each introduced by a marker of the form ⟦sNNN⟧ (NNN is the segment number).
- Output every marker exactly once, in the same order, each followed by the translation of THAT segment only.
- Never merge, split, skip, reorder, rename, or add segments, and never move words from one segment into another.
- Titles and notes are segments too: translate them as plain text, with no Markdown symbols (#, >, **).`;

export interface SingleRegisterPromptInput {
  targetLanguage: TargetLanguage;
  register: TranslationRegister;
  sectionTitle: string;
  arabicText: string;
  historicalCommentary: string;
  wikiShiaExcerpts: string[];
  targetLanguageReference?: string;
  mtBaselines: Array<{ providerLabel: string; literal: string }>;
  /** Set on a retry: why the previous answer was rejected. */
  repairNote?: string;
}

export function buildSingleRegisterPrompt(input: SingleRegisterPromptInput): {
  system: string;
  user: string;
} {
  const langLabel = `${input.targetLanguage.name} (${input.targetLanguage.code})`;

  const registerInstruction =
    input.register === "literal"
      ? `Produce a **LITERAL (${langLabel})** translation in the precision style of classical Quranic translations:
- Preserve every single Arabic word, clause, rhetorical parallelism, cognate accusative, pronoun chain, and theological nuance across the entire continuous text.
- Maintain consistent terminology from beginning to end.
- Use square brackets [like this] ONLY when ${input.targetLanguage.name} syntax strictly requires an implied word.
- Never add commentary into the body text, and never alter or soften historical claims.`
      : `Produce a **SIMPLIFIED (${langLabel})** translation written for a non-Muslim reader who has zero background in Islamic history or Arabic idioms:
- Keep the complete continuous narrative and sermon from start to finish without omitting any passage or softening any historical claim.
- Use clear, natural, dignified modern ${input.targetLanguage.name}.
- Briefly clarify unfamiliar historical/theological terms inline on first mention (such as Fadak, Emigrants/Muhajirun, Helpers/Ansar, People of the House) ONLY where needed for comprehension, without turning commentary into part of Lady Fatima's own words.`;

  const system = `You are a master scholar of classical Arabic, Shia Islamic theology, and Quranic translation, fluent at native literary level in ${langLabel}.
You are translating Khutbat al-Fadakiyyah (the Sermon of Fadak) by Lady Fatima al-Zahra (peace be upon her) from Arabic into ${langLabel} as ONE CONTINUOUS WHOLE DOCUMENT so that meaning, voice, pronoun references, and terminology remain seamless throughout.

Ground all lexical, theological, and historical meanings strictly in the original Arabic text and the provided Shia sources (Bihar al-Anwar vol. 29 by Allama Majlisi, al-Ihtijaj by al-Tabarsi, WikiShia).

${registerInstruction}

${MARKER_RULES}
Output ONLY the marked translation — no preamble, no meta-commentary, no code fences.`;

  const baselinesText =
    input.mtBaselines.length > 0
      ? input.mtBaselines.map((b) => `### ${b.providerLabel}\n${b.literal}`).join("\n\n---\n\n")
      : "(No machine translation baselines provided.)";

  const targetRefSection = input.targetLanguageReference
    ? `\n## 3b. Existing Authorized Shia ${input.targetLanguage.name} Reference (for terminology reinforcement only)\n${input.targetLanguageReference.slice(0, 12000)}\n`
    : "";

  const user = `## Target Language: ${langLabel}
## Register: ${input.register.toUpperCase()}
## Scope: ${input.sectionTitle}

## 1. Original Arabic Text (Translate Completely & Continuously)
${input.arabicText}

## 2. Shia Historical & Theological Context (Bihar al-Anwar / Allama Majlisi)
${input.historicalCommentary}

## 3. WikiShia Aligned Terminology Reference (175 Segments)
${input.wikiShiaExcerpts.join("\n")}
${targetRefSection}
## 4. Machine / Reference Baseline Translations in ${input.targetLanguage.name} (for lexical cross-check only — infer meaning from the Arabic & Shia commentary)
${baselinesText}

${input.repairNote ? `## Correction needed\n${input.repairNote}\n\n` : ""}Now write the complete ${input.register.toUpperCase()} ${langLabel} translation, one marker per segment:`;

  return { system, user };
}

export interface RegisterRankingPromptInput {
  targetLanguage: TargetLanguage;
  register: TranslationRegister;
  sectionTitle: string;
  arabicText: string;
  historicalCommentary: string;
  referenceFinalLiteral?: string;
  repairNote?: string;
  candidates: Array<{
    providerId: string;
    providerLabel: string;
    kind: string;
    text: string;
  }>;
}

export function buildRegisterRankingPrompt(input: RegisterRankingPromptInput): {
  system: string;
  user: string;
} {
  const langLabel = `${input.targetLanguage.name} (${input.targetLanguage.code})`;
  const registerDesc =
    input.register === "literal"
      ? `Quranic-style LITERAL ${input.targetLanguage.name} precision (word-by-word fidelity, exact clauses, consistent terminology across the entire text, grounded in Allama Majlisi's Bihar al-Anwar)`
      : `SIMPLIFIED ${input.targetLanguage.name} for non-Muslims (clear, accessible, self-explanatory without distorting or over-editorializing beyond the Arabic text and finalized literal anchor)`;

  const system = `You are Claude Fable 5.2 acting as lead editor and Shia Arabic-to-${input.targetLanguage.name} translation judge.
Evaluate every candidate ${input.register.toUpperCase()} translation against the complete original Arabic of Khutbat al-Fadakiyyah and Allama Majlisi's commentary in Bihar al-Anwar.
Target standard: ${registerDesc}.

Rank all candidates from 1 (best) to N, score each 0-100, document specific strengths and errors in synthesisNotes, and produce the complete synthesized ${input.register.toUpperCase()} translation in finalTranslation.

${MARKER_RULES}
Candidates that came from machine translation carry no markers: use them only as a cross-check and still emit one marker per Arabic segment in finalTranslation.`;

  const candidateBlock = input.candidates
    .map((c) => `### Candidate: ${c.providerId} (${c.providerLabel}, ${c.kind})\n${c.text}`)
    .join("\n\n========================================\n\n");

  const anchorSection = input.referenceFinalLiteral
    ? `\n## Finalized Literal ${input.targetLanguage.name} Anchor (ensure Simplified never contradicts this meaning)\n${input.referenceFinalLiteral}\n`
    : "";

  const user = `## Target Language: ${langLabel}
## Register Being Ranked & Synthesized: ${input.register.toUpperCase()}
## Scope: ${input.sectionTitle}

## Original Arabic Text
${input.arabicText}

## Shia Context & Commentary (Bihar al-Anwar / Allama Majlisi)
${input.historicalCommentary}
${anchorSection}
## Candidate ${input.register.toUpperCase()} Translations
${candidateBlock}${input.repairNote ? `\n\n## Correction needed\n${input.repairNote}` : ""}`;

  return { system, user };
}

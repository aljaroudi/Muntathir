import fs from "node:fs/promises";
import path from "node:path";
import {
  type CachedRankCall,
  readRankCache,
  readTextCache,
  writeRankCache,
  writeTextCache,
} from "./cache";
import { loadContextBundle } from "./context";
import type { TargetLanguage } from "./languages";
import { callGatewayStreamStructured, callGatewayStreamText } from "./llm/gateway";
import { callUntilMarked } from "./llm/marked";
import {
  buildRegisterRankingPrompt,
  buildSingleRegisterPrompt,
  RankedSynthesisSchema,
  type RankedSynthesisOutput,
} from "./llm/prompts";
import {
  buildRunMetricsReport,
  formatDuration,
  formatNum,
  formatProgress,
  PipelineLogger,
  summarizeStep,
} from "./logger";
import { translateWithGoogleV3Detailed } from "./mt/google";
import { buildSlots, loadHistory, ProgressTracker, slotKey } from "./progress";
import { saveRows } from "./rows";
import {
  buildSegments,
  markerOf,
  parseMarked,
  renderMarkdown,
  renderMarkedArabic,
  type Segment,
  toRows,
} from "./segments";
import type {
  CallMetrics,
  CandidateTranslation,
  PipelineConfig,
  RunMetricsReport,
  SectionMetrics,
  SectionSynthesis,
  SourceSection,
  TranslationRegister,
} from "./types";

const REGISTERS: TranslationRegister[] = ["literal", "simplified"];
const GOOGLE_LABEL = "Google Cloud Translation v3";
const KAGI_LABEL = "Kagi Translate (Manual File)";
const RANK_LABEL = "Claude Fable 5.2 (Rank & Synthesize)";

export async function runPipeline(
  config: PipelineConfig,
  fetchFn: typeof fetch = fetch,
): Promise<SectionSynthesis[]> {
  const runStartPerf = performance.now();
  const runStartedAt = new Date().toISOString();
  const lang = config.targetLanguage;
  const dryRun = config.dryRun;
  const useCache = !dryRun;

  const langOutputDir = path.join(config.outputDir, lang.code);
  const cacheDir = path.join(langOutputDir, "cache");
  await fs.mkdir(langOutputDir, { recursive: true });

  // Step 1: context
  const step1Start = performance.now();
  const bundle = await loadContextBundle(config.dataDir, lang);
  const step1DurationMs = Math.round(performance.now() - step1Start);

  const section: SourceSection | undefined = config.onlySection
    ? bundle.sections.find((s) => s.id === config.onlySection)
    : {
        id: "full-document",
        title: "الخطبة الفدكية - النص الكامل المتصل",
        arabicText: bundle.fullArabicText,
      };
  if (!section) {
    throw new Error(`No matching section found (onlySection=${config.onlySection})`);
  }

  const allSegments = buildSegments(bundle.fullArabicText, bundle.alignedReference);
  const segments = config.onlySection
    ? allSegments.filter((seg) => seg.sectionId === config.onlySection)
    : allSegments;
  if (segments.length === 0) {
    throw new Error(`No segments for section ${config.onlySection}`);
  }
  const markedArabic = renderMarkedArabic(segments);
  const dryRunMarked = (label: string) =>
    segments.map((seg) => `${markerOf(seg.id)} [${label}] ${seg.id}`).join("\n\n");
  // Cache files from before segment markers (no `.seg`) hold unmarked text and stay untouched.
  const scope = `${section.id}.seg`;

  const logger = new PipelineLogger(
    path.join(langOutputDir, "translation.log"),
    config.quiet ?? false,
  );
  await logger.init({
    targetLanguage: `${lang.name} (${lang.code})`,
    dryRun,
    modeLabel: config.onlySection ? `section=${config.onlySection}` : "full document",
  });

  // The manual Kagi file only covers the whole document.
  const kagi = config.onlySection ? undefined : bundle.kagiManualTranslation;
  const arabicChars = section.arabicText.length;
  const wikiShiaExcerpts = bundle.alignedReference.map(
    (seg) => `[${seg.index}] AR: ${seg.arabic} | EN: ${seg.english}`,
  );
  logger.info(
    `${segments.length} segments | ${formatNum(arabicChars)} AR chars | commentary ${formatNum(bundle.historicalCommentary.length)} | wikishia refs ${bundle.alignedReference.length}${bundle.targetLanguageReference ? " | reference translation loaded" : ""} | kagi: ${kagi ? path.basename(kagi.filePath) : "none"}`,
  );

  if (!dryRun && !config.aiGatewayApiKey && !config.modelResolver) {
    throw new Error("AI_GATEWAY_API_KEY is required when not running in --dry-run mode");
  }

  const modelEntries = [
    { id: "gemini", label: "Gemini 4 Carbon", model: config.models.gemini },
    { id: "grok", label: "Grok 4.7", model: config.models.grok },
    { id: "claude", label: "Claude Fable 5.2", model: config.models.claude },
    { id: "gpt", label: "GPT 6 Astra 6.2", model: config.models.gpt },
  ];

  // Live money/time projection: cache hits are done; the rest is estimated from other languages' runs.
  const slots = buildSlots(scope, modelEntries.map((m) => m.id));
  const progress = new ProgressTracker(
    slots,
    dryRun ? new Map() : await loadHistory(config.outputDir, [scope, section.id]),
  );
  if (useCache) {
    const cachedCount = await progress.markCached(cacheDir);
    logger.info(`LLM calls cached ${cachedCount}/${slots.length} | ${formatProgress(progress.snapshot())}`);
  }

  try {
    const secStartPerf = performance.now();
    const candidates: CandidateTranslation[] = [];
    const step2Calls: CallMetrics[] = [];
    const step3Calls: CallMetrics[] = [];
    const step4Calls: CallMetrics[] = [];

    // Step 2: MT baselines — Google (API, cached) + the hand-supplied Kagi file
    const step2Start = performance.now();
    const addMt = (providerId: string, providerLabel: string, literal: string, call: CallMetrics) => {
      step2Calls.push(call);
      candidates.push({ providerId, providerLabel, kind: "mt", literal, metrics: call });
    };
    const mtCall = (providerId: string, providerLabel: string): CallMetrics => ({
      step: "step2-mt",
      sectionId: section.id,
      providerId,
      providerLabel,
      durationMs: 0,
      inputTokens: null,
      outputTokens: null,
      totalTokens: null,
      costUsd: null,
      inputChars: arabicChars,
      outputChars: 0,
    });

    if (config.skipMt) {
      logger.info("MT baselines skipped (--skip-mt)");
    } else {
      const googleFile = path.join(cacheDir, `${section.id}__step2-google.json`);
      const cachedGoogle = useCache ? await readTextCache(googleFile) : null;
      if (cachedGoogle) {
        addMt("google-v3", GOOGLE_LABEL, cachedGoogle.text, {
          ...cachedGoogle.metrics,
          cached: true,
          durationMs: 0,
        });
      } else if (dryRun) {
        const text = `[DRY RUN Google v3 -> ${lang.code}] ${section.arabicText.slice(0, 80)}...`;
        addMt("google-v3", GOOGLE_LABEL, text, {
          ...mtCall("google-v3", GOOGLE_LABEL),
          outputChars: text.length,
        });
      } else if (config.googleProjectId && config.googleAccessToken) {
        const res = await translateWithGoogleV3Detailed(
          section.arabicText,
          {
            projectId: config.googleProjectId,
            location: config.googleLocation,
            accessToken: config.googleAccessToken,
            targetLanguageCode: lang.googleCode,
          },
          fetchFn,
        );
        const call: CallMetrics = {
          ...mtCall("google-v3", GOOGLE_LABEL),
          durationMs: res.durationMs,
          inputTokens: res.inputTokens,
          outputTokens: res.outputTokens,
          totalTokens: res.totalTokens,
          inputChars: res.inputChars,
          outputChars: res.outputChars,
        };
        await writeTextCache(googleFile, { text: res.text, metrics: call });
        addMt("google-v3", GOOGLE_LABEL, res.text, call);
        logger.call(call);
      } else {
        logger.warn("Skipping Google Translate v3 (missing project/token)");
      }

      if (kagi) {
        addMt("kagi", KAGI_LABEL, kagi.text, {
          ...mtCall("kagi", KAGI_LABEL),
          outputChars: kagi.text.length,
          sourceFile: kagi.filePath,
        });
      } else if (!config.onlySection) {
        logger.warn(`No data/kagi/${lang.code.toLowerCase()}-kagi.md - continuing without a Kagi baseline`);
      }
    }
    const step2Summary = summarizeStep("step2-mt", performance.now() - step2Start, step2Calls);

    // Step 3: 4 frontier LLMs, literal batch then simplified batch (each batch runs in parallel)
    const step3Start = performance.now();
    const mtBaselines = candidates
      .filter((c) => c.kind === "mt")
      .map((c) => ({ providerLabel: c.providerLabel, literal: c.literal }));
    const timeoutMs = config.requestTimeoutMs ?? 1_800_000;

    const runRegisterBatch = async (
      register: TranslationRegister,
    ): Promise<Record<string, string>> => {
      const promptFor = (repairNote?: string) =>
        buildSingleRegisterPrompt({
          targetLanguage: lang,
          register,
          sectionTitle: section.title,
          arabicText: markedArabic,
          historicalCommentary: bundle.historicalCommentary,
          wikiShiaExcerpts,
          targetLanguageReference: bundle.targetLanguageReference,
          mtBaselines,
          repairNote,
        });

      const entries = await Promise.all(
        modelEntries.map(async (m) => {
          const cacheFile = path.join(cacheDir, `${scope}__step3-${m.id}-${register}.json`);
          const cached = useCache ? await readTextCache(cacheFile) : null;
          if (cached) {
            step3Calls.push({ ...cached.metrics, cached: true, durationMs: 0 });
            return [m.id, cached.text] as const;
          }
          if (dryRun) {
            step3Calls.push({
              step: "step3-llm",
              sectionId: section.id,
              providerId: m.id,
              providerLabel: m.label,
              register,
              model: m.model,
              durationMs: 0,
              inputTokens: 0,
              outputTokens: 0,
              totalTokens: 0,
              inputChars: arabicChars,
              outputChars: 0,
              attempts: 1,
            });
            return [m.id, dryRunMarked(`DRY RUN ${m.label} ${register} (${lang.code})`)] as const;
          }

          const res = await callUntilMarked<string>({
            segments,
            label: `${m.label} ${register}`,
            warn: (msg) => logger.warn(msg),
            text: (data) => data,
            call: (repairNote) => {
              const prompt = promptFor(repairNote);
              return callGatewayStreamText(
                {
                  baseUrl: config.aiGatewayBaseUrl,
                  apiKey: config.aiGatewayApiKey,
                  model: m.model,
                  modelResolver: config.modelResolver,
                  system: prompt.system,
                  user: prompt.user,
                  timeoutMs,
                  onRetry: (attempt, err) =>
                    logger.warn(`${m.label} ${register} retry #${attempt}: ${err.message}`),
                },
                fetchFn,
              );
            },
          });

          const call: CallMetrics = {
            step: "step3-llm",
            sectionId: section.id,
            providerId: m.id,
            providerLabel: m.label,
            register,
            model: m.model,
            durationMs: res.durationMs,
            inputTokens: res.usage.inputTokens,
            outputTokens: res.usage.outputTokens,
            reasoningTokens: res.usage.reasoningTokens,
            totalTokens: res.usage.totalTokens,
            costUsd: res.usage.costUsd,
            inputChars: res.inputChars,
            outputChars: res.outputChars,
            attempts: res.attempts,
          };
          await writeTextCache(cacheFile, { text: res.data, metrics: call });
          step3Calls.push(call);
          progress.complete(slotKey("step3-llm", m.id, register), {
            costUsd: call.costUsd ?? 0,
            durationMs: call.durationMs,
            cached: false,
          });
          logger.call(call, progress.snapshot());
          return [m.id, res.data] as const;
        }),
      );
      return Object.fromEntries(entries);
    };

    const literalByModel = await runRegisterBatch("literal");
    const simplifiedByModel = await runRegisterBatch("simplified");
    for (const m of modelEntries) {
      candidates.push({
        providerId: m.id,
        providerLabel: m.label,
        kind: "llm",
        literal: literalByModel[m.id],
        simplified: simplifiedByModel[m.id],
      });
    }
    const step3Summary = summarizeStep("step3-llm", performance.now() - step3Start, step3Calls);

    // Step 4: rank + synthesize (literal first, then simplified anchored to the final literal)
    const step4Start = performance.now();
    const runRankStep = async (
      register: TranslationRegister,
      regCandidates: Array<{ providerId: string; providerLabel: string; kind: string; text: string }>,
      referenceFinalLiteral?: string,
    ): Promise<CachedRankCall> => {
      const cacheFile = path.join(cacheDir, `${scope}__step4-rank-${register}.json`);
      const cached = useCache ? await readRankCache(cacheFile) : null;
      if (cached) {
        step4Calls.push({ ...cached.metrics, cached: true, durationMs: 0 });
        return cached;
      }

      const baseCall: CallMetrics = {
        step: "step4-rank",
        sectionId: section.id,
        providerId: "claude-rank",
        providerLabel: RANK_LABEL,
        register,
        model: config.models.claude,
        durationMs: 0,
        inputTokens: 0,
        outputTokens: 0,
        totalTokens: 0,
        inputChars: arabicChars,
        outputChars: 0,
        attempts: 1,
      };

      if (dryRun) {
        const label = register === "literal" ? "Literal" : "Simplified";
        step4Calls.push(baseCall);
        return {
          rankings: regCandidates.map((c, i) => ({
            providerId: c.providerId,
            rank: i + 1,
            score: 95 - i * 3,
            strengths: `Dry run ${register} placeholder`,
            issues: "None",
          })),
          synthesisNotes: `Dry run ${register} synthesis completed.`,
          finalTranslation: dryRunMarked(`DRY RUN Final ${label} (${lang.code})`),
          metrics: baseCall,
        };
      }

      const res = await callUntilMarked<RankedSynthesisOutput>({
        segments,
        label: `rank ${register}`,
        warn: (msg) => logger.warn(msg),
        text: (data) => data.finalTranslation,
        call: (repairNote) => {
          const rankPrompt = buildRegisterRankingPrompt({
            targetLanguage: lang,
            register,
            sectionTitle: section.title,
            arabicText: markedArabic,
            historicalCommentary: bundle.historicalCommentary,
            referenceFinalLiteral,
            repairNote,
            candidates: regCandidates,
          });
          return callGatewayStreamStructured(
            {
              baseUrl: config.aiGatewayBaseUrl,
              apiKey: config.aiGatewayApiKey,
              model: config.models.claude,
              modelResolver: config.modelResolver,
              system: rankPrompt.system,
              user: rankPrompt.user,
              schema: RankedSynthesisSchema,
              timeoutMs,
              onRetry: (attempt, err) =>
                logger.warn(`rank ${register} retry #${attempt}: ${err.message}`),
            },
            fetchFn,
          );
        },
      });

      const call: CallMetrics = {
        ...baseCall,
        durationMs: res.durationMs,
        inputTokens: res.usage.inputTokens,
        outputTokens: res.usage.outputTokens,
        reasoningTokens: res.usage.reasoningTokens,
        totalTokens: res.usage.totalTokens,
        costUsd: res.usage.costUsd,
        inputChars: res.inputChars,
        outputChars: res.outputChars,
        attempts: res.attempts,
      };
      const out: CachedRankCall = {
        rankings: res.data.rankings,
        synthesisNotes: res.data.synthesisNotes,
        finalTranslation: res.data.finalTranslation,
        metrics: call,
      };
      await writeRankCache(cacheFile, out);
      step4Calls.push(call);
      progress.complete(slotKey("step4-rank", "claude-rank", register), {
        costUsd: call.costUsd ?? 0,
        durationMs: call.durationMs,
        cached: false,
      });
      logger.call(call, progress.snapshot());
      return out;
    };

    const literalRank = await runRankStep(
      "literal",
      candidates.map((c) => ({
        providerId: c.providerId,
        providerLabel: c.providerLabel,
        kind: c.kind,
        text: c.literal,
      })),
    );
    const simplifiedRank = await runRankStep(
      "simplified",
      candidates
        .filter((c) => Boolean(c.simplified))
        .map((c) => ({
          providerId: c.providerId,
          providerLabel: c.providerLabel,
          kind: c.kind,
          text: c.simplified!,
        })),
      literalRank.finalTranslation,
    );
    const step4Summary = summarizeStep("step4-rank", performance.now() - step4Start, step4Calls);

    const allCalls = [...step2Calls, ...step3Calls, ...step4Calls];
    const secMetrics: SectionMetrics = {
      sectionId: section.id,
      sectionTitle: section.title,
      cached: allCalls.length > 0 && allCalls.every((c) => Boolean(c.cached || c.sourceFile)),
      wallDurationMs: Math.round(performance.now() - secStartPerf),
      steps: { step2Mt: step2Summary, step3Llm: step3Summary, step4Rank: step4Summary },
      calls: allCalls,
      totalInputTokens:
        step2Summary.inputTokens + step3Summary.inputTokens + step4Summary.inputTokens,
      totalOutputTokens:
        step2Summary.outputTokens + step3Summary.outputTokens + step4Summary.outputTokens,
      totalTokens: step2Summary.totalTokens + step3Summary.totalTokens + step4Summary.totalTokens,
      totalCostUsd: step2Summary.costUsd + step3Summary.costUsd + step4Summary.costUsd,
    };

    const literalChecked = parseMarked(literalRank.finalTranslation, segments);
    const simplifiedChecked = parseMarked(simplifiedRank.finalTranslation, segments);
    if (!literalChecked.ok || !simplifiedChecked.ok) {
      throw new Error(
        `Final translation lost segment markers: ${[...literalChecked.problems, ...simplifiedChecked.problems].join("; ")}`,
      );
    }
    const finalLiteral = renderMarkdown(segments, literalChecked.byId);
    const finalSimplified = renderMarkdown(segments, simplifiedChecked.byId);

    const results: SectionSynthesis[] = [
      {
        sectionId: section.id,
        sectionTitle: section.title,
        targetLanguage: lang.code,
        arabicText: section.arabicText,
        candidates,
        literalRankings: literalRank.rankings,
        simplifiedRankings: simplifiedRank.rankings,
        rankings: literalRank.rankings,
        finalLiteral,
        finalSimplified,
        literalSynthesisNotes: literalRank.synthesisNotes,
        simplifiedSynthesisNotes: simplifiedRank.synthesisNotes,
        synthesisNotes: `Literal:\n${literalRank.synthesisNotes}\n\nSimplified:\n${simplifiedRank.synthesisNotes}`,
        metrics: secMetrics,
      },
    ];

    const metricsReport = buildRunMetricsReport({
      runStartedAt,
      runFinishedAt: new Date().toISOString(),
      targetLanguage: `${lang.name} (${lang.code})`,
      dryRun,
      totalWallDurationMs: performance.now() - runStartPerf,
      step1Context: {
        durationMs: step1DurationMs,
        sectionCount: 1,
        alignedSegmentCount: bundle.alignedReference.length,
        arabicChars,
        commentaryChars: bundle.historicalCommentary.length,
        kagiManualFile: kagi?.filePath,
      },
      sections: [secMetrics],
    });

    await logger.summary(metricsReport);
    await logger.flush();
    await writeOutputs(langOutputDir, lang, results, metricsReport);
    await saveRows(path.join(langOutputDir, "translations.json"), [
      ...toRows(segments, literalChecked.byId, "ai", "literal"),
      ...toRows(segments, simplifiedChecked.byId, "ai", "simplified"),
    ]);
    return results;
  } catch (err) {
    logger.error(`Pipeline aborted: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}`);
    await logger.flush();
    throw err;
  }
}

async function writeOutputs(
  langOutputDir: string,
  lang: TargetLanguage,
  results: SectionSynthesis[],
  metricsReport: RunMetricsReport,
): Promise<void> {
  const isSingleFullDoc = results.length === 1 && results[0].sectionId === "full-document";

  const literalMd = isSingleFullDoc
    ? results[0].finalLiteral + "\n"
    : [
        `# Khutbat al-Fadakiyyah — Literal ${lang.name} (${lang.code}) Translation`,
        "",
        ...results.flatMap((r) => [`## ${r.sectionTitle} (${r.sectionId})`, "", r.finalLiteral, ""]),
      ].join("\n");

  const simplifiedMd = isSingleFullDoc
    ? results[0].finalSimplified + "\n"
    : [
        `# The Sermon of Fadak — Simplified ${lang.name} (${lang.code}) Translation`,
        "",
        ...results.flatMap((r) => [
          `## ${r.sectionTitle} (${r.sectionId})`,
          "",
          r.finalSimplified,
          "",
        ]),
      ].join("\n");

  const stepRows = Object.values(metricsReport.totalsByStep).map(
    (s) =>
      `| ${s.step} | ${formatDuration(s.wallDurationMs)} | ${formatDuration(s.sumCallDurationMs)} | ${s.callCount} | ${formatNum(s.inputTokens)} | ${formatNum(s.outputTokens)} | ${formatNum(s.totalTokens)} | $${s.costUsd.toFixed(4)} |`,
  );

  const providerRows = Object.entries(metricsReport.totalsByProvider).map(
    ([id, p]) =>
      `| ${id} (${p.providerLabel}) | ${p.callCount} | ${formatDuration(p.totalDurationMs)} | ${formatDuration(p.avgDurationMs)} | ${formatNum(p.inputTokens)} | ${formatNum(p.outputTokens)} | ${formatNum(p.totalTokens)} | $${p.costUsd.toFixed(4)} |`,
  );

  const rankingsMd = [
    `# Translation Rankings, Synthesis & Metrics — ${lang.name} (${lang.code})`,
    "",
    "## Timing, Token & Cost Summary",
    "",
    `- **Total Wall Time:** ${formatDuration(metricsReport.grandTotals.wallDurationMs)}`,
    `- **Total Tokens:** in=${formatNum(metricsReport.grandTotals.inputTokens)}, out=${formatNum(metricsReport.grandTotals.outputTokens)} (reasoning=${formatNum(metricsReport.grandTotals.reasoningTokens)}), total=${formatNum(metricsReport.grandTotals.totalTokens)}`,
    `- **Total Gateway Cost:** $${metricsReport.grandTotals.costUsd.toFixed(4)}`,
    ...(metricsReport.step1Context.kagiManualFile
      ? [`- **Manual Kagi Baseline:** \`${metricsReport.step1Context.kagiManualFile}\``]
      : []),
    "",
    "### By Step",
    "| Step | Wall Time | Summed Time | Calls | Input Tokens | Output Tokens | Total Tokens | Cost |",
    "|---|---|---|---|---|---|---|---|",
    ...stepRows,
    "",
    "### By Provider / Model",
    "| Provider | Calls | Total Time | Avg Time | Input Tokens | Output Tokens | Total Tokens | Cost |",
    "|---|---|---|---|---|---|---|---|",
    ...providerRows,
    "",
    "---",
    "",
    ...results.flatMap((r) => [
      `## ${r.sectionTitle} (${r.sectionId})`,
      "",
      "### Literal Rankings",
      "| Rank | Provider | Score | Strengths | Issues |",
      "|---|---|---|---|---|",
      ...r.literalRankings.map(
        (rk) => `| ${rk.rank} | ${rk.providerId} | ${rk.score} | ${rk.strengths} | ${rk.issues} |`,
      ),
      "",
      `**Literal Synthesis Notes:** ${r.literalSynthesisNotes}`,
      "",
      "### Simplified Rankings",
      "| Rank | Provider | Score | Strengths | Issues |",
      "|---|---|---|---|---|",
      ...r.simplifiedRankings.map(
        (rk) => `| ${rk.rank} | ${rk.providerId} | ${rk.score} | ${rk.strengths} | ${rk.issues} |`,
      ),
      "",
      `**Simplified Synthesis Notes:** ${r.simplifiedSynthesisNotes}`,
      "",
    ]),
  ].join("\n");

  await Promise.all([
    fs.writeFile(path.join(langOutputDir, "literal.md"), literalMd, "utf8"),
    fs.writeFile(path.join(langOutputDir, "simplified.md"), simplifiedMd, "utf8"),
    fs.writeFile(path.join(langOutputDir, "rankings.md"), rankingsMd, "utf8"),
    fs.writeFile(path.join(langOutputDir, "report.json"), JSON.stringify(results, null, 2), "utf8"),
    fs.writeFile(
      path.join(langOutputDir, "metrics.json"),
      JSON.stringify(metricsReport, null, 2),
      "utf8",
    ),
  ]);
}

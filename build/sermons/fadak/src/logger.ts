import fs from "node:fs/promises";
import path from "node:path";
import type { ProgressSnapshot } from "./progress";
import type {
  CallMetrics,
  ProviderAggregateMetrics,
  RunMetricsReport,
  SectionMetrics,
  StepMetrics,
  TranslationStepId,
} from "./types";

export function formatDuration(ms: number): string {
  if (ms < 1000) return `${Math.round(ms)}ms`;
  const secs = ms / 1000;
  if (secs < 60) return `${secs.toFixed(1)}s`;
  const mins = Math.floor(secs / 60);
  return `${mins}m ${Math.round(secs % 60)}s`;
}

export function formatNum(n: number | null | undefined): string {
  if (n === null || n === undefined) return "N/A";
  return n.toLocaleString("en-US");
}

const usd = (n: number) => `$${n.toFixed(2)}`;

/** `spent $1.87 (+$6.22 cached) | left ~$5.63 | elapsed 4m 54s | eta ~9m 12s` */
export function formatProgress(s: ProgressSnapshot): string {
  const spent = `spent ${usd(s.spentUsd)}${s.cachedUsd > 0 ? ` (+${usd(s.cachedUsd)} cached)` : ""}`;
  const left =
    s.pendingSlots === 0
      ? "$0"
      : s.unknownSlots === s.pendingSlots
        ? "?"
        : `~${usd(s.leftUsd)}${s.unknownSlots > 0 ? "+" : ""}`;
  const eta = s.etaMs === null ? "?" : s.etaMs === 0 ? "0s" : `~${formatDuration(s.etaMs)}`;
  return `${spent} | left ${left} | elapsed ${formatDuration(s.elapsedMs)} | eta ${eta}`;
}

function callLabel(call: CallMetrics): string {
  if (call.step === "step4-rank") return `rank ${call.register ?? ""}`.trim();
  if (call.step === "step3-llm") return `${call.providerId} ${call.register ?? ""}`.trim();
  return call.providerId;
}

export class PipelineLogger {
  private startPerf = performance.now();
  private writeQueue: Promise<void> = Promise.resolve();

  constructor(
    private readonly logFilePath: string,
    private readonly quiet = false,
  ) {}

  private append(text: string): void {
    this.writeQueue = this.writeQueue.then(() => fs.appendFile(this.logFilePath, text, "utf8"));
  }

  async init(header: { targetLanguage: string; dryRun: boolean; modeLabel: string }): Promise<void> {
    await fs.mkdir(path.dirname(this.logFilePath), { recursive: true });
    this.info(
      `== ${header.targetLanguage} | ${header.dryRun ? "DRY-RUN" : "LIVE"} | ${header.modeLabel} ==`,
    );
  }

  info(message: string): void {
    const elapsed = formatDuration(performance.now() - this.startPerf);
    this.append(`${new Date().toISOString()} ${message}\n`);
    if (!this.quiet) console.log(`[${elapsed.padStart(7)}] ${message}`);
  }

  warn(message: string): void {
    this.info(`WARN ${message}`);
  }

  error(message: string): void {
    this.info(`ERROR ${message}`);
  }

  /** One line per finished call, followed by the live money/time projection. */
  call(call: CallMetrics, progress?: ProgressSnapshot): void {
    const tokens =
      call.inputTokens !== null || call.outputTokens !== null
        ? ` in=${formatNum(call.inputTokens)} out=${formatNum(call.outputTokens)}`
        : "";
    const cost = typeof call.costUsd === "number" ? ` $${call.costUsd.toFixed(4)}` : "";
    const retries = call.attempts && call.attempts > 1 ? ` (attempts=${call.attempts})` : "";
    const tail = progress ? `  | ${formatProgress(progress)}` : "";
    this.info(
      `${callLabel(call)} done in ${formatDuration(call.durationMs)}${cost}${tokens}${retries}${tail}`,
    );
  }

  async summary(report: RunMetricsReport): Promise<void> {
    const calls = report.sections.flatMap((s) => s.calls);
    const live = calls.filter((c) => !c.cached).reduce((sum, c) => sum + (c.costUsd ?? 0), 0);
    const total = report.grandTotals.costUsd;
    const g = report.grandTotals;
    this.info(
      `Done in ${formatDuration(g.wallDurationMs)} | cost $${total.toFixed(4)} (this run $${live.toFixed(4)}, cached $${(total - live).toFixed(4)}) | ${calls.length} calls`,
    );
    this.info(
      `Tokens in=${formatNum(g.inputTokens)} out=${formatNum(g.outputTokens)} (reasoning=${formatNum(g.reasoningTokens)}) total=${formatNum(g.totalTokens)}`,
    );
  }

  async flush(): Promise<void> {
    await this.writeQueue;
  }
}

export function summarizeStep(
  step: TranslationStepId,
  wallDurationMs: number,
  calls: CallMetrics[],
): StepMetrics {
  let sumCallDurationMs = 0;
  let inputTokens = 0;
  let outputTokens = 0;
  let reasoningTokens = 0;
  let totalTokens = 0;
  let costUsd = 0;
  let inputChars = 0;
  let outputChars = 0;

  for (const c of calls) {
    sumCallDurationMs += c.durationMs;
    inputTokens += c.inputTokens ?? 0;
    outputTokens += c.outputTokens ?? 0;
    reasoningTokens += c.reasoningTokens ?? 0;
    totalTokens += c.totalTokens ?? (c.inputTokens ?? 0) + (c.outputTokens ?? 0);
    costUsd += c.costUsd ?? 0;
    inputChars += c.inputChars;
    outputChars += c.outputChars;
  }

  return {
    step,
    wallDurationMs: Math.round(wallDurationMs),
    sumCallDurationMs: Math.round(sumCallDurationMs),
    callCount: calls.length,
    inputTokens,
    outputTokens,
    reasoningTokens,
    totalTokens,
    costUsd,
    inputChars,
    outputChars,
  };
}

export function buildRunMetricsReport(params: {
  runStartedAt: string;
  runFinishedAt: string;
  targetLanguage: string;
  dryRun: boolean;
  totalWallDurationMs: number;
  step1Context: RunMetricsReport["step1Context"];
  sections: SectionMetrics[];
}): RunMetricsReport {
  const emptyStep = (step: TranslationStepId): StepMetrics => ({
    step,
    wallDurationMs: 0,
    sumCallDurationMs: 0,
    callCount: 0,
    inputTokens: 0,
    outputTokens: 0,
    reasoningTokens: 0,
    totalTokens: 0,
    costUsd: 0,
    inputChars: 0,
    outputChars: 0,
  });

  const totalsByStep: Record<TranslationStepId, StepMetrics> = {
    "step1-context": {
      ...emptyStep("step1-context"),
      wallDurationMs: params.step1Context.durationMs,
      sumCallDurationMs: params.step1Context.durationMs,
      callCount: 1,
      inputChars: params.step1Context.arabicChars + params.step1Context.commentaryChars,
    },
    "step2-mt": emptyStep("step2-mt"),
    "step3-llm": emptyStep("step3-llm"),
    "step4-rank": emptyStep("step4-rank"),
  };

  const totalsByProvider: Record<string, ProviderAggregateMetrics> = {};

  const addStep = (acc: StepMetrics, cur: StepMetrics) => {
    acc.wallDurationMs += cur.wallDurationMs;
    acc.sumCallDurationMs += cur.sumCallDurationMs;
    acc.callCount += cur.callCount;
    acc.inputTokens += cur.inputTokens;
    acc.outputTokens += cur.outputTokens;
    acc.reasoningTokens += cur.reasoningTokens;
    acc.totalTokens += cur.totalTokens;
    acc.costUsd += cur.costUsd;
    acc.inputChars += cur.inputChars;
    acc.outputChars += cur.outputChars;
  };

  for (const sec of params.sections) {
    addStep(totalsByStep["step2-mt"], sec.steps.step2Mt);
    addStep(totalsByStep["step3-llm"], sec.steps.step3Llm);
    addStep(totalsByStep["step4-rank"], sec.steps.step4Rank);

    for (const c of sec.calls) {
      const existing = totalsByProvider[c.providerId] ?? {
        providerLabel: c.providerLabel,
        callCount: 0,
        totalDurationMs: 0,
        avgDurationMs: 0,
        inputTokens: 0,
        outputTokens: 0,
        reasoningTokens: 0,
        totalTokens: 0,
        costUsd: 0,
        inputChars: 0,
        outputChars: 0,
      };
      existing.callCount += 1;
      existing.totalDurationMs += c.durationMs;
      existing.avgDurationMs = Math.round(existing.totalDurationMs / existing.callCount);
      existing.inputTokens += c.inputTokens ?? 0;
      existing.outputTokens += c.outputTokens ?? 0;
      existing.reasoningTokens += c.reasoningTokens ?? 0;
      existing.totalTokens += c.totalTokens ?? (c.inputTokens ?? 0) + (c.outputTokens ?? 0);
      existing.costUsd += c.costUsd ?? 0;
      existing.inputChars += c.inputChars;
      existing.outputChars += c.outputChars;
      totalsByProvider[c.providerId] = existing;
    }
  }

  const allStepItems = [
    totalsByStep["step2-mt"],
    totalsByStep["step3-llm"],
    totalsByStep["step4-rank"],
  ];

  const grandTotals = {
    wallDurationMs: Math.round(params.totalWallDurationMs),
    sumCallDurationMs: allStepItems.reduce((s, x) => s + x.sumCallDurationMs, 0),
    callCount: allStepItems.reduce((s, x) => s + x.callCount, 0),
    inputTokens: allStepItems.reduce((s, x) => s + x.inputTokens, 0),
    outputTokens: allStepItems.reduce((s, x) => s + x.outputTokens, 0),
    reasoningTokens: allStepItems.reduce((s, x) => s + x.reasoningTokens, 0),
    totalTokens: allStepItems.reduce((s, x) => s + x.totalTokens, 0),
    costUsd: allStepItems.reduce((s, x) => s + x.costUsd, 0),
    inputChars: allStepItems.reduce((s, x) => s + x.inputChars, 0),
    outputChars: allStepItems.reduce((s, x) => s + x.outputChars, 0),
  };

  return {
    runStartedAt: params.runStartedAt,
    runFinishedAt: params.runFinishedAt,
    targetLanguage: params.targetLanguage,
    dryRun: params.dryRun,
    totalWallDurationMs: Math.round(params.totalWallDurationMs),
    step1Context: params.step1Context,
    sections: params.sections,
    totalsByStep,
    totalsByProvider,
    grandTotals,
  };
}

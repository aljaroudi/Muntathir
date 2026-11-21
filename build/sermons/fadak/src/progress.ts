import fs from "node:fs/promises";
import path from "node:path";
import { readCacheMetrics } from "./cache";
import type { TranslationRegister, TranslationStepId } from "./types";

/** One billable LLM call: 4 models x 2 registers (step 3) + 2 rank calls (step 4). */
export interface Slot {
  key: string;
  /** Slots in the same stage run concurrently; stages run one after another. */
  stage: number;
  cacheFile: string;
}

export interface SlotStat {
  costUsd: number | null;
  durationMs: number | null;
}

export interface ProgressSnapshot {
  /** Money spent by live calls in this run. */
  spentUsd: number;
  /** Money already paid in earlier runs (cache hits). */
  cachedUsd: number;
  /** Estimated cost of calls not finished yet (excludes slots with no estimate). */
  leftUsd: number;
  pendingSlots: number;
  /** Pending slots we have no estimate for (so leftUsd is a lower bound). */
  unknownSlots: number;
  elapsedMs: number;
  /** Estimated time to finish; null when nothing to base it on. */
  etaMs: number | null;
}

export function slotKey(
  step: TranslationStepId,
  providerId: string,
  register?: TranslationRegister,
): string {
  return `${step}:${providerId}:${register ?? ""}`;
}

const REGISTERS: TranslationRegister[] = ["literal", "simplified"];

export function buildSlots(scope: string, modelIds: string[]): Slot[] {
  const slots: Slot[] = [];
  REGISTERS.forEach((register, i) => {
    for (const id of modelIds) {
      slots.push({
        key: slotKey("step3-llm", id, register),
        stage: i,
        cacheFile: `${scope}__step3-${id}-${register}.json`,
      });
    }
  });
  REGISTERS.forEach((register, i) => {
    slots.push({
      key: slotKey("step4-rank", "claude-rank", register),
      stage: 2 + i,
      cacheFile: `${scope}__step4-rank-${register}.json`,
    });
  });
  return slots;
}

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const s = [...values].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/**
 * Median cost/duration per slot across every language already translated for the same
 * scopes (output/<lang>/cache; pass the current scope plus older ones with similar cost). Used as the prior for languages not yet translated.
 */
export async function loadHistory(
  outputDir: string,
  scopes: string[],
): Promise<Map<string, SlotStat>> {
  const costs = new Map<string, number[]>();
  const durations = new Map<string, number[]>();

  let langDirs: string[] = [];
  try {
    langDirs = (await fs.readdir(outputDir, { withFileTypes: true }))
      .filter((d) => d.isDirectory())
      .map((d) => d.name);
  } catch {
    return new Map();
  }

  for (const lang of langDirs) {
    const cacheDir = path.join(outputDir, lang, "cache");
    let files: string[] = [];
    try {
      files = await fs.readdir(cacheDir);
    } catch {
      continue;
    }
    for (const f of files) {
      if (!scopes.some((sc) => f.startsWith(`${sc}__step3-`) || f.startsWith(`${sc}__step4-`))) continue;
      const m = await readCacheMetrics(path.join(cacheDir, f));
      if (!m || typeof m.costUsd !== "number") continue;
      const key = slotKey(m.step, m.providerId, m.register);
      costs.set(key, [...(costs.get(key) ?? []), m.costUsd]);
      if (m.durationMs > 0) durations.set(key, [...(durations.get(key) ?? []), m.durationMs]);
    }
  }

  const out = new Map<string, SlotStat>();
  for (const [key, c] of costs) {
    out.set(key, { costUsd: median(c), durationMs: median(durations.get(key) ?? []) });
  }
  return out;
}

interface DoneStat {
  costUsd: number;
  durationMs: number;
  cached: boolean;
}

export class ProgressTracker {
  private done = new Map<string, DoneStat>();
  private readonly startedAt: number;
  private stageStartedAt: number;

  constructor(
    private readonly slots: Slot[],
    private readonly history: Map<string, SlotStat>,
    private readonly now: () => number = () => performance.now(),
  ) {
    this.startedAt = now();
    this.stageStartedAt = this.startedAt;
  }

  complete(key: string, stat: DoneStat): void {
    this.done.set(key, stat);
    const slot = this.slots.find((s) => s.key === key);
    if (slot && this.slots.filter((s) => s.stage === slot.stage).every((s) => this.done.has(s.key))) {
      this.stageStartedAt = this.now();
    }
  }

  /** Mark slots that already have a cache file from an earlier run. */
  async markCached(cacheDir: string): Promise<number> {
    let count = 0;
    for (const slot of this.slots) {
      const m = await readCacheMetrics(path.join(cacheDir, slot.cacheFile));
      if (!m) continue;
      this.complete(slot.key, { costUsd: m.costUsd ?? 0, durationMs: m.durationMs, cached: true });
      count++;
    }
    return count;
  }

  /** Prior for a pending slot: history, else the same model's other register in this run. */
  private estimate(slot: Slot): SlotStat | null {
    const h = this.history.get(slot.key);
    if (h) return h;
    const [step, provider, register] = slot.key.split(":");
    const siblingKey = `${step}:${provider}:${register === "literal" ? "simplified" : "literal"}`;
    const d = this.done.get(siblingKey);
    if (d) return { costUsd: d.costUsd, durationMs: d.durationMs };
    return this.history.get(siblingKey) ?? null;
  }

  snapshot(): ProgressSnapshot {
    let spentUsd = 0;
    let cachedUsd = 0;
    for (const d of this.done.values()) {
      if (d.cached) cachedUsd += d.costUsd;
      else spentUsd += d.costUsd;
    }

    const pending = this.slots.filter((s) => !this.done.has(s.key));
    let leftUsd = 0;
    let unknownSlots = 0;
    for (const s of pending) {
      const cost = this.estimate(s)?.costUsd;
      if (typeof cost === "number") leftUsd += cost;
      else unknownSlots++;
    }

    // Stages run sequentially; slots inside a stage run in parallel (slowest one counts).
    let etaMs: number | null = null;
    let firstPendingStage = true;
    const stages = [...new Set(pending.map((s) => s.stage))].sort((a, b) => a - b);
    for (const stage of stages) {
      const isCurrent = firstPendingStage;
      firstPendingStage = false;
      const durations = pending
        .filter((s) => s.stage === stage)
        .map((s) => this.estimate(s)?.durationMs)
        .filter((d): d is number => typeof d === "number");
      if (durations.length === 0) continue;
      let stageMs = Math.max(...durations);
      if (isCurrent) stageMs = Math.max(0, stageMs - (this.now() - this.stageStartedAt));
      etaMs = (etaMs ?? 0) + stageMs;
    }
    if (pending.length === 0) etaMs = 0;

    return {
      spentUsd,
      cachedUsd,
      leftUsd,
      pendingSlots: pending.length,
      unknownSlots,
      elapsedMs: this.now() - this.startedAt,
      etaMs,
    };
  }
}

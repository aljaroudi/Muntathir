import fs from "node:fs/promises";
import path from "node:path";
import type { CallMetrics, RankedCandidate } from "./types";

export const CACHE_ENVELOPE_VERSION = 1;

export type CacheKind = "text" | "rank";

export interface CachedTextCall {
  text: string;
  metrics: CallMetrics;
}

export interface CachedRankCall {
  rankings: RankedCandidate[];
  synthesisNotes: string;
  finalTranslation: string;
  metrics: CallMetrics;
}

export interface CacheEnvelope<TPayload> {
  version: typeof CACHE_ENVELOPE_VERSION;
  kind: CacheKind;
  payload: TPayload;
  metrics: CallMetrics;
}

type TextPayload = { text: string };
type RankPayload = {
  rankings: RankedCandidate[];
  synthesisNotes: string;
  finalTranslation: string;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasMetrics(value: Record<string, unknown>): value is Record<string, unknown> & {
  metrics: CallMetrics;
} {
  return isRecord(value.metrics);
}

/** Normalize legacy flat blobs and v1 envelopes into a text cache entry. */
export function normalizeTextCache(raw: unknown): CachedTextCall | null {
  if (!isRecord(raw) || !hasMetrics(raw)) return null;

  if (raw.version === CACHE_ENVELOPE_VERSION && raw.kind === "text" && isRecord(raw.payload)) {
    const text = raw.payload.text;
    if (typeof text !== "string") return null;
    return { text, metrics: raw.metrics };
  }

  if (typeof raw.text === "string") {
    return { text: raw.text, metrics: raw.metrics };
  }

  return null;
}

/** Normalize legacy flat blobs and v1 envelopes into a rank cache entry. */
export function normalizeRankCache(raw: unknown): CachedRankCall | null {
  if (!isRecord(raw) || !hasMetrics(raw)) return null;

  if (raw.version === CACHE_ENVELOPE_VERSION && raw.kind === "rank" && isRecord(raw.payload)) {
    const { rankings, synthesisNotes, finalTranslation } = raw.payload;
    if (
      !Array.isArray(rankings) ||
      typeof synthesisNotes !== "string" ||
      typeof finalTranslation !== "string"
    ) {
      return null;
    }
    return {
      rankings: rankings as RankedCandidate[],
      synthesisNotes,
      finalTranslation,
      metrics: raw.metrics,
    };
  }

  if (
    Array.isArray(raw.rankings) &&
    typeof raw.synthesisNotes === "string" &&
    typeof raw.finalTranslation === "string"
  ) {
    return {
      rankings: raw.rankings as RankedCandidate[],
      synthesisNotes: raw.synthesisNotes,
      finalTranslation: raw.finalTranslation,
      metrics: raw.metrics,
    };
  }

  return null;
}

export function toTextEnvelope(data: CachedTextCall): CacheEnvelope<TextPayload> {
  return {
    version: CACHE_ENVELOPE_VERSION,
    kind: "text",
    payload: { text: data.text },
    metrics: data.metrics,
  };
}

export function toRankEnvelope(data: CachedRankCall): CacheEnvelope<RankPayload> {
  return {
    version: CACHE_ENVELOPE_VERSION,
    kind: "rank",
    payload: {
      rankings: data.rankings,
      synthesisNotes: data.synthesisNotes,
      finalTranslation: data.finalTranslation,
    },
    metrics: data.metrics,
  };
}

async function readRawJson(cacheFile: string): Promise<unknown | null> {
  try {
    const raw = await fs.readFile(cacheFile, "utf8");
    return JSON.parse(raw) as unknown;
  } catch {
    return null;
  }
}

export async function readTextCache(cacheFile: string): Promise<CachedTextCall | null> {
  return normalizeTextCache(await readRawJson(cacheFile));
}

export async function readRankCache(cacheFile: string): Promise<CachedRankCall | null> {
  return normalizeRankCache(await readRawJson(cacheFile));
}

/** Read metrics from either text or rank cache shapes (for cost estimates). */
export async function readCacheMetrics(cacheFile: string): Promise<CallMetrics | null> {
  const raw = await readRawJson(cacheFile);
  if (!isRecord(raw) || !hasMetrics(raw)) return null;
  return raw.metrics;
}

export async function writeTextCache(cacheFile: string, data: CachedTextCall): Promise<void> {
  await fs.mkdir(path.dirname(cacheFile), { recursive: true });
  await fs.writeFile(cacheFile, JSON.stringify(toTextEnvelope(data), null, 2), "utf8");
}

export async function writeRankCache(cacheFile: string, data: CachedRankCall): Promise<void> {
  await fs.mkdir(path.dirname(cacheFile), { recursive: true });
  await fs.writeFile(cacheFile, JSON.stringify(toRankEnvelope(data), null, 2), "utf8");
}

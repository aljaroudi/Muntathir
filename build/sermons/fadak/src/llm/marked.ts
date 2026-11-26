import { markerOf, parseMarked, type Segment } from "../segments";
import type { GatewayDetailedResult, GatewayTokenUsage } from "./gateway";

function addUsage(a: GatewayTokenUsage, b: GatewayTokenUsage): GatewayTokenUsage {
  const add = (x: number | null, y: number | null) =>
    x === null && y === null ? null : (x ?? 0) + (y ?? 0);
  return {
    inputTokens: add(a.inputTokens, b.inputTokens),
    outputTokens: add(a.outputTokens, b.outputTokens),
    reasoningTokens: add(a.reasoningTokens, b.reasoningTokens),
    totalTokens: add(a.totalTokens, b.totalTokens),
    costUsd: add(a.costUsd, b.costUsd),
  };
}

/**
 * Run a model call; if its output loses/duplicates/reorders segment markers (or fails
 * `extraCheck`), retry once with the problem spelled out. Usage of both tries is summed.
 */
export async function callUntilMarked<D>(opts: {
  segments: Segment[];
  label: string;
  warn: (message: string) => void;
  call: (repairNote?: string) => Promise<GatewayDetailedResult<D>>;
  text: (data: D) => string;
  /** Extra problems to report for a marker-valid answer (e.g. altered text). */
  extraCheck?: (text: string) => string[];
}): Promise<GatewayDetailedResult<D>> {
  const problemsOf = (data: D) => {
    const text = opts.text(data);
    return [...parseMarked(text, opts.segments).problems, ...(opts.extraCheck?.(text) ?? [])];
  };

  const first = await opts.call();
  let problems = problemsOf(first.data);
  if (problems.length === 0) return first;

  const why = problems.join("; ");
  opts.warn(`${opts.label}: bad output (${why}) - retrying once`);
  const second = await opts.call(
    `Your previous answer was rejected: ${why}. Return every ${markerOf("sNNN")} marker exactly once, in order.`,
  );
  problems = problemsOf(second.data);
  if (problems.length > 0) {
    throw new Error(`${opts.label}: invalid output after retry (${problems.join("; ")})`);
  }
  return {
    ...second,
    usage: addUsage(first.usage, second.usage),
    durationMs: first.durationMs + second.durationMs,
    inputChars: first.inputChars + second.inputChars,
    attempts: first.attempts + second.attempts,
  };
}

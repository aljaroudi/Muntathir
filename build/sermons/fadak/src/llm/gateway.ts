import { createGateway, type GatewayModelId } from "@ai-sdk/gateway";
import {
  type LanguageModel,
  type LanguageModelUsage,
  Output,
  type ProviderMetadata,
  streamText,
} from "ai";
import type { z } from "zod";

export interface GatewayCallOptions {
  baseUrl?: string;
  apiKey?: string;
  model: GatewayModelId;
  modelResolver?: (modelId: GatewayModelId) => LanguageModel;
  system: string;
  user: string;
  maxRetries?: number;
  timeoutMs?: number;
  onRetry?: (attempt: number, error: Error) => void;
}

export interface GatewayTokenUsage {
  inputTokens: number | null;
  outputTokens: number | null;
  reasoningTokens: number | null;
  totalTokens: number | null;
  costUsd: number | null;
}

export interface GatewayDetailedResult<T> {
  data: T;
  usage: GatewayTokenUsage;
  durationMs: number;
  inputChars: number;
  outputChars: number;
  attempts: number;
}

export function extractJsonPayload<T>(raw: string): T {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = (fenced ? fenced[1] : raw).trim();
  try {
    return JSON.parse(candidate) as T;
  } catch {
    const firstBrace = candidate.indexOf("{");
    const lastBrace = candidate.lastIndexOf("}");
    if (firstBrace !== -1 && lastBrace > firstBrace) {
      return JSON.parse(candidate.slice(firstBrace, lastBrace + 1)) as T;
    }
    throw new Error(`Failed to parse JSON payload: ${candidate.slice(0, 200)}`);
  }
}

function mapAiSdkUsage(
  usage: LanguageModelUsage,
  providerMetadata?: ProviderMetadata,
): GatewayTokenUsage {
  const inputTokens = usage.inputTokens ?? null;
  const outputTokens = usage.outputTokens ?? null;
  const reasoningTokens = usage.outputTokenDetails?.reasoningTokens ?? null;
  const totalTokens =
    usage.totalTokens ??
    (inputTokens !== null && outputTokens !== null ? inputTokens + outputTokens : null);

  const rawCost = providerMetadata?.gateway?.cost;
  const parsedCost =
    typeof rawCost === "number"
      ? rawCost
      : typeof rawCost === "string"
        ? Number(rawCost)
        : Number.NaN;
  const costUsd = Number.isFinite(parsedCost) ? parsedCost : null;

  return { inputTokens, outputTokens, reasoningTokens, totalTokens, costUsd };
}

function resolveLanguageModel(opts: GatewayCallOptions, fetchFn: typeof fetch): LanguageModel {
  if (opts.modelResolver) {
    return opts.modelResolver(opts.model);
  }
  // Ignore legacy OpenAI-compat `/v1` base URL so `@ai-sdk/gateway` uses its native `/v4/ai` endpoint
  const normalizedBase =
    opts.baseUrl && !opts.baseUrl.replace(/\/$/, "").endsWith("/v1") ? opts.baseUrl : undefined;

  const customFetch = Object.assign(
    (input: string | URL | Request, init?: RequestInit) =>
      fetchFn(input, { ...init, timeout: false } as unknown as RequestInit),
    { preconnect: fetchFn.preconnect },
  ) as typeof fetch;

  const gatewayProvider = createGateway({
    apiKey: opts.apiKey,
    ...(normalizedBase ? { baseURL: normalizedBase } : {}),
    // Disable Bun's default 300s idle socket timeout on streaming requests
    fetch: customFetch,
  });

  return gatewayProvider(opts.model);
}

export async function callGatewayStreamText(
  opts: GatewayCallOptions,
  fetchFn: typeof fetch = fetch,
): Promise<GatewayDetailedResult<string>> {
  const maxRetries = opts.maxRetries ?? 2;
  const timeoutMs = opts.timeoutMs ?? 1_800_000; // 30 minutes default
  const inputChars = opts.system.length + opts.user.length;
  const t0 = performance.now();
  let lastError: Error | undefined;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const model = resolveLanguageModel(opts, fetchFn);
      const result = streamText({
        model,
        system: opts.system,
        prompt: opts.user,
        maxRetries: 0,
        abortSignal: AbortSignal.timeout(timeoutMs),
      });

      const [text, usage, providerMetadata] = await Promise.all([
        result.text,
        result.usage,
        result.providerMetadata,
      ]);

      const trimmed = text.trim();
      if (!trimmed) {
        throw new Error(`Vercel AI Gateway (${opts.model}) returned empty text`);
      }

      return {
        data: trimmed,
        usage: mapAiSdkUsage(usage, providerMetadata),
        durationMs: Math.round(performance.now() - t0),
        inputChars,
        outputChars: trimmed.length,
        attempts: attempt + 1,
      };
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      if (attempt < maxRetries) {
        opts.onRetry?.(attempt + 1, lastError);
        await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
      }
    }
  }

  throw lastError ?? new Error("Gateway streamText call failed");
}

export async function callGatewayStreamStructured<TSchema extends z.ZodType>(
  opts: GatewayCallOptions & { schema: TSchema },
  fetchFn: typeof fetch = fetch,
): Promise<GatewayDetailedResult<z.infer<TSchema>>> {
  const maxRetries = opts.maxRetries ?? 2;
  const timeoutMs = opts.timeoutMs ?? 1_800_000;
  const inputChars = opts.system.length + opts.user.length;
  const t0 = performance.now();
  let lastError: Error | undefined;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      const model = resolveLanguageModel(opts, fetchFn);
      const result = streamText({
        model,
        system: opts.system,
        prompt: opts.user,
        output: Output.object({ schema: opts.schema }),
        maxRetries: 0,
        abortSignal: AbortSignal.timeout(timeoutMs),
      });

      const [output, text, usage, providerMetadata] = await Promise.all([
        result.output,
        result.text,
        result.usage,
        result.providerMetadata,
      ]);

      const validated = opts.schema.parse(output);

      return {
        data: validated,
        usage: mapAiSdkUsage(usage, providerMetadata),
        durationMs: Math.round(performance.now() - t0),
        inputChars,
        outputChars: text.length,
        attempts: attempt + 1,
      };
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      if (attempt < maxRetries) {
        opts.onRetry?.(attempt + 1, lastError);
        await new Promise((r) => setTimeout(r, 1000 * 2 ** attempt));
      }
    }
  }

  throw lastError ?? new Error("Gateway structured streamText call failed");
}

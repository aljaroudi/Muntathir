import type { GatewayModelId } from "@ai-sdk/gateway";
import type { LanguageModel } from "ai";
import type { TargetLanguage } from "./languages";

export type TranslationRegister = "literal" | "simplified";

export type TranslationStepId = "step1-context" | "step2-mt" | "step3-llm" | "step4-rank";

export interface SourceSection {
  id: string;
  title: string;
  arabicText: string;
}

export interface AlignedSegment {
  index: number;
  arabic: string;
  english: string;
}

export interface ContextBundle {
  fullArabicText: string;
  sections: SourceSection[];
  historicalCommentary: string;
  alignedReference: AlignedSegment[];
  targetLanguageReference?: string;
  kagiManualTranslation?: {
    filePath: string;
    text: string;
  };
}

export interface CallMetrics {
  step: TranslationStepId;
  sectionId: string;
  providerId: string;
  providerLabel: string;
  register?: TranslationRegister;
  model?: string;
  durationMs: number;
  inputTokens: number | null;
  outputTokens: number | null;
  reasoningTokens?: number | null;
  totalTokens: number | null;
  costUsd?: number | null;
  inputChars: number;
  outputChars: number;
  attempts?: number;
  cached?: boolean;
  sourceFile?: string;
}

export interface StepMetrics {
  step: TranslationStepId;
  wallDurationMs: number;
  sumCallDurationMs: number;
  callCount: number;
  inputTokens: number;
  outputTokens: number;
  reasoningTokens: number;
  totalTokens: number;
  costUsd: number;
  inputChars: number;
  outputChars: number;
}

export interface SectionMetrics {
  sectionId: string;
  sectionTitle: string;
  cached: boolean;
  wallDurationMs: number;
  steps: {
    step2Mt: StepMetrics;
    step3Llm: StepMetrics;
    step4Rank: StepMetrics;
  };
  calls: CallMetrics[];
  totalInputTokens: number;
  totalOutputTokens: number;
  totalTokens: number;
  totalCostUsd: number;
}

export interface ProviderAggregateMetrics {
  providerLabel: string;
  callCount: number;
  totalDurationMs: number;
  avgDurationMs: number;
  inputTokens: number;
  outputTokens: number;
  reasoningTokens: number;
  totalTokens: number;
  costUsd: number;
  inputChars: number;
  outputChars: number;
}

export interface RunMetricsReport {
  runStartedAt: string;
  runFinishedAt: string;
  targetLanguage: string;
  dryRun: boolean;
  totalWallDurationMs: number;
  step1Context: {
    durationMs: number;
    sectionCount: number;
    alignedSegmentCount: number;
    arabicChars: number;
    commentaryChars: number;
    kagiManualFile?: string;
  };
  sections: SectionMetrics[];
  totalsByStep: Record<TranslationStepId, StepMetrics>;
  totalsByProvider: Record<string, ProviderAggregateMetrics>;
  grandTotals: {
    wallDurationMs: number;
    sumCallDurationMs: number;
    callCount: number;
    inputTokens: number;
    outputTokens: number;
    reasoningTokens: number;
    totalTokens: number;
    costUsd: number;
    inputChars: number;
    outputChars: number;
  };
}

export interface CandidateTranslation {
  providerId: string;
  providerLabel: string;
  kind: "mt" | "llm";
  literal: string;
  simplified?: string;
  metrics?: CallMetrics;
}

export interface RankedCandidate {
  providerId: string;
  rank: number;
  score: number;
  strengths: string;
  issues: string;
}

export interface SectionSynthesis {
  sectionId: string;
  sectionTitle: string;
  targetLanguage: string;
  arabicText: string;
  candidates: CandidateTranslation[];
  literalRankings: RankedCandidate[];
  simplifiedRankings: RankedCandidate[];
  rankings: RankedCandidate[];
  finalLiteral: string;
  finalSimplified: string;
  literalSynthesisNotes: string;
  simplifiedSynthesisNotes: string;
  synthesisNotes: string;
  metrics?: SectionMetrics;
}

export interface PipelineConfig {
  dataDir: string;
  outputDir: string;
  targetLanguage: TargetLanguage;
  dryRun: boolean;
  skipMt: boolean;
  quiet?: boolean;
  onlySection?: string;
  requestTimeoutMs?: number;
  aiGatewayApiKey?: string;
  aiGatewayBaseUrl?: string;
  modelResolver?: (modelId: GatewayModelId) => LanguageModel;
  models: {
    gemini: GatewayModelId;
    grok: GatewayModelId;
    claude: GatewayModelId;
    gpt: GatewayModelId;
  };
  googleProjectId?: string;
  googleLocation: string;
  googleAccessToken?: string;
}

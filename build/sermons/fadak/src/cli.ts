import path from "node:path";
import { resolveTargetLanguage } from "./languages";
import { runPipeline } from "./pipeline";
import type { PipelineConfig } from "./types";

function parseArgs(argv: string[]): {
  lang: string;
  dryRun: boolean;
  skipMt: boolean;
  onlySection?: string;
} {
  let lang = process.env.TARGET_LANG;
  let dryRun = false;
  let skipMt = false;
  let onlySection: string | undefined;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--dry-run") dryRun = true;
    else if (arg === "--skip-mt") skipMt = true;
    else if ((arg === "--lang" || arg === "-l") && argv[i + 1]) {
      lang = argv[++i];
    } else if (arg.startsWith("--lang=")) {
      lang = arg.slice("--lang=".length);
    } else if (arg === "--section" && argv[i + 1]) {
      onlySection = argv[++i];
    } else if (arg.startsWith("--section=")) {
      onlySection = arg.slice("--section=".length);
    }
  }
  if (!lang) throw new Error("Specify --lang <code> or set TARGET_LANG");
  return { lang, dryRun, skipMt, onlySection };
}

async function main() {
  const flags = parseArgs(Bun.argv.slice(2));
  const rootDir = path.resolve(import.meta.dir, "..");
  const targetLanguage = resolveTargetLanguage(flags.lang);

  const config: PipelineConfig = {
    dataDir: path.join(rootDir, "data"),
    outputDir: path.join(rootDir, "output"),
    targetLanguage,
    dryRun: flags.dryRun,
    skipMt: flags.skipMt,
    onlySection: flags.onlySection,
    requestTimeoutMs: process.env.REQUEST_TIMEOUT_MS
      ? Number(process.env.REQUEST_TIMEOUT_MS)
      : 1_800_000,
    aiGatewayApiKey: process.env.AI_GATEWAY_API_KEY,
    aiGatewayBaseUrl: process.env.AI_GATEWAY_BASE_URL,
    models: {
      gemini: process.env.MODEL_GEMINI ?? "google/gemini-4-carbon",
      grok: process.env.MODEL_GROK ?? "spacexai/grok-4.7",
      claude: process.env.MODEL_CLAUDE ?? "anthropic/claude-fable-5.2",
      gpt: process.env.MODEL_GPT ?? "openai/gpt-6.2-astra",
    },
    googleProjectId: process.env.GOOGLE_CLOUD_PROJECT_ID,
    googleLocation: process.env.GOOGLE_CLOUD_LOCATION ?? "global",
    googleAccessToken: process.env.GOOGLE_TRANSLATE_ACCESS_TOKEN,
  };

  await runPipeline(config);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

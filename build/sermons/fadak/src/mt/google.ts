export interface GoogleTranslateOptions {
  projectId: string;
  location: string;
  accessToken: string;
  targetLanguageCode?: string;
}

export interface MtCallResult {
  text: string;
  durationMs: number;
  inputChars: number;
  outputChars: number;
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
}

export function chunkTextByParagraph(text: string, maxChars = 12000): string[] {
  if (text.length <= maxChars) return [text];
  const paragraphs = text.split(/\n+/);
  const chunks: string[] = [];
  let current = "";
  for (const para of paragraphs) {
    if ((current + "\n" + para).length > maxChars && current.length > 0) {
      chunks.push(current.trim());
      current = para;
    } else {
      current = current ? `${current}\n${para}` : para;
    }
  }
  if (current.trim()) chunks.push(current.trim());
  return chunks;
}

export async function translateWithGoogleV3Detailed(
  arabicText: string,
  opts: GoogleTranslateOptions,
  fetchFn: typeof fetch = fetch,
): Promise<MtCallResult> {
  const t0 = performance.now();
  const url = `https://translation.googleapis.com/v3/projects/${encodeURIComponent(opts.projectId)}/locations/${encodeURIComponent(opts.location)}:translateText`;
  const chunks = chunkTextByParagraph(arabicText);
  const translatedChunks: string[] = [];

  for (const chunk of chunks) {
    const res = await fetchFn(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${opts.accessToken}`,
        "x-goog-user-project": opts.projectId,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        contents: [chunk],
        mimeType: "text/plain",
        sourceLanguageCode: "ar",
        targetLanguageCode: opts.targetLanguageCode ?? "en",
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Google Translate v3 error (${res.status}): ${errText}`);
    }

    const data = (await res.json()) as {
      translations?: Array<{ translatedText?: string }>;
    };
    const text = data.translations?.[0]?.translatedText;
    if (!text) {
      throw new Error("Google Translate v3 returned empty translation");
    }
    translatedChunks.push(text);
  }

  const joined = translatedChunks.join("\n\n");
  return {
    text: joined,
    durationMs: Math.round(performance.now() - t0),
    inputChars: arabicText.length,
    outputChars: joined.length,
    inputTokens: null,
    outputTokens: null,
    totalTokens: null,
  };
}

export async function translateWithGoogleV3(
  arabicText: string,
  opts: GoogleTranslateOptions,
  fetchFn: typeof fetch = fetch,
): Promise<string> {
  const res = await translateWithGoogleV3Detailed(arabicText, opts, fetchFn);
  return res.text;
}

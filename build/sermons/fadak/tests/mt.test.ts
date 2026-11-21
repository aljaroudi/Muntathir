import { describe, expect, test } from "bun:test";
import { translateWithGoogleV3 } from "../src/mt/google";

describe("machine translation clients", () => {
  test("translateWithGoogleV3 posts to v3 translateText with x-goog-user-project and joins chunks", async () => {
    let capturedUrl = "";
    let capturedQuotaProject = "";
    let capturedBody: Record<string, unknown> = {};
    const mockFetch = (async (input: string | URL | Request, init?: RequestInit) => {
      capturedUrl = String(input);
      capturedQuotaProject = new Headers(init?.headers).get("x-goog-user-project") ?? "";
      capturedBody = JSON.parse(String(init?.body ?? "{}"));
      return new Response(
        JSON.stringify({ translations: [{ translatedText: "Praise be to Allah" }] }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }) as typeof fetch;

    const result = await translateWithGoogleV3(
      "اَلْحَمْدُللَّـهِ",
      { projectId: "demo-proj", location: "global", accessToken: "tok-123" },
      mockFetch,
    );

    expect(capturedUrl).toBe(
      "https://translation.googleapis.com/v3/projects/demo-proj/locations/global:translateText",
    );
    expect(capturedQuotaProject).toBe("demo-proj");
    expect(capturedBody.sourceLanguageCode).toBe("ar");
    expect(capturedBody.targetLanguageCode).toBe("en");
    expect(result).toBe("Praise be to Allah");
  });
});

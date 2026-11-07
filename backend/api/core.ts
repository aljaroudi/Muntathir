export const PROFILE = "gemini-embedding-2:1536:search-v1";
export const MODEL = "gemini-embedding-2";
export type SearchRequest = {
  query: string;
  kinds: string[] | null;
  sources: string[] | null;
  languages: string[] | null;
  chapter?: string;
  limit: number;
};

export function parseRequest(value: unknown): SearchRequest {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid request");
  }
  const v = value as Record<string, unknown>;
  if (
    Object.keys(v).some(
      (k) =>
        ![
          "query",
          "kinds",
          "sources",
          "languages",
          "chapter",
          "limit",
        ].includes(k),
    )
  )
    throw new Error("Unknown field");
  if (typeof v.query !== "string") throw new Error("Query required");
  const query = v.query.trim();
  if (
    !query ||
    [...query].length > 512 ||
    [...query].some((c) => c.codePointAt(0)! < 32)
  ) {
    throw new Error("Query must contain 1–512 characters");
  }
  const arrays = (key: string): string[] | null => {
    const a = v[key];
    if (a === undefined) return null;
    if (
      !Array.isArray(a) ||
      !a.length ||
      a.length > 20 ||
      a.some(
        (x) => typeof x !== "string" || !/^[\p{L}\p{N}_.:-]{1,100}$/u.test(x),
      )
    )
      throw new Error(`Invalid ${key}`);
    return [...new Set(a as string[])].sort();
  };
  const kinds = arrays("kinds");
  if (kinds?.some((x) => !["quran", "hadith", "dua"].includes(x))) {
    throw new Error("Invalid kinds");
  }
  const sources = arrays("sources");
  if (
    v.chapter !== undefined &&
    (typeof v.chapter !== "string" ||
      !/^[\p{L}\p{N}_.-]{1,100}$/u.test(v.chapter) ||
      kinds?.length !== 1 ||
      kinds[0] !== "hadith" ||
      sources?.length !== 1)
  )
    throw new Error("Chapter requires one hadith source");
  const limit = v.limit ?? 20;
  if (
    !Number.isInteger(limit) ||
    (limit as number) < 1 ||
    (limit as number) > 50
  )
    throw new Error("Invalid limit");
  return {
    query,
    kinds,
    sources,
    ...(v.chapter === undefined ? {} : { chapter: v.chapter as string }),
    languages: arrays("languages"),
    limit: limit as number,
  };
}

export function normalize(text: string): string {
  return text
    .normalize("NFKD")
    .replace(/\p{M}|[\u0640\u06d6-\u06ed]/gu, "")
    .replace(/[أإآٱ]/gu, "ا")
    .replace(/ى/gu, "ي")
    .toLowerCase();
}

export function reference(query: string): Record<string, unknown> | null {
  const ascii = query.replace(/[٠-٩۰-۹]/gu, (c) =>
    String(c.charCodeAt(0) - (c <= "٩" ? 0x660 : 0x6f0)),
  );
  const verse = ascii.match(/^(\d+)\s*:\s*(\d+)$/u);
  if (verse) {
    const chapter = Number(verse[1]),
      number = Number(verse[2]);
    if (chapter < 1 || chapter > 114 || number < 1 || number > 286) {
      throw new Error("Invalid verse reference");
    }
    return { chapter, verse: number };
  }
  const hadith = ascii.match(
    /^([\p{L}\p{N}_.-]+)\s*,\s*([0-9][\p{L}\p{N}_.-]*)$/u,
  );
  return hadith ? { book: hadith[1], number: hadith[2] } : null;
}

export function validVector(value: unknown): value is number[] {
  return (
    Array.isArray(value) &&
    value.length === 1536 &&
    value.every((x) => typeof x === "number" && Number.isFinite(x)) &&
    value.some((x) => x !== 0)
  );
}

export async function hash(value: string): Promise<string> {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  ]
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}

import fs from "node:fs/promises";
import path from "node:path";
import type { TargetLanguage } from "./languages";
import type { AlignedSegment, ContextBundle, SourceSection } from "./types";

function stripFrontmatter(md: string): string {
  return md.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, "");
}

export function extractFullArabicDocument(markdown: string): string {
  const withoutFm = stripFrontmatter(markdown);
  // Strip trailing Obsidian related-links section (`## روابط ذات صلة` onwards)
  const withoutLinks = withoutFm.replace(/\n---\s*\n##\s+روابط[\s\S]*$/, "");
  return withoutLinks.trim();
}

export function slugifySectionTitle(title: string, index: number): string {
  const prefix = String(index + 1).padStart(2, "0");
  if (title.includes("مقدمة")) return `${prefix}-intro`;
  if (title.includes("متن الخطبة")) return `${prefix}-sermon`;
  if (title.includes("قبر")) return `${prefix}-grave-elegy`;
  if (title.includes("فلان")) return `${prefix}-abu-bakr-dialogue`;
  if (title.includes("أمير المؤمنين")) return `${prefix}-ali-dialogue`;
  return `${prefix}-section`;
}

export function parseSourceSections(markdown: string): SourceSection[] {
  const body = stripFrontmatter(markdown);
  const lines = body.split(/\r?\n/);
  const sections: SourceSection[] = [];
  let currentTitle: string | null = null;
  let buffer: string[] = [];

  const flush = () => {
    if (!currentTitle) return;
    if (currentTitle.includes("روابط")) return;
    const text = buffer
      .join("\n")
      .replace(/^---+$/gm, "")
      .trim();
    if (text.length > 0) {
      sections.push({
        id: slugifySectionTitle(currentTitle, sections.length),
        title: currentTitle,
        arabicText: text,
      });
    }
  };

  for (const line of lines) {
    const headingMatch = line.match(/^#{2,3}\s+(.+)$/);
    if (headingMatch) {
      flush();
      const candidateTitle = headingMatch[1].trim();
      if (candidateTitle.startsWith("لسيدة نساء")) {
        currentTitle = null;
        buffer = [];
        continue;
      }
      currentTitle = candidateTitle;
      buffer = [];
      continue;
    }
    if (currentTitle) {
      buffer.push(line);
    }
  }
  flush();
  return sections;
}

export function parseAlignedSegments(markdown: string): AlignedSegment[] {
  const blocks = markdown.split(/^### \[(\d+)\]\s*$/gm);
  const segments: AlignedSegment[] = [];

  for (let i = 1; i < blocks.length; i += 2) {
    const index = Number(blocks[i]);
    const content = blocks[i + 1] ?? "";
    const arMatch = content.match(/>\s*\*\*العربية:\*\*\s*\r?\n((?:>.*\r?\n?)+)/);
    const enMatch = content.match(/>\s*\*\*English \(WikiShia Translation\):\*\*\s*\r?\n((?:>.*\r?\n?)+)/);
    if (!arMatch || !enMatch) continue;

    const cleanQuote = (raw: string) =>
      raw
        .split(/\r?\n/)
        .map((l) => l.replace(/^>\s?/, "").trim())
        .filter(Boolean)
        .join(" ");

    segments.push({
      index,
      arabic: cleanQuote(arMatch[1]),
      english: cleanQuote(enMatch[1]),
    });
  }

  return segments;
}

async function loadTargetReferenceIfAvailable(
  dataDir: string,
  targetLanguage?: TargetLanguage,
): Promise<string | undefined> {
  if (!targetLanguage?.referenceSubdir || targetLanguage.code === "en") {
    return undefined;
  }
  const refDir = path.join(dataDir, "translations", targetLanguage.referenceSubdir);
  try {
    const entries = await fs.readdir(refDir);
    const mdFiles = entries
      .filter((f) => f.endsWith(".md"))
      .sort();
    if (mdFiles.length === 0) return undefined;
    const contents = await Promise.all(
      mdFiles.map((f) => fs.readFile(path.join(refDir, f), "utf8")),
    );
    return contents.map(stripFrontmatter).join("\n\n").trim();
  } catch {
    return undefined;
  }
}

/** Kagi baselines are supplied by hand as `data/kagi/<code>-kagi.md` (lowercase code). */
export function manualKagiPath(dataDir: string, targetLanguage: TargetLanguage): string {
  return path.join(dataDir, "kagi", `${targetLanguage.code.toLowerCase()}-kagi.md`);
}

export async function findManualKagiTranslation(
  dataDir: string,
  targetLanguage?: TargetLanguage,
): Promise<{ filePath: string; text: string } | undefined> {
  if (!targetLanguage) return undefined;
  const filePath = manualKagiPath(dataDir, targetLanguage);
  try {
    const text = stripFrontmatter(await fs.readFile(filePath, "utf8")).trim();
    return text.length > 0 ? { filePath, text } : undefined;
  } catch {
    return undefined;
  }
}

export async function loadContextBundle(
  dataDir: string,
  targetLanguage?: TargetLanguage,
): Promise<ContextBundle> {
  const sourcePath = path.join(dataDir, "01 - النص العربي الأصلي الكامل.md");
  const commentaryPath = path.join(dataDir, "02 - السياق التاريخي ومصادر الشيعة وشرح المجلسي.md");
  const alignedPath = path.join(
    dataDir,
    "translations/en - English/3. WikiShia Bilingual (175 Aligned Segments).md",
  );

  const [sourceMd, commentaryMd, alignedMd, targetLanguageReference, kagiManualTranslation] =
    await Promise.all([
      fs.readFile(sourcePath, "utf8"),
      fs.readFile(commentaryPath, "utf8"),
      fs.readFile(alignedPath, "utf8"),
      loadTargetReferenceIfAvailable(dataDir, targetLanguage),
      findManualKagiTranslation(dataDir, targetLanguage),
    ]);

  return {
    fullArabicText: extractFullArabicDocument(sourceMd),
    sections: parseSourceSections(sourceMd),
    historicalCommentary: stripFrontmatter(commentaryMd).trim(),
    alignedReference: parseAlignedSegments(alignedMd),
    targetLanguageReference,
    kagiManualTranslation,
  };
}

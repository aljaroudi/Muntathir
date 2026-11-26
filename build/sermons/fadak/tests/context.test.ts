import { describe, expect, test } from "bun:test";
import path from "node:path";
import {
  extractFullArabicDocument,
  loadContextBundle,
  parseAlignedSegments,
  parseSourceSections,
} from "../src/context";
import { resolveTargetLanguage } from "../src/languages";

describe("context parser", () => {
  test("extractFullArabicDocument strips frontmatter and trailing Obsidian links while keeping continuous document", () => {
    const md = `---
title: Test
---
# الخطبة الفدكية
## مقدمة الرواية
روى عبد الله بن الحسن...
---
## متن الخطبة الشريفة
بِسْمِ اللهِ الرَّحْمنِ الرَّحيمِ
---
## روابط ذات صلة
- [[Link]]
`;
    const doc = extractFullArabicDocument(md);
    expect(doc).toContain("# الخطبة الفدكية");
    expect(doc).toContain("روى عبد الله بن الحسن");
    expect(doc).toContain("بِسْمِ اللهِ الرَّحْمنِ الرَّحيمِ");
    expect(doc).not.toContain("روابط ذات صلة");
  });

  test("parseSourceSections strips frontmatter and extracts sermon sections", () => {
    const md = `---
title: Test
---
# Title
## مقدمة الرواية
روى عبد الله بن الحسن...
---
## متن الخطبة الشريفة
بِسْمِ اللهِ الرَّحْمنِ الرَّحيمِ
اَلْحَمْدُللَّـهِ عَلی ما اَنْعَمَ
---
## روابط ذات صلة
- [[Link]]
`;
    const sections = parseSourceSections(md);
    expect(sections.length).toBe(2);
    expect(sections[0].id).toBe("01-intro");
    expect(sections[0].arabicText).toContain("روى عبد الله بن الحسن");
    expect(sections[1].id).toBe("02-sermon");
    expect(sections[1].arabicText).toContain("بِسْمِ اللهِ");
  });

  test("parseAlignedSegments extracts numbered WikiShia segments", () => {
    const md = `### [1]
> **العربية:**
> بِسْمِ اللهِ الرَّحْمنِ الرَّحيمِ

> **English (WikiShia Translation):**
> In the Name of Allah, the All-beneficent, the All-merciful.

### [2]
> **العربية:**
> اَلْحَمْدُللَّـهِ

> **English (WikiShia Translation):**
> Praise be to Allah
`;
    const segments = parseAlignedSegments(md);
    expect(segments.length).toBe(2);
    expect(segments[0]).toEqual({
      index: 1,
      arabic: "بِسْمِ اللهِ الرَّحْمنِ الرَّحيمِ",
      english: "In the Name of Allah, the All-beneficent, the All-merciful.",
    });
  });

  test("loadContextBundle reads real data directory and discovers data/kagi/en-kagi.md", async () => {
    const dataDir = path.resolve(import.meta.dir, "../data");
    const bundle = await loadContextBundle(dataDir, resolveTargetLanguage("en"));
    expect(bundle.fullArabicText.length).toBeGreaterThan(20000);
    expect(bundle.sections.length).toBeGreaterThanOrEqual(3);
    expect(bundle.alignedReference.length).toBe(175);
    expect(bundle.historicalCommentary.length).toBeGreaterThan(1000);
    expect(bundle.kagiManualTranslation?.filePath).toContain("en-kagi.md");
    expect(bundle.kagiManualTranslation?.text).toContain("Sermon of Fadak");
  });
});

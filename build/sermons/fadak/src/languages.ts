export interface TargetLanguage {
  code: string;
  name: string;
  googleCode: string;
  /** Estimated Muslim speakers, millions. Used to rank primary targets. */
  muslimSpeakersM?: number;
  /** Folder under data/translations/: `{code} - {English name}` */
  referenceSubdir?: string;
}

/** Stable `{code} - {name}` dir used under data/translations/. */
export function translationSubdir(code: string, name: string): string {
  return `${code} - ${name}`;
}

/** Primary targets in declared order (Muslim speakers, millions). Ties keep this order. */
const PRIMARY_TARGETS: TargetLanguage[] = [
  { code: "bn", name: "Bengali", googleCode: "bn", muslimSpeakersM: 220 },
  { code: "id", name: "Indonesian", googleCode: "id", muslimSpeakersM: 220 },
  { code: "ur", name: "Urdu", googleCode: "ur", muslimSpeakersM: 180 },
  { code: "pa", name: "Punjabi", googleCode: "pa", muslimSpeakersM: 90 },
  { code: "tr", name: "Turkish", googleCode: "tr", muslimSpeakersM: 85 },
  { code: "fa", name: "Persian", googleCode: "fa", muslimSpeakersM: 80 },
  { code: "ha", name: "Hausa", googleCode: "ha", muslimSpeakersM: 70 },
  { code: "jv", name: "Javanese", googleCode: "jw", muslimSpeakersM: 70 },
  { code: "ps", name: "Pashto", googleCode: "ps", muslimSpeakersM: 45 },
  { code: "ms", name: "Malay", googleCode: "ms", muslimSpeakersM: 30 },
  { code: "sd", name: "Sindhi", googleCode: "sd", muslimSpeakersM: 30 },
  { code: "uz", name: "Uzbek", googleCode: "uz", muslimSpeakersM: 25 },
  { code: "so", name: "Somali", googleCode: "so", muslimSpeakersM: 20 },
  { code: "ff", name: "Fulah", googleCode: "ff", muslimSpeakersM: 20 },
  { code: "ku", name: "Kurdish", googleCode: "ku", muslimSpeakersM: 15 },
  { code: "yo", name: "Yoruba", googleCode: "yo", muslimSpeakersM: 15 },
  { code: "sw", name: "Swahili", googleCode: "sw", muslimSpeakersM: 15 },
];

/** Already have human/Kagi/AI material; kept even without a speaker rank. */
const EXISTING_MATERIAL: TargetLanguage[] = [
  { code: "en", name: "English", googleCode: "en" },
  { code: "zh-CN", name: "Mandarin Chinese (Simplified)", googleCode: "zh-CN" },
  { code: "fr", name: "French", googleCode: "fr" },
  { code: "az", name: "Azerbaijani", googleCode: "az" },
  { code: "de", name: "German", googleCode: "de" },
  { code: "es", name: "Spanish", googleCode: "es" },
  { code: "ru", name: "Russian", googleCode: "ru" },
];

const KNOWN_LANGUAGES: Record<string, TargetLanguage> = {};
for (const lang of [...PRIMARY_TARGETS, ...EXISTING_MATERIAL]) {
  lang.referenceSubdir = translationSubdir(lang.code, lang.name);
  KNOWN_LANGUAGES[lang.code.toLowerCase()] = lang;
}
KNOWN_LANGUAGES.zh = KNOWN_LANGUAGES["zh-cn"];

/** Unique targets: primary list order, then languages kept for existing material. */
export function listTargetLanguages(): TargetLanguage[] {
  const primaryCodes = new Set(PRIMARY_TARGETS.map((l) => l.code));
  return [
    ...PRIMARY_TARGETS,
    ...EXISTING_MATERIAL.filter((l) => !primaryCodes.has(l.code)),
  ];
}

export function resolveTargetLanguage(input: string): TargetLanguage {
  const normalized = input.trim().toLowerCase();
  if (KNOWN_LANGUAGES[normalized]) {
    return KNOWN_LANGUAGES[normalized];
  }
  const byName = Object.values(KNOWN_LANGUAGES).find(
    (l) => l.name.toLowerCase() === normalized || l.name.toLowerCase().startsWith(normalized),
  );
  if (byName) return byName;

  const code = input.trim();
  const name = input.trim();
  return {
    code,
    name,
    googleCode: code,
    referenceSubdir: translationSubdir(code, name),
  };
}

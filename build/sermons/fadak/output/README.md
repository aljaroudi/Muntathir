# Translation outputs

Each subdirectory is a target language code (`--lang <code>`).

- **Speakers:** estimated Muslim speakers in millions (primary ranking). `—` = kept because material already exists
- **Human:** files under `data/translations/<code> - <Name>/`
- **Machine:** Kagi file in `data/kagi/<code>-kagi.md` and/or finished AI run in `output/<code>/`
- **AI cost:** gateway spend from that language's `metrics.json` (translation only; alignment is separate)
- **Aligned:** sources present in `output/<code>/translations.json` (segment IDs for the bundled reader)

`✅` = present. `✅ +N` = N extra of that type. `—` = none.

Regenerate this table: `bun run status`

**Progress:** 10 human · 3 machine · 2 AI done · AI spend $13.24

| Code | Language | Speakers (M) | Human | Machine | AI cost | Aligned |
|---|---|---:|---|---|---|---|
| bn | Bengali | 220 | — | — | — | — |
| id | Indonesian | 220 | ✅ | — | — | — |
| ur | Urdu | 180 | ✅ | — | — | — |
| pa | Punjabi | 90 | — | — | — | — |
| tr | Turkish | 85 | ✅ | — | — | — |
| fa | Persian | 80 | ✅ | — | — | — |
| ha | Hausa | 70 | — | — | — | — |
| jv | Javanese | 70 | — | — | — | — |
| ps | Pashto | 45 | — | — | — | — |
| ms | Malay | 30 | — | — | — | — |
| sd | Sindhi | 30 | — | — | — | — |
| uz | Uzbek | 25 | — | — | — | — |
| so | Somali | 20 | — | — | — | — |
| ff | Fulah | 20 | — | — | — | — |
| ku | Kurdish | 15 | — | — | — | — |
| yo | Yoruba | 15 | — | — | — | — |
| sw | Swahili | 15 | ✅ | — | — | — |
| en | English | — | ✅ +3 | ✅ +1 | $7.49 | ai/literal, ai/simplified, human:wikishia, kagi |
| zh-CN | Mandarin Chinese (Simplified) | — | — | ✅ +1 | $5.74 | ai/literal, ai/simplified, kagi |
| fr | French | — | — | ✅ | — | — |
| az | Azerbaijani | — | ✅ | — | — | — |
| de | German | — | ✅ | — | — | — |
| es | Spanish | — | ✅ | — | — | — |
| ru | Russian | — | ✅ | — | — | — |

# Jev 1.14 benchmark — 14 November 2026

Jev is integrated for optional meaning-search reranking (setup in
[SEARCH_SERVICE.md](SEARCH_SERVICE.md#jev-reranking); method in
[RERANK_BENCHMARK.md](RERANK_BENCHMARK.md)).

150 queries, identical frozen top-20 candidate pools, sequential requests, 2 s timeout.
All 150 returned valid rankings, no retries. 142 queries have positive judgments; the 8
without are excluded from NDCG and top-result accuracy.

| Group | Baseline NDCG@10 | Jev NDCG@10 |
| --- | ---: | ---: |
| All scored queries | 0.7655 | 0.7993 |
| Held-out, verified English | 0.6284 | 0.6683 |
| Held-out, verified Arabic | 0.4903 | 0.5975 |
| Held-out, seed-positive English | 0.9752 | 0.9646 |
| Held-out, seed-positive Arabic | 1.0000 | 0.9789 |

- Top-result accuracy: 70.42% → 71.83%. Candidate recall unchanged at 91.01%.
- Reranker-only latency (dev machine, not end-to-end or concurrent): median 236.6 ms,
  p95 275.0 ms, max 462.1 ms. The retrieval load target is 300 ms, so end-to-end latency
  needs its own budget and measurement.
- Usage: 786,139 input tokens; at $0.042 per million input tokens (output free) ≈
  $0.033017838 total, $0.000220119 per query (from response usage, not an invoice).
  [Provider pricing](https://help.typesafe.ai/articles/5187202169-how-much-does-jev-cost).

## Caveats

- Labels are incomplete seed positives: on average 8.87 of the reranked top ten are
  unjudged and count as zero. Seed-positive groups declined slightly, so the
  no-regression gate has **not** passed.
- Numeric reference queries were included here, but production resolves explicit
  references before reranking; Jev only orders explicit meaning searches.
- Do not tune against these held-out outcomes or fill missing labels with model judgments.
- Re-run full-corpus relevance and end-to-end concurrent load gates before activating a
  collection; keep the previous collection for rollback.

Raw run: `backend/work/refresh-2026-11-14/jev-results.jsonl`; grouped report
`jev-report.json` alongside. Snapshot SHA-256:
`9cafee7626f7618cf54cf3130308d173c6c27779270b356198a4b2407f5428ac`.

## Additional review comparisons

Grade each passage 0–3. Check whether multiple references are equally relevant, and whether exact wording or broader meaning is intended. Displayed passages are the exact text sent to Jev. No new judgments have been assigned.

### hadith-exact_fasting-en: Fasting is a shield

Intended meaning / exclusions: ______

#### {"kind": "hadith", "book": "muslim", "chapter": "13.json", "number": 211}

Item `0abc6fa1-86ad-5fab-b81c-bc729e066e34` · baseline rank 1 · Jev rank 11

Fasting is a shield.

Grade ___ · Reason ___

#### {"kind": "hadith", "book": "bukhari", "chapter": "30.json", "number": 4}

Item `b636881b-e158-59f5-8c53-2aed800f9db5` · baseline rank 16 · Jev rank 1

Allah's Messenger (ﷺ) said, "Fasting is a shield (or a screen or a shelter). So, the person observing fasting 
should avoid sexual relation with his wife and should not behave foolishly and impudently, and if 
somebody fights with him or abuses him, he should tell him twice, 'I am fasting." The Prophet (ﷺ) added, 
"By Him in Whose Hands my soul is, the smell coming out from the mouth of a fasting person is 
better in the sight of Allah than the smell of musk. (Allah says about the fasting person), 'He has left 
his food, drink and desires for My sake. The fast is for Me. So I will reward (the fasting person) for it 
and the reward of good deeds is multiplied ten times."

Grade ___ · Reason ___

#### {"kind": "hadith", "book": "nasai", "chapter": "22.json", "number": 135}

Item `6c9c9ed7-afd7-5b07-817d-8894cbbfdbe8` · baseline rank 2 · Jev rank 2

"The Messenger of Allah said: 'Fasting is a shield."'

Grade ___ · Reason ___

#### {"kind": "hadith", "book": "nasai", "chapter": "22.json", "number": 128}

Item `0f0f10fc-bb78-5181-b2ab-c05d73c2a850` · baseline rank 20 · Jev rank 3

"The Messenger of Allah said: 'Allah, the Mighty and sublime, said: Every deed of the son of Adam is for him, except fasting; it is for me and I shall reward for it. Fasting is a shield. If any one of you is observing a fast, let him not utte obscene a fast, let him not utter obscene talk or raise his voice in anger, and if anyone insults him or wants to fight, let him say: I am a person who is fasting. By the One in Whose hand is the soul of Muhammad, the smell coming from the mouth of the fasting person is better before Allah than the fragrance of musk." ' (Sahih) 
This Hadith was narrated from Abu Hurairah by Saeed bin Al-Musayyab.

Grade ___ · Reason ___

### hadith-smiling-en: Kindness through a cheerful face

Intended meaning / exclusions: ______

#### {"kind": "hadith", "book": "tirmidhi", "chapter": "27.json", "number": 76}

Item `0a76a8d8-4ec5-5b93-84fb-ad83ae014350` · baseline rank 1 · Jev rank 8

"Every good is charity. Indeed among the good is to meet your brother with a smiling face, and to pour what is left in your bucket into the vessel of your brother."

Grade ___ · Reason ___

#### {"kind": "hadith", "book": "muslim", "chapter": "45.json", "number": 187}

Item `282e4507-bf01-595f-8071-0db3c1ae00e1` · baseline rank 2 · Jev rank 1

Allah's Apostle (ﷺ) said to me: Don't consider anything insignificant out of good things even if it is that you meet your brother with a cheerful countenance.

Grade ___ · Reason ___

#### {"kind": "hadith", "book": "tirmidhi", "chapter": "27.json", "number": 62}

Item `b04dc608-90a1-501e-babc-b1d82d8545a4` · baseline rank 3 · Jev rank 2

"Your smiling in the face of your brother is charity, commanding good and forbidding evil is charity, your giving directions to a man lost in the land is charity for you. Your seeing for a man with bad sight is a charity for you, your removal of a rock, a thorn  or a bone from the road is charity for you. Your pouring what remains from your bucket into the bucket of your brother is charity for you."

Grade ___ · Reason ___

#### {"kind": "hadith", "book": "alkafi-2", "chapter": "1.json", "number": 748}

Item `1f2b40f7-97e7-547c-a381-e175bc2c13c2` · baseline rank 10 · Jev rank 3

1. Muhammad ibn Yahya has narrated from Ahmad ibn Muhammad ibn ‘Isa from Ali ibn al-Hakam from al-Husayn ibn Hashim from Sa’dan ibn Muslim from abu ‘Abd Allah (a.s.) who has said the following: “Whoever removes a speck from the face of his brother (in belief), Allah, the Most Majestic, the Most Holy, then will write down for the former ten good deeds and whoever smiles to his brother (in belief) earns one good deed.” 

Grade ___ · Reason ___

### additional-18-en: No soul is burdened beyond its capacity

Intended meaning / exclusions: ______

#### {"kind": "quran", "chapter": 2, "verse": 286}

Item `d0b3ed0c-b85a-532c-b322-72234773e15d` · baseline rank 1 · Jev rank 3

لا يُكَلِّفُ اللَّهُ نَفسًا إِلّا وُسعَها ۚ لَها ما كَسَبَت وَعَلَيها مَا اكتَسَبَت ۗ رَبَّنا لا تُؤاخِذنا إِن نَسينا أَو أَخطَأنا ۚ رَبَّنا وَلا تَحمِل عَلَينا إِصرًا كَما حَمَلتَهُ عَلَى الَّذينَ مِن قَبلِنا ۚ رَبَّنا وَلا تُحَمِّلنا ما لا طاقَةَ لَنا بِهِ ۖ وَاعفُ عَنّا وَاغفِر لَنا وَارحَمنا ۚ أَنتَ مَولىٰنا فَانصُرنا عَلَى القَومِ الكـٰفِرينَ

Grade ___ · Reason ___

#### {"kind": "quran", "chapter": 23, "verse": 62}

Item `725aed22-a678-5a37-90f2-a63291f1fc9f` · baseline rank 2 · Jev rank 1

وَلا نُكَلِّفُ نَفسًا إِلّا وُسعَها ۖ وَلَدَينا كِتـٰبٌ يَنطِقُ بِالحَقِّ ۚ وَهُم لا يُظلَمونَ

Grade ___ · Reason ___

#### {"kind": "quran", "chapter": 7, "verse": 42}

Item `e2d91580-00f3-5964-bd61-df6eecb52c5b` · baseline rank 4 · Jev rank 2

وَالَّذينَ ءامَنوا وَعَمِلُوا الصّـٰلِحـٰتِ لا نُكَلِّفُ نَفسًا إِلّا وُسعَها أُولـٰئِكَ أَصحـٰبُ الجَنَّةِ ۖ هُم فيها خـٰلِدونَ

Grade ___ · Reason ___

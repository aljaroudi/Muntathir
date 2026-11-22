import { normalize, type SearchRequest } from './core.ts'

export type Reference =
  | { kind: 'quran'; chapter: number; verse: number }
  | { kind: 'hadith'; book: string; chapter: string; number: number }
  | { kind: 'dua'; id: string; passage?: number; locator?: string }
  | { kind: 'figure'; id: string }
  | { kind: 'rulings'; authority: string; language: string; id: string }
export type Hit = Reference & { score: number | null }
export type Point = {
  id: string
  score: number
  payload: { item_id: string; ref: Reference; text?: string; search_text?: string }
  vector?: number[]
}
/** Match tiers, best first: the whole query as consecutive words, then everything else. */
export const PHRASE = 1,
  MEANING = 0
export function words(text: string): string[] {
  return normalize(text).match(/[\p{L}\p{N}]+/gu) ?? []
}
/** Whether [query] appears in [text] as consecutive whole words. */
export function containsPhrase(query: string[], text: string[]): boolean {
  if (!query.length || query.length > text.length) return false
  outer: for (let i = 0; i + query.length <= text.length; i++) {
    for (let j = 0; j < query.length; j++) if (text[i + j] !== query[j]) continue outer
    return true
  }
  return false
}
/** Sorts by tier, keeping the existing order within each tier. */
export function byTier<T>(values: T[], tier: (value: T) => number): T[] {
  return values
    .map((value, index) => ({ value, index, tier: tier(value) }))
    .sort((a, b) => b.tier - a.tier || a.index - b.index)
    .map((entry) => entry.value)
}
export class Qdrant {
  private cachedActive: { name: string; expiresAt: number } | null = null
  private pendingActive: Promise<string> | null = null

  constructor(
    readonly url: string,
    readonly key = '',
    private readonly ttlMs = 30_000,
    private readonly now = Date.now,
  ) {}
  async call(
    path: string,
    body?: unknown,
    method = body === undefined ? 'GET' : 'POST',
  ): Promise<any> {
    const response = await fetch(`${this.url}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(this.key ? { 'api-key': this.key } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(4000),
    })
    if (!response.ok) {
      if (response.status === 404 && path.startsWith('/collections/')) this.invalidateActive()
      throw new Error(`Qdrant HTTP ${response.status}`)
    }
    return ((await response.json()) as any).result
  }
  invalidateActive() {
    this.cachedActive = null
  }
  async active(force = false): Promise<string> {
    if (!force && this.cachedActive && this.now() < this.cachedActive.expiresAt) {
      return this.cachedActive.name
    }
    if (!this.pendingActive) {
      this.pendingActive = (async () => {
        const result = await this.call('/aliases')
        const name = result.aliases.find((a: any) => a.alias_name === 'search')?.collection_name
        if (!name) {
          this.cachedActive = null
          throw new Error('No active corpus')
        }
        this.cachedActive = { name, expiresAt: this.now() + this.ttlMs }
        return name
      })()
      void this.pendingActive
        .finally(() => {
          this.pendingActive = null
        })
        .catch(() => {})
    }
    return await this.pendingActive
  }
  async query(collection: string, body: unknown): Promise<Point[]> {
    return (await this.call(`/collections/${encodeURIComponent(collection)}/points/query`, body))
      .points
  }
}
export function filter(input: SearchRequest): { must: any[] } {
  const must: any[] = []
  for (const [key, values] of [
    ['kind', input.kinds ?? ['quran', 'hadith', 'dua', 'rulings']],
    ['source_id', input.sources],
    ['language', input.languages],
  ] as const) {
    if (values) must.push({ key, match: { any: values } })
  }
  if (input.chapter)
    must.push({
      key: 'ref.chapter',
      match: {
        value: input.kinds?.[0] === 'quran' ? Number(input.chapter) : input.chapter,
      },
    })
  return { must }
}
export function cosine(a: number[], b: number[]): number {
  if (a.length !== b.length) throw new Error('Vector dimension mismatch')
  let dot = 0,
    aa = 0,
    bb = 0
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i]
    aa += a[i] * a[i]
    bb += b[i] * b[i]
  }
  if (!aa || !bb) throw new Error('Zero vector')
  return Math.max(-1, Math.min(1, dot / Math.sqrt(aa * bb)))
}
/** Best score first. Qdrant orders ties arbitrarily, so break them by ID to keep fusion repeatable. */
const byScore = (a: Point, b: Point) => b.score - a.score || a.id.localeCompare(b.id)
export function fuse(
  semantic: Point[],
  lexical: Point[],
  scores: Map<string, number> | null,
  limit: number,
  tiers: Map<string, number> = new Map(),
) {
  const passages = new Map<string, { point: Point; rank: number }>()
  for (const list of [semantic, lexical])
    list.forEach((point, index) => {
      const found = passages.get(point.id) ?? { point, rank: 0 }
      found.rank += 1 / (61 + index)
      passages.set(point.id, found)
    })
  const items = new Map<
    string,
    {
      id: string
      pointId: string
      ref: Reference
      rank: number
      score: number | null
      text: string
      tier: number
    }
  >()
  for (const { point, rank } of passages.values()) {
    const score = scores?.get(point.id) ?? null
    if (scores && !Number.isFinite(score)) throw new Error('Missing cosine')
    const id = point.payload.item_id,
      previous = items.get(id),
      tier = tiers.get(point.id) ?? MEANING
    if (previous) {
      previous.tier = Math.max(previous.tier, tier)
      if (rank > previous.rank) {
        previous.pointId = point.id
        previous.text = point.payload.text ?? ''
      }
      previous.rank = Math.max(previous.rank, rank)
      if (score !== null) previous.score = Math.max(previous.score ?? score, score)
    } else {
      items.set(id, {
        id,
        pointId: point.id,
        ref: point.payload.ref,
        rank,
        score,
        text: point.payload.text ?? '',
        tier,
      })
    }
  }
  // Exact phrases first; fusion rank orders each tier.
  return [...items.values()]
    .sort((a, b) => b.tier - a.tier || b.rank - a.rank || a.id.localeCompare(b.id))
    .slice(0, limit)
}
export async function retrieve(
  db: Qdrant,
  collection: string,
  input: SearchRequest,
  vector: number[] | null,
  direct: Record<string, unknown> | null,
  includePassages = false,
) {
  const selected = filter(input)
  if (direct) {
    selected.must.push({
      key: 'kind',
      match: { value: direct.book ? 'hadith' : 'quran' },
    })
    for (const [key, value] of Object.entries(direct)) {
      selected.must.push({
        key: `ref.${key}`,
        match: { value: key === 'number' ? Number(value) : value },
      })
    }
    const unique = new Map<string, Hit>()
    let offset: unknown = undefined
    do {
      const page = await db.call(`/collections/${collection}/points/scroll`, {
        filter: selected,
        limit: 256,
        offset,
        with_payload: ['item_id', 'ref'],
        with_vector: false,
      })
      for (const point of page.points)
        unique.set(point.payload.item_id, {
          ...point.payload.ref,
          score: null,
        })
      offset = page.next_page_offset
    } while (offset && unique.size < input.limit)
    return {
      results: [...unique.entries()]
        .sort(([a], [b]) => a.localeCompare(b))
        .slice(0, input.limit)
        .map(([, hit]) => hit),
    }
  }
  selected.must.push({
    should: [
      { key: 'kind', match: { any: ['hadith', 'dua', 'rulings', 'figure'] } },
      { key: 'search_eligible', match: { value: true } },
    ],
  })
  const common = {
    filter: selected,
    limit: 100,
    with_payload: ['item_id', 'ref'],
    with_vector: false,
  }
  const [rawSemantic, rawLexical] = await Promise.all([
    vector ? db.query(collection, {
      ...common,
      query: vector,
      params: { exact: true },
    }).catch(() => null) : null,
    db.query(collection, {
      ...common,
      with_payload: ['item_id', 'ref', 'search_text'],
      filter: {
        must: [...selected.must, { key: 'search_text', match: { text: normalize(input.query) } }],
      },
      query: { text: normalize(input.query) },
      using: 'search_text',
    }),
  ])
  let semantic = (rawSemantic ?? [])
    .sort(byScore)
    .slice(0, 100)
  const lexical = rawLexical.sort(byScore)
  const scores = new Map(semantic.map((p) => [p.id, p.score]))
  let degraded = rawSemantic === null
  const missing = lexical.filter((p) => !scores.has(p.id)).map((p) => p.id)
  if (vector && rawSemantic && missing.length) {
    try {
      const points = await db.call(`/collections/${collection}/points`, {
        ids: missing,
        with_vector: true,
        with_payload: false,
      })
      for (const p of points) scores.set(p.id, cosine(vector, p.vector))
      if (missing.some(id => !Number.isFinite(scores.get(id)))) throw new Error('Missing vector')
    } catch {
      semantic = []
      degraded = true
    }
  }
  // Only whole phrases outrank fusion: long passages often contain every query word by chance.
  const query = words(input.query)
  const tiers = new Map(
    lexical.map((p) => [
      p.id,
      containsPhrase(query, words(p.payload.search_text ?? '')) ? PHRASE : MEANING,
    ]),
  )
  const ranked = fuse(semantic, lexical, degraded ? null : scores, input.limit, tiers)
  let texts = new Map<string, string>()
  if (includePassages && ranked.length) {
    const points = await db.call(`/collections/${collection}/points`, {
      ids: ranked.slice(0, 20).map((p) => p.pointId),
      with_payload: ['text'],
      with_vector: false,
    }).catch(() => null)
    if (!Array.isArray(points)) degraded = true
    else {
      texts = new Map(points.map((p: any) => [String(p.id), p.payload?.text ?? '']))
    }
  }
  const missingPassages = includePassages && ranked.slice(0, 20).some(p => !texts.get(p.pointId) && !p.text)
  return {
    degraded: degraded || missingPassages,
    missingPassages,
    results: ranked.map((p) => ({ ...p.ref, score: p.score })),
    candidates: ranked.map((p) => ({
      id: p.id,
      hit: { ...p.ref, score: p.score },
      text: texts.get(p.pointId) ?? p.text,
      tier: p.tier,
    })),
    itemIDs: ranked.map((p) => p.id),
    semanticIDs: semantic.map((p) => p.id),
    semanticItemIDs: [...new Set(semantic.map((p) => p.payload.item_id))],
    lexicalItemIDs: [...new Set(lexical.map((p) => p.payload.item_id))],
  }
}

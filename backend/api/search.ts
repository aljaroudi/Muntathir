import { normalize, type SearchRequest } from './core.ts'

export type Reference =
  | { kind: 'quran'; chapter: number; verse: number }
  | { kind: 'hadith'; book: string; chapter: string; number: number }
  | { kind: 'dua'; id: string; passage?: number }
export type Hit = Reference & { score: number | null }
export type Point = {
  id: string
  score: number
  payload: { item_id: string; ref: Reference; text?: string }
  vector?: number[]
}
export class Qdrant {
  constructor(
    readonly url: string,
    readonly key = '',
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
    if (!response.ok) throw new Error(`Qdrant HTTP ${response.status}`)
    return ((await response.json()) as any).result
  }
  async active(): Promise<string> {
    const result = await this.call('/aliases')
    const name = result.aliases.find((a: any) => a.alias_name === 'search')?.collection_name
    if (!name) throw new Error('No active corpus')
    return name
  }
  async query(collection: string, body: unknown): Promise<Point[]> {
    return (await this.call(`/collections/${encodeURIComponent(collection)}/points/query`, body))
      .points
  }
}
export function filter(input: SearchRequest): { must: any[] } {
  const must: any[] = []
  for (const [key, values] of [
    ['kind', input.kinds],
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
export function fuse(
  semantic: Point[],
  lexical: Point[],
  scores: Map<string, number>,
  limit: number,
) {
  const passages = new Map<string, { point: Point; rank: number }>()
  for (const list of [semantic, lexical])
    list.forEach((point, index) => {
      const found = passages.get(point.id) ?? { point, rank: 0 }
      found.rank += 1 / (61 + index)
      passages.set(point.id, found)
    })
  const items = new Map<string, { id: string; ref: Reference; rank: number; score: number }>()
  for (const { point, rank } of passages.values()) {
    const score = scores.get(point.id)
    if (score === undefined || !Number.isFinite(score)) throw new Error('Missing cosine')
    const id = point.payload.item_id,
      previous = items.get(id)
    if (previous) {
      previous.rank = Math.max(previous.rank, rank)
      previous.score = Math.max(previous.score, score)
    } else items.set(id, { id, ref: point.payload.ref, rank, score })
  }
  return [...items.values()]
    .sort((a, b) => b.rank - a.rank || a.id.localeCompare(b.id))
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
  if (!vector) throw new Error('Missing query embedding')
  selected.must.push({
    should: [
      { key: 'kind', match: { any: ['hadith', 'dua'] } },
      { key: 'search_eligible', match: { value: true } },
    ],
  })
  const common = {
    filter: selected,
    limit: 100,
    with_payload: includePassages ? ['item_id', 'ref', 'text'] : ['item_id', 'ref'],
    with_vector: false,
  }
  const [rawSemantic, lexical] = await Promise.all([
    db.query(collection, {
      ...common,
      limit: 200,
      query: vector,
      params: { exact: true },
    }),
    db.query(collection, {
      ...common,
      filter: {
        must: [...selected.must, { key: 'search_text', match: { text: normalize(input.query) } }],
      },
      query: { text: normalize(input.query) },
      using: 'search_text',
    }),
  ])
  const semantic = rawSemantic
    .sort((a, b) => b.score - a.score || a.id.localeCompare(b.id))
    .slice(0, 100)
  const scores = new Map(semantic.map((p) => [p.id, p.score]))
  const missing = lexical.filter((p) => !scores.has(p.id)).map((p) => p.id)
  if (missing.length) {
    const points = await db.call(`/collections/${collection}/points`, {
      ids: missing,
      with_vector: true,
      with_payload: false,
    })
    for (const p of points) scores.set(p.id, cosine(vector, p.vector))
  }
  const ranked = fuse(semantic, lexical, scores, input.limit)
  return {
    results: ranked.map((p) => ({ ...p.ref, score: p.score })),
    candidates: ranked.map((p) => ({
      id: p.id,
      hit: { ...p.ref, score: p.score },
      text:
        [...semantic, ...lexical].find((point) => point.payload.item_id === p.id)?.payload.text ??
        '',
    })),
    itemIDs: ranked.map((p) => p.id),
    semanticIDs: semantic.map((p) => p.id),
  }
}

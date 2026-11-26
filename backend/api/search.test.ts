import { test, expect } from 'bun:test'
import { Store } from './store.ts'
import { cosine, fuse, filter, retrieve, type Point } from './search.ts'
import { parseRequest } from './core.ts'
import { createHandler } from './server.ts'
import { Qdrant } from './search.ts'
const point = (id: string, item: string): Point => ({
  id,
  score: 0.9,
  payload: { item_id: item, ref: { kind: 'quran', chapter: 2, verse: 1 } },
})
test('cosine is similarity, fusion deduplicates and keeps maximum cosine', () => {
  expect(cosine([1, 0], [0, 1])).toBe(0)
  expect(cosine([1, 0], [-1, 0])).toBe(-1)
  const a = point('a', 'same'),
    b = point('b', 'same'),
    c = point('c', 'other')
  const hits = fuse(
    [a, c],
    [b, a],
    new Map([
      ['a', 0.7],
      ['b', 0.8],
      ['c', 0.6],
    ]),
    20,
  )
  expect(hits).toHaveLength(2)
  expect(hits[0].score).toBe(0.8)
  expect(() => fuse([a], [], new Map(), 20)).toThrow()
})
test('persistent quotas survive restart and expire at window boundary', async () => {
  const path = `${Bun.env.TMPDIR ?? '/tmp'}/search-test-${crypto.randomUUID()}.sqlite`
  try {
    let s = new Store(path)
    expect(s.take('a', 1, 60, 1000)).toBe(true)
    s.db.close()
    s = new Store(path)
    expect(s.take('a', 1, 60, 2000)).toBe(false)
    expect(s.take('a', 1, 60, 60000)).toBe(true)
    s.put('x', { a: 1 }, 60)
    expect(s.get('x')).toEqual({ a: 1 })
    expect(s.get('missing')).toBeUndefined()
    s.db.close()
  } finally {
    await Bun.$`rm -f ${path} ${path}-wal ${path}-shm`.quiet()
  }
})
test('filters and bounded inputs', () => {
  expect(
    filter(parseRequest({ query: 'test', kinds: ['hadith'], sources: ['a'] })).must,
  ).toHaveLength(2)
  expect(() => parseRequest({ query: 'test', limit: 51 })).toThrow()
})
test('direct references skip embedding and provider failure is unavailable', async () => {
  const store = new Store(':memory:')
  const db = new Qdrant('http://unused')
  db.active = async () => 'revision'
  db.call = async () => ({
    points: [point('a', 'item')],
    next_page_offset: null,
  })
  const handler = createHandler(store, db, {
    GEMINI_API_KEY: 'test',
    SEARCH_RATE_SALT: 'test',
  })
  const request = (query: string) =>
    new Request('http://localhost/v1/search', {
      method: 'POST',
      body: JSON.stringify({ query }),
    })
  expect((await handler(request('2:1'), '127.0.0.1')).status).toBe(200)
  expect((await handler(request('2:1'), '192.168.0.1')).status).toBe(403)
  db.active = async () => {
    throw new Error('down')
  }
  expect((await handler(request('new query'), '127.0.0.1')).status).toBe(503)
  store.db.close()
})
test('concurrent embedding misses coalesce and provider failures use the index', async () => {
  const store = new Store(':memory:'),
    db = new Qdrant('http://unused')
  db.active = async () => 'revision'
  db.query = async () => []
  const original = globalThis.fetch
  let calls = 0
  const handler = createHandler(store, db, {
    GEMINI_API_KEY: 'test',
    SEARCH_RATE_SALT: 'test',
  })
  const req = (query: string) =>
    new Request('http://localhost/v1/search', {
      method: 'POST',
      body: JSON.stringify({ query }),
    })
  try {
    globalThis.fetch = Object.assign(
      async () => {
        calls++
        await Bun.sleep(10)
        return Response.json({ embedding: { values: Array(1536).fill(0.1) } })
      },
      { preconnect: original.preconnect },
    )
    const responses = await Promise.all([
      handler(req('same'), '127.0.0.1'),
      handler(req('same'), '127.0.0.1'),
    ])
    expect(responses.map((r) => r.status)).toEqual([200, 200])
    expect(calls).toBe(1)
    globalThis.fetch = Object.assign(async () => new Response('', { status: 503 }), {
      preconnect: original.preconnect,
    })
    expect((await handler(req('failure'), '127.0.0.1')).status).toBe(200)
    db.query = async () => { throw new Error('index unavailable') }
    expect((await handler(req('failure'), '127.0.0.1')).status).toBe(503)
  } finally {
    globalThis.fetch = original
    store.db.close()
  }
})
test('tunnel identity is required and cannot be supplied by a non-loopback peer', async () => {
  const s = new Store(':memory:'),
    db = new Qdrant('http://unused')
  const h = createHandler(s, db, {
    GEMINI_API_KEY: 'test',
    SEARCH_RATE_SALT: 'test',
    SEARCH_TRUST_TUNNEL: 'true',
  })
  const req = () =>
    new Request('http://localhost/v1/search', {
      method: 'POST',
      body: '{"query":"2:1"}',
    })
  expect((await h(req(), '127.0.0.1')).status).toBe(503)
  const r = req()
  r.headers.set('cf-connecting-ip', '1.2.3.4')
  expect((await h(r, '10.0.0.2')).status).toBe(403)
  s.db.close()
})

test('result cache isolates corpus revision and filters', async () => {
  const store = new Store(':memory:'),
    db = new Qdrant('http://unused')
  let revision = 'one',
    calls = 0
  db.active = async () => revision
  db.call = async () => {
    calls++
    return { points: [point('a', 'item')], next_page_offset: null }
  }
  const handler = createHandler(store, db, {
    GEMINI_API_KEY: 'test',
    SEARCH_RATE_SALT: 'test',
  })
  const request = (kinds?: string[]) =>
    new Request('http://localhost/v1/search', {
      method: 'POST',
      body: JSON.stringify({ query: '2:1', kinds }),
    })
  await handler(request(), '127.0.0.1')
  await handler(request(), '127.0.0.1')
  expect(calls).toBe(1)
  revision = 'two'
  await handler(request(), '127.0.0.1')
  expect(calls).toBe(2)
  await handler(request(['quran']), '127.0.0.1')
  expect(calls).toBe(3)
  store.db.close()
})

test('chapter scopes require one hadith volume and constrain both retrieval paths', () => {
  const request = parseRequest({
    query: 'patience',
    kinds: ['hadith'],
    sources: ['alkafi-1'],
    chapter: '1.json',
  })
  expect(filter(request).must).toContainEqual({
    key: 'source_id',
    match: { any: ['alkafi-1'] },
  })
  expect(filter(request).must).toContainEqual({
    key: 'ref.chapter',
    match: { value: '1.json' },
  })
  for (const input of [
    { query: 'x', chapter: '1.json' },
    { query: 'x', kinds: ['quran'], sources: ['quran'], chapter: '1.json' },
    { query: 'x', kinds: ['hadith'], sources: ['a', 'b'], chapter: '1.json' },
    { query: 'x', kinds: ['hadith'], sources: ['a'], chapter: '../1.json' },
  ])
    expect(() => parseRequest(input)).toThrow()
  expect(JSON.stringify(request)).not.toBe(JSON.stringify({ ...request, chapter: '2.json' }))
})

test('Quran chapter scopes validate and filter before every retrieval limit', async () => {
  const input = parseRequest({
    query: 'mercy',
    kinds: ['quran'],
    chapter: '2',
  })
  const chapterFilter = { key: 'ref.chapter', match: { value: 2 } }
  expect(filter(input).must).toContainEqual(chapterFilter)
  expect(parseRequest({ query: 'x', kinds: ['quran'], chapter: '114' }).chapter).toBe('114')
  for (const chapter of ['0', '115', '-1', '2.5', '02', '1.json', 2]) {
    expect(() => parseRequest({ query: 'x', kinds: ['quran'], chapter })).toThrow()
  }
  expect(() => parseRequest({ query: 'x', kinds: ['quran', 'hadith'], chapter: '2' })).toThrow()
  const db = new Qdrant('http://unused')
  const requests: any[] = []
  db.query = async (_, body) => {
    requests.push(body)
    return []
  }
  await retrieve(db, 'test', input, [1, 0], null)
  expect(requests).toHaveLength(2)
  for (const request of requests) expect(request.filter.must).toContainEqual(chapterFilter)
  db.call = async (_, body) => {
    requests.push(body)
    return { points: [], next_page_offset: null }
  }
  await retrieve(db, 'test', input, null, { chapter: 1, verse: 1 })
  expect(requests[2].filter.must).toContainEqual(chapterFilter)
  expect(requests[2].filter.must).toContainEqual({
    key: 'ref.chapter',
    match: { value: 1 },
  })
})

test('short Quran eligibility filters both candidate paths, but not direct lookup', async () => {
  const db = new Qdrant('unused')
  const requests: any[] = []
  db.query = async (_, body) => {
    requests.push(body)
    return []
  }
  db.call = async (_, body) => {
    requests.push(body)
    return { points: [], next_page_offset: null }
  }
  const input = parseRequest({ query: 'patience', kinds: ['quran'] })
  await retrieve(db, 'test', input, [1, 0], null)
  expect(requests).toHaveLength(2)
  for (const request of requests)
    expect(JSON.stringify(request.filter)).toContain('search_eligible')
  requests.length = 0
  await retrieve(db, 'test', input, null, { chapter: 2, verse: 1 })
  expect(JSON.stringify(requests[0].filter)).not.toContain('search_eligible')
})

test('reranking cache separates models, skips references and never caches failures', async () => {
  const store = new Store(':memory:')
  const db = new Qdrant('unused')
  db.active = async () => 'revision'
  const a = point('a', 'item-a'),
    b = point('b', 'item-b')
  b.payload.ref = { kind: 'quran', chapter: 2, verse: 2 }
  db.query = async () => [a, b]
  db.call = async (path) =>
    path.endsWith('/points/scroll')
      ? { points: [a], next_page_offset: null }
      : [
          { id: 'a', payload: { text: 'First passage text' } },
          { id: 'b', payload: { text: 'Second passage text' } },
        ]
  const original = globalThis.fetch
  let calls = 0,
    fail = false
  try {
    globalThis.fetch = Object.assign(
      async (url: any) => {
        if (!String(url).includes('api.typesafe.ai'))
          return Response.json({
            embedding: { values: Array(1536).fill(0.1) },
          })
        calls++
        return fail
          ? new Response('', { status: 503 })
          : Response.json({ answers: { p0: { type: 'noul', noul: .1 }, p1: { type: 'noul', noul: .9 } } })
      },
      { preconnect: original.preconnect },
    )
    const env = {
      GEMINI_API_KEY: 'test',
      SEARCH_RATE_SALT: 'test',
      SEARCH_RERANK_PROVIDER: 'jev',
      JEV_API_KEY: 'test',
      SEARCH_RERANK_MODEL: 'one',
    }
    const request = (query: string) =>
      new Request('http://localhost/v1/search', {
        method: 'POST',
        body: JSON.stringify({ query }),
      })
    const handler = createHandler(store, db, env)
    const result = (await (await handler(request('patience'), '127.0.0.1')).json()) as any
    expect(result.results.map((r: any) => r.verse)).toEqual([2, 1])
    expect(result.results[0].score).toBe(0.9)
    await handler(request('patience'), '127.0.0.1')
    expect(calls).toBe(1)
    const other = createHandler(store, db, {
      ...env,
      SEARCH_RERANK_MODEL: 'two',
    })
    await other(request('patience'), '127.0.0.1')
    expect(calls).toBe(2)
    await other(request('2:1'), '127.0.0.1')
    expect(calls).toBe(2)
    fail = true
    const failed = createHandler(store, db, {
      ...env,
      SEARCH_RERANK_MODEL: 'three',
    })
    expect((await failed(request('patience'), '127.0.0.1')).status).toBe(200)
    fail = false
    const recovered = createHandler(store, db, {
      ...env,
      SEARCH_RERANK_MODEL: 'three',
    })
    await recovered(request('patience'), '127.0.0.1')
    expect(calls).toBe(4)
  } finally {
    globalThis.fetch = original
    store.db.close()
  }
})

test('reranking receives the passage that earned the winning fusion rank', () => {
  const first = point('first', 'same')
  const best = point('best', 'same')
  first.payload.text = 'Unrelated opening passage'
  best.payload.text = 'Relevant passage near the end'
  const result = fuse([first, best], [best], new Map([['first', 0.8], ['best', 0.9]]), 20)
  expect(result[0].text).toBe('Relevant passage near the end')
})

test('bulk retrieval omits passage text, caps semantic at 100, and fetches top-20 text only when requested', async () => {
  const db = new Qdrant('unused')
  const queries: any[] = []
  const pointCalls: any[] = []
  const semanticPoints: Point[] = Array.from({ length: 25 }, (_, i) => ({
    id: `p-${i}`,
    score: i === 0 ? 0.98 : i === 1 ? 1 : 1 - i * 0.01,
    payload: { item_id: `item-${i}`, ref: { kind: 'quran', chapter: 2, verse: i + 1 } },
  }))
  const winningOther: Point = {
    id: 'p-0-win',
    score: 0.9,
    payload: { item_id: 'item-0', ref: { kind: 'quran', chapter: 2, verse: 1 } },
  }
  db.query = async (_, body: any) => {
    queries.push(body)
    return body.using === 'search_text' ? [winningOther] : semanticPoints
  }
  db.call = async (path, body: any) => {
    pointCalls.push({ path, body })
    if (body.with_vector) return [{ id: 'p-0-win', vector: [1, 0] }]
    return body.ids.map((id: string) => ({ id, payload: { text: `text:${id}` } }))
  }

  const input = parseRequest({ query: 'patience', limit: 25 })
  const withoutText = await retrieve(db, 'test', input, [1, 0], null, false)
  expect(queries).toHaveLength(2)
  expect(queries[0].limit).toBe(100)
  expect(queries[0].with_payload).toEqual(['item_id', 'ref'])
  expect(queries[1].with_payload).toEqual(['item_id', 'ref', 'search_text'])
  expect(pointCalls.filter((c) => c.body.with_payload)).toHaveLength(0)
  expect(withoutText.results).toHaveLength(25)
  expect((withoutText.results[0] as any).text).toBeUndefined()

  queries.length = 0
  pointCalls.length = 0
  const withText = await retrieve(db, 'test', input, [1, 0], null, true)
  expect(queries[0].with_payload).toEqual(['item_id', 'ref'])
  expect(queries[1].with_payload).toEqual(['item_id', 'ref', 'search_text'])
  const textFetches = pointCalls.filter((c) => Array.isArray(c.body.with_payload))
  expect(textFetches).toHaveLength(1)
  expect(textFetches[0].body.with_payload).toEqual(['text'])
  expect(textFetches[0].body.ids).toHaveLength(20)
  expect(textFetches[0].body.ids[0]).toBe('p-0-win')
  expect(withText.candidates![0].text).toBe('text:p-0-win')
  expect(withText.candidates![20].text).toBe('')
  expect((withText.results[0] as any).text).toBeUndefined()
})

test('Qdrant active() caches alias within TTL, coalesces concurrent calls, and invalidates on 404', async () => {
  const original = globalThis.fetch
  let now = 1000,
    aliasCalls = 0,
    collection = 'rev-1',
    queryStatus = 200
  try {
    globalThis.fetch = Object.assign(
      async (url: any) => {
        if (String(url).endsWith('/aliases')) {
          aliasCalls++
          await Bun.sleep(5)
          return Response.json({ result: { aliases: [{ alias_name: 'search', collection_name: collection }] } })
        }
        return new Response(queryStatus === 200 ? JSON.stringify({ result: { points: [] } }) : '', {
          status: queryStatus,
        })
      },
      { preconnect: original.preconnect },
    )
    const db = new Qdrant('http://qdrant.local', '', 30_000, () => now)
    expect(await Promise.all([db.active(), db.active()])).toEqual(['rev-1', 'rev-1'])
    expect(aliasCalls).toBe(1)

    now += 10_000
    collection = 'rev-2'
    expect(await db.active()).toBe('rev-1')
    expect(aliasCalls).toBe(1)

    now += 20_001
    expect(await db.active()).toBe('rev-2')
    expect(aliasCalls).toBe(2)

    queryStatus = 404
    await expect(db.query('rev-2', {})).rejects.toThrow('Qdrant HTTP 404')
    collection = 'rev-3'
    expect(await db.active()).toBe('rev-3')
    expect(aliasCalls).toBe(3)
  } finally {
    globalThis.fetch = original
  }
})

test('legacy unscoped searches exclude new kinds before ranking', () => {
  expect(filter(parseRequest({ query: 'test' })).must).toContainEqual({
    key: 'kind', match: { any: ['quran', 'hadith', 'dua', 'rulings'] },
  })
})

test('dense retrieval failures keep scoped keyword hits and null cosine scores', async () => {
  const db = new Qdrant('unused')
  const input = parseRequest({ query: 'patience', kinds: ['quran'], chapter: '2' })
  let failVectorSearch = true
  db.query = async (_, body: any) => {
    expect(body.filter.must).toContainEqual({ key: 'ref.chapter', match: { value: 2 } })
    if (body.using === 'search_text') return [point('lexical', 'item')]
    if (failVectorSearch) throw new Error('dense index unavailable')
    return []
  }
  db.call = async () => { throw new Error('vector read unavailable') }
  for (const fail of [true, false]) {
    failVectorSearch = fail
    const result = await retrieve(db, 'test', input, [1, 0], null)
    expect(result.degraded).toBe(true)
    expect(result.results).toEqual([{ kind: 'quran', chapter: 2, verse: 1, score: null }])
  }
})

test('mixed legacy and figure requests remain isolated through keyword fallback', async () => {
  const store = new Store(':memory:')
  const db = new Qdrant('unused')
  db.active = async () => 'expanded'
  db.query = async (_, body: any) => {
    const kinds = body.filter.must.find((condition: any) => condition.key === 'kind').match.any
    return kinds.includes('figure')
      ? [{ ...point('figure', 'figure'), payload: { item_id: 'figure', ref: { kind: 'figure', id: 'ali' } } }]
      : [point('quran', 'quran')]
  }
  const handler = createHandler(store, db, { SEARCH_RATE_SALT: 'test', SEARCH_IP_PER_MINUTE: '40' })
  try {
    await Promise.all(Array.from({ length: 40 }, async (_, i) => {
      const kinds = i % 2 ? ['figure'] : undefined
      const request = new Request('http://localhost/v1/search', {
        method: 'POST', body: JSON.stringify({ query: 'Ali', kinds }),
      })
      const response = await handler(request, '127.0.0.1')
      expect(response.status).toBe(200)
      const { results } = await response.json() as { results: { kind: string; score: number | null }[] }
      expect(results.map(hit => hit.kind)).toEqual([kinds ? 'figure' : 'quran'])
      expect(results[0].score).toBeNull()
    }))
  } finally {
    store.db.close()
  }
})

test('exhausted embedding budget still reranks keyword hits with Jev', async () => {
  const store = new Store(':memory:')
  store.take('embedding:day', 1, 86400)
  const db = new Qdrant('unused')
  db.active = async () => 'revision'
  const a = point('a', 'a'), b = point('b', 'b')
  b.payload.ref = { kind: 'quran', chapter: 2, verse: 2 }
  db.query = async (_, body: any) => {
    expect(body.using).toBe('search_text')
    return [a, b]
  }
  db.call = async () => [a, b].map(p => ({ id: p.id, payload: { text: 'indexed passage' } }))
  const original = globalThis.fetch
  let reranks = 0
  try {
    globalThis.fetch = Object.assign(async (url: any) => {
      expect(String(url)).toContain('api.typesafe.ai')
      reranks++
      return Response.json({ answers: { p0: { type: 'noul', noul: 0.1 }, p1: { type: 'noul', noul: 0.9 } } })
    }, { preconnect: original.preconnect })
    const handler = createHandler(store, db, {
      GEMINI_API_KEY: 'test', SEARCH_RATE_SALT: 'test', SEARCH_DAILY_EMBEDDING_LIMIT: '1',
      SEARCH_RERANK_PROVIDER: 'jev', JEV_API_KEY: 'test',
    })
    const response = await handler(new Request('http://localhost/v1/search', {
      method: 'POST', body: JSON.stringify({ query: 'patience', kinds: ['quran'] }),
    }), '127.0.0.1')
    expect(response.status).toBe(200)
    expect((await response.json() as any).results).toEqual([
      { ...b.payload.ref, score: null }, { ...a.payload.ref, score: null },
    ])
    expect(reranks).toBe(1)
  } finally {
    store.db.close()
    globalThis.fetch = original
  }
})

test('scattered keyword matches do not outrank meaning, exact phrases do', async () => {
  const db = new Qdrant('unused')
  const scattered = point('scattered', 'scattered'),
    phrase = point('phrase', 'phrase'),
    meaning = point('meaning', 'meaning')
  Object.assign(scattered.payload, { search_text: 'mercy is shown by some people' })
  Object.assign(phrase.payload, { search_text: 'show mercy people said' })
  db.query = async (_, body: any) =>
    body.using === 'search_text'
      ? [{ ...scattered, score: 9 }, { ...phrase, score: 8 }]
      : [{ ...meaning, score: 0.9 }]
  db.call = async () =>
    [scattered, phrase].map((p) => ({ id: p.id, vector: [1, 0] }))
  const found = await retrieve(db, 'test', parseRequest({ query: 'mercy people' }), [1, 0], null)
  expect(found.itemIDs).toEqual(['phrase', 'meaning', 'scattered'])
})

test('tied keyword scores rank the same whatever order Qdrant returns', async () => {
  const db = new Qdrant('unused')
  let flip = false
  db.query = async (_, body: any) => {
    if (body.using !== 'search_text') return []
    const tied = [point('a', 'a'), point('b', 'b')]
    return flip ? tied.reverse() : tied
  }
  db.call = async () => [point('a', 'a'), point('b', 'b')].map((p) => ({ id: p.id, vector: [1, 0] }))
  const run = async () =>
    (await retrieve(db, 'test', parseRequest({ query: 'patience' }), [1, 0], null)).itemIDs
  const first = await run()
  flip = true
  expect(await run()).toEqual(first)
})

test('source scopes fit whole multi-volume collections', () => {
  const sources = Array.from({ length: 256 }, (_, i) => `v-${i}`)
  expect(parseRequest({ query: 'test', sources }).sources).toHaveLength(256)
  expect(() => parseRequest({ query: 'test', sources: [...sources, 'extra'] })).toThrow('Invalid sources')
  expect(() => parseRequest({ query: 'test', languages: sources.slice(0, 21) })).toThrow('Invalid languages')
})

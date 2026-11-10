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
test('concurrent embedding misses coalesce and failures remain unavailable', async () => {
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
    expect((await handler(req('failure'), '127.0.0.1')).status).toBe(503)
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

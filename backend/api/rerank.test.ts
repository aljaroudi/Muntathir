import { expect, test } from 'bun:test'
import { Reranker, type Candidate } from './rerank.ts'

const candidates: Candidate[] = Array.from({ length: 22 }, (_, i) => ({
  id: String(i),
  text: 'نص '.repeat(500),
  hit: { kind: 'quran', chapter: 2, verse: i + 1, score: i / 30 },
}))
const env = {
  SEARCH_RERANK_PROVIDER: 'jev',
  JEV_API_KEY: 'test',
  SEARCH_RERANK_MODEL: 'test',
}
const fake = (fn: (url: any, init: any) => Promise<Response>) =>
  Object.assign(fn, { preconnect: fetch.preconnect }) as typeof fetch
const reply = (ids: unknown) =>
  Response.json({
    answers: Object.fromEntries((Array.isArray(ids) ? ids : []).map((id, i) => [`p${id}`, { type: 'noul', noul: ((ids as unknown[]).length - i) / (ids as unknown[]).length }])) ,
  })

test('reranking bounds input and preserves references, scores and tail', async () => {
  let body: any
  const ranker = new Reranker(
    env,
    fake(async (url, init) => {
      expect(url).toBe('https://api.typesafe.ai/v1/systemone')
      body = JSON.parse(init.body)
      return reply(
        candidates
          .slice(0, 20)
          .map((c) => c.id)
          .reverse(),
      )
    }),
  )
  const result = await ranker.rank('What helps with patience?', candidates)
  expect(result.outcome).toBe('success')
  expect(result.cacheable).toBe(true)
  expect(result.results).toEqual(
    [...candidates.slice(0, 20).reverse(), ...candidates.slice(20)].map((c) => c.hit),
  )
  const data = JSON.parse(body.state)
  expect(data.candidates).toHaveLength(20)
  expect(data.candidates[0].text).toBe(candidates[0].text)
  expect(typeof data.instructions).toBe('string')
  expect(body.questions.p0.instructions).toBe('Evaluate passage "0".')
  expect(body.tools).toBeUndefined()
})

for (const ids of [['0', '0'], ['0', 'unknown'], ['0'], null]) {
  test(`invalid ranking falls back: ${JSON.stringify(ids)}`, async () => {
    const ranker = new Reranker(
      env,
      fake(async () => reply(ids)),
    )
    const result = await ranker.rank('query', candidates.slice(0, 2))
    expect(result.results).toEqual(candidates.slice(0, 2).map((c) => c.hit))
    expect(result.cacheable).toBe(false)
    expect(result.outcome).toBe('failed')
  })
}

test('disabled, bounded concurrency, timeout without cooldown, and failure cooldown preserve baseline', async () => {
  expect((await new Reranker({}).rank('q', candidates)).outcome).toBe('disabled')
  let now = 1000,
    calls = 0
  const gates: (() => void)[] = []
  const concurrentRanker = new Reranker(
    { ...env, SEARCH_RERANK_URL: 'https://custom.rerank.local/v1/systemone' },
    fake(async (url) => {
      expect(url).toBe('https://custom.rerank.local/v1/systemone')
      calls++
      await new Promise<void>((resolve) => gates.push(resolve))
      return reply(candidates.slice(0, 2).map((c) => c.id))
    }),
    () => now,
  )
  const inFlight = Array.from({ length: 4 }, () => concurrentRanker.rank('q', candidates.slice(0, 2)))
  expect((await concurrentRanker.rank('q', candidates.slice(0, 2))).outcome).toBe('busy')
  expect(calls).toBe(4)
  for (const done of gates) done()
  expect((await Promise.all(inFlight)).map((r) => r.outcome)).toEqual([
    'success',
    'success',
    'success',
    'success',
  ])

  calls = 0
  let mode: 'timeout' | 'error' = 'timeout'
  const ranker = new Reranker(
    { ...env, SEARCH_RERANK_TIMEOUT_MS: '10' },
    fake(async (_, init) => {
      calls++
      if (mode === 'timeout') {
        await new Promise((_, reject) => {
          init.signal.addEventListener('abort', () => reject(new Error('timeout')), { once: true })
        })
      }
      return new Response('', { status: 503 })
    }),
    () => now,
  )
  // Timeout falls back without activating 30s cooldown.
  expect((await ranker.rank('q', candidates)).outcome).toBe('failed')
  expect((await ranker.rank('q', candidates)).outcome).toBe('failed')
  expect(calls).toBe(2)

  // HTTP/parse failure activates 30s cooldown.
  mode = 'error'
  expect((await ranker.rank('q', candidates)).outcome).toBe('failed')
  expect((await ranker.rank('q', candidates)).outcome).toBe('cooldown')
  expect(calls).toBe(3)
  now += 30_001
  expect((await ranker.rank('q', candidates)).outcome).toBe('failed')
  expect(calls).toBe(4)
})

test('unavailable service and malformed content are non-fatal', async () => {
  for (const response of [
    new Response('', { status: 503 }),
    Response.json({ choices: [{ message: { content: 'not json' } }] }),
  ]) {
    const ranker = new Reranker(
      env,
      fake(async () => response),
    )
    expect((await ranker.rank('q', candidates)).outcome).toBe('failed')
  }
})

test('exhausted request budget skips optional inference', async () => {
  const ranker = new Reranker(
    env,
    fake(async () => {
      throw new Error('must not call')
    }),
  )
  const result = await ranker.rank('q', candidates, 0)
  expect(result.outcome).toBe('budget')
  expect(result.cacheable).toBe(false)
  expect(result.results).toEqual(candidates.map((c) => c.hit))
})

test('Jev uses pinned model, full winning passages and validates scores', async () => {
  const selected = candidates.slice(0, 2)
  const ranker = new Reranker({ SEARCH_RERANK_PROVIDER: 'jev', JEV_API_KEY: 'test-secret' }, fake(async (url, init) => {
    expect(url).toBe('https://api.typesafe.ai/v1/systemone')
    expect(init.headers.Authorization).toBe('Bearer test-secret')
    const body = JSON.parse(init.body)
    expect(body.model).toBe('jev-1.14.0')
    expect(JSON.parse(body.state).candidates[0].text).toBe(selected[0].text)
    return Response.json({ answers: { p0: { type: 'noul', noul: .1 }, p1: { type: 'noul', noul: .9 } } })
  }))
  expect(JSON.stringify(ranker.config)).not.toContain('test-secret')
  const result = await ranker.rank('query', selected)
  expect(result.outcome).toBe('success')
  expect(result.results).toEqual(selected.toReversed().map(c => c.hit))
  expect(() => new Reranker({ SEARCH_RERANK_PROVIDER: 'jev' })).toThrow('JEV_API_KEY')
  expect(new Reranker({ SEARCH_RERANK_PROVIDER: 'off', JEV_API_KEY: 'test-secret' }).config).toBeNull()
})

test('invalid Jev scores fall back without caching', async () => {
  for (const answers of [{}, { p0: { type: 'noul', noul: 1 }, p1: { type: 'noul', noul: 2 } }]) {
    const ranker = new Reranker({ SEARCH_RERANK_PROVIDER: 'jev', JEV_API_KEY: 'test' }, fake(async () => Response.json({ answers })))
    const result = await ranker.rank('query', candidates.slice(0, 2))
    expect(result.outcome).toBe('failed')
    expect(result.cacheable).toBe(false)
    expect(result.results).toEqual(candidates.slice(0, 2).map(c => c.hit))
  }
})

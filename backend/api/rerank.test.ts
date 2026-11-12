import { expect, test } from 'bun:test'
import { Reranker, type Candidate } from './rerank.ts'

const candidates: Candidate[] = Array.from({ length: 22 }, (_, i) => ({
  id: String(i),
  text: 'نص '.repeat(500),
  hit: { kind: 'quran', chapter: 2, verse: i + 1, score: i / 30 },
}))
const env = {
  SEARCH_RERANK_URL: 'http://localhost:1234/v1',
  SEARCH_RERANK_MODEL: 'test',
}
const fake = (fn: (url: any, init: any) => Promise<Response>) =>
  Object.assign(fn, { preconnect: fetch.preconnect }) as typeof fetch
const reply = (ids: unknown) =>
  Response.json({
    choices: [{ message: { content: JSON.stringify({ ids }) } }],
  })

test('reranking bounds input and preserves references, scores and tail', async () => {
  let body: any
  const ranker = new Reranker(
    env,
    fake(async (url, init) => {
      expect(url).toBe('http://localhost:1234/v1/chat/completions')
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
  const data = JSON.parse(body.messages[1].content)
  expect(data.candidates).toHaveLength(20)
  expect([...data.candidates[0].text]).toHaveLength(1000)
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

test('disabled, busy, timeout and cooldown preserve baseline', async () => {
  expect((await new Reranker({}).rank('q', candidates)).outcome).toBe('disabled')
  let now = 1000,
    calls = 0
  const ranker = new Reranker(
    { ...env, SEARCH_RERANK_TIMEOUT_MS: '10' },
    fake(async (_, init) => {
      calls++
      await new Promise((_, reject) => {
        init.signal.addEventListener('abort', () => reject(new Error('timeout')), { once: true })
      })
      return reply([])
    }),
    () => now,
  )
  const pending = ranker.rank('q', candidates)
  expect((await ranker.rank('q', candidates)).outcome).toBe('busy')
  expect((await pending).outcome).toBe('failed')
  expect((await ranker.rank('q', candidates)).outcome).toBe('cooldown')
  expect(calls).toBe(1)
  now += 30001
  expect((await ranker.rank('q', candidates)).outcome).toBe('failed')
  expect(calls).toBe(2)
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

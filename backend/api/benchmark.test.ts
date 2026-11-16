import { test, expect } from 'bun:test'
import { request, ranking, metrics, estimate, apiKey } from './benchmark.ts'
const q = { id: 'test', query: 'kindness', split: 'heldout', language: 'en', review_status: 'pending', relevant: { a: 3, b: 0 }, candidates: [{ id: 'a', text: 'Kindness' }, { id: 'b', text: 'Unrelated' }] }
test('provider requests contain identical full passages, no judgments', () => {
  for (const p of ['openai', 'jev', 'gemini'] as const) {
    const body = JSON.stringify(request(p, 'model', q).body)
    expect(body).toContain('Kindness')
    expect(body).toContain('Unrelated')
    expect(body).not.toContain('review_status')
    expect(body).not.toContain('heldout')
  }
})
test('decision scores validate and preserve stable ties', () => {
  expect(ranking('openai', { answers: [{ name: 'p1', type: 'predicate', probability: .5 }, { name: 'p0', type: 'predicate', probability: .5 }] }, q)).toEqual(['a', 'b'])
  expect(ranking('jev', { answers: { p0: { type: 'noul', noul: .2 }, p1: { type: 'noul', noul: .8 } } }, q)).toEqual(['b', 'a'])
  for (const answers of [[], [{ name: 'p0', type: 'refusal' }], [{ name: 'p0', type: 'predicate', probability: 2 }, { name: 'p1', type: 'predicate', probability: 0 }]]) expect(() => ranking('openai', { answers }, q)).toThrow()
})
test('Gemini rejects missing, duplicated, invented and truncated references', () => {
  const payload = (ids: string[], finishReason = 'STOP') => ({ candidates: [{ finishReason, content: { parts: [{ text: JSON.stringify({ ids }) }] } }] })
  expect(ranking('gemini', payload(['b', 'a']), q)).toEqual(['b', 'a'])
  for (const ids of [['a'], ['a', 'a'], ['a', 'fake']]) expect(() => ranking('gemini', payload(ids), q)).toThrow()
  expect(() => ranking('gemini', payload(['a', 'b'], 'MAX_TOKENS'), q)).toThrow()
})
test('metrics exclude explicit negatives from recall and expose unjudged results', () => {
  expect(metrics(['a', 'b', 'c'], q.relevant)).toEqual({ ndcg_at_10: 1, top_result_accuracy: 1, candidate_recall: 1, unjudged_at_10: 1 })
  expect(metrics(['b'], { b: 0 }).ndcg_at_10).toBeNull()
})
test('estimation is offline, validates rates and counts every request', () => {
  const one = estimate('jev', 'model', [q], 1, 2)
  const two = estimate('jev', 'model', [q, q], 1, 2)
  expect(two.estimated_usd).toBe(one.estimated_usd * 2)
  expect(one.requests).toBe(1)
  expect(() => estimate('openai', 'model', [q], NaN, 0)).toThrow()
})
test('CLI dry run works without keys; paid flags and pricing fail before requests', async () => {
  const { mkdtemp, writeFile, rm } = await import('node:fs/promises')
  const { tmpdir } = await import('node:os')
  const { join } = await import('node:path')
  const dir = await mkdtemp(join(tmpdir(), 'rerank-benchmark-'))
  try {
    const snapshot = join(dir, 'snapshot.json'), config = join(dir, 'config.json'), output = join(dir, 'results.jsonl')
    await writeFile(snapshot, JSON.stringify({ cases: [q] }))
    await writeFile(config, JSON.stringify([{ provider: 'openai', model: 'test', timeout_ms: 2000, input_usd_per_million: null, output_usd_per_million: null }]))
    const run = (args: string[]) => Bun.spawnSync([process.execPath, `${import.meta.dir}/benchmark.ts`, ...args], { env: { PATH: process.env.PATH ?? '' } })
    const dry = run(['dry-run', snapshot, config])
    expect(dry.exitCode).toBe(0)
    expect(JSON.parse(dry.stdout.toString()).plan[0].estimate.estimated_usd).toBeNull()
    expect(run(['run', snapshot, config, output]).stderr.toString()).toContain('requires --execute')
    expect(run(['run', snapshot, config, output, '--execute']).stderr.toString()).toContain('Fill current pricing')
    expect(await Bun.file(output).exists()).toBe(false)
  } finally { await rm(dir, { recursive: true, force: true }) }
})

test('Jev accepts project key name and vendor alias', () => {
  expect(apiKey('jev', { JEV_API_KEY: 'project', TYPESAFE_API_KEY: 'vendor' })).toBe('project')
  expect(apiKey('jev', { TYPESAFE_API_KEY: 'vendor' })).toBe('vendor')
  expect(apiKey('jev', {})).toBeUndefined()
})

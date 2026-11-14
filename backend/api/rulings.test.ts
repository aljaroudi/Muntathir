import { test, expect } from 'bun:test'
import { parseRequest } from './core.ts'
import { filter, fuse, type Point } from './search.ts'

test('rulings scope filters authority and language before ranking', () => {
  const input = parseRequest({ query: 'الصلاة', kinds: ['rulings'], sources: ['sistani'], languages: ['ar'] })
  expect(filter(input).must).toEqual([
    { key: 'kind', match: { any: ['rulings'] } },
    { key: 'source_id', match: { any: ['sistani'] } },
    { key: 'language', match: { any: ['ar'] } },
  ])
  expect(() => parseRequest({ query: 'test', kinds: ['rulings'], chapter: '1' })).toThrow()
})

test('rulings passage collapse retains the complete source reference', () => {
  const ref = { kind: 'rulings' as const, authority: 'sistani', language: 'ar', id: '42' }
  const points: Point[] = ['a', 'b'].map(id => ({ id, score: 0.8, payload: { item_id: 'stable', ref, text: id } }))
  const result = fuse(points, [], new Map([['a', 0.8], ['b', 0.7]]), 20)
  expect(result).toHaveLength(1)
  expect(result[0].ref).toEqual(ref)
})

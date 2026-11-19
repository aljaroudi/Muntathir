import { test } from 'bun:test'
import { normalize, parseRequest, reference, validVector } from './core.ts'
function assert(value: unknown) {
  if (!value) throw new Error('Assertion failed')
}
test('bounded filters and defaults', () => {
  assert(parseRequest({ query: '  patience  ' }).limit === 20)
  for (const value of [
    { query: '' },
    { query: 'a', limit: 51 },
    { query: 'a', kinds: ['other'] },
    { query: 'a', sources: [] },
    { query: 'a', p_exact: true },
  ]) {
    let failed = false
    try {
      parseRequest(value)
    } catch {
      failed = true
    }
    assert(failed)
  }
})
test('references avoid provider calls across numeral scripts', () => {
  assert(reference('٢:٢٥٥')?.verse === 255)
  assert(reference('۲:۲۵۵')?.chapter === 2)
  assert(reference('bukhari, 1')?.number === '1')
  assert(reference('kindness to neighbours') === null)
  assert(reference('mercy, patience') === null)
  let failed = false
  try {
    reference('115:1')
  } catch {
    failed = true
  }
  assert(failed)
})
test('Arabic normalization and vector validation', () => {
  assert(normalize('إِنَّـمَا') === normalize('انما'))
  assert(validVector(Array(1536).fill(0.1)))
  assert(!validVector(Array(3072).fill(0.1)))
  assert(!validVector(Array(1536).fill(0)))
  assert(!validVector(Array(1536).fill(Infinity)))
})

test('common Arabic phrases yield to topical terms unless sought explicitly', () => {
  for (const phrase of ['صلى الله عليه وآله وسلم', 'صلى الله عليه وسلم', 'عز وجل', 'جل جلاله', 'عليه السلام', 'قَالَ', 'مِنْ', 'من', 'بن', 'ابن']) {
    assert(parseRequest({ query: phrase + ' الصبر' }).query === 'الصبر')
    assert(parseRequest({ query: phrase }).query === phrase)
  }
  for (const query of ['علي بن الحسين', 'مقال', 'منزلة الصبر', '2:255']) assert(parseRequest({ query }).query === query)
  assert(parseRequest({ query: '"قال الصبر"' }).query === 'قال الصبر')
  assert(parseRequest({ query: '"من كنت مولاه"' }).query === 'من كنت مولاه')
})

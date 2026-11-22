import { Database } from 'bun:sqlite'
import { describe, expect, test } from 'bun:test'
import { existsSync } from 'node:fs'
import { resolve } from 'node:path'
import { split, excerpt } from '../src/core/text.ts'
import { Content, PAGE_SIZE } from '../src/server/content.ts'
import { isPublicID, publicID } from '../src/server/ids.ts'
import { toHTML, toPlain } from '../src/server/markdown.ts'

const directory = resolve(import.meta.dir, '../.data')
const installed = existsSync(`${directory}/rulings.db`)
if (!installed) console.warn('Skipping content tests: run `bun scripts/data.ts` first')

describe.if(installed)('content', () => {
  const content = installed ? new Content(directory) : (null as never)
  const open = (name: string) => new Database(`${directory}/${name}.db`, { readonly: true })
  const hadith = () => open('hadith')
  const rulings = () => open('rulings')

  test('Quran', () => {
    expect(content.surahs.reduce((sum, surah) => sum + surah.verses, 0)).toBe(6236)
    expect(content.surah(1)!.basmala).toBeUndefined()
    expect(content.surah(9)!.basmala).toBeUndefined()
    expect(content.surah(112)!.basmala).toBe(content.surah(1)!.items[0]!.text.ar)
    expect(content.surah(112, 1)!.basmala).toBeUndefined()
    expect(content.surah(115)).toBeNull()
    for (let index = 0; index < 360; index++) expect(content.dailyVerse(index)!.text.en).not.toBe('')
    expect(content.dailyVerse(360)).toBeNull()
  })

  test('every surah pages through all of its verses', () => {
    for (const surah of content.surahs) {
      let after: number | undefined = 0
      let count = 0
      while (after !== undefined) {
        const page: any = content.surah(surah.number, after)
        count += page.items.length
        after = page.next
      }
      expect(count).toBe(surah.verses)
    }
  })

  test('every collection, chapter and narration is reachable', () => {
    const db = hadith()
    const expected = db.query<{ n: number }, []>('SELECT count(*) AS n FROM hadith').get()!.n
    let count = 0
    for (const collection of content.collections) {
      for (const book of content.contents(collection.id)!.books) {
        for (const chapter of book.chapters) {
          expect(chapter.name.ar).not.toBe('')
          let after: number | undefined
          do {
            const page: any = content.chapter(chapter.id, after)
            expect(page.items.length).toBeLessThanOrEqual(PAGE_SIZE)
            count += page.items.length
            after = page.next
          } while (after !== undefined)
        }
      }
    }
    expect(count).toBe(expected)
  }, 120_000)

  test('the longest narration renders, and its preview stays short', () => {
    const row = hadith()
      .query<{ book: string; file: string; number: number }, []>(
        `SELECT h.book_id AS book, c.file_name AS file, h.id_in_book AS number
         FROM hadith h JOIN chapter c ON c.id = h.chapter_id ORDER BY length(h.arabic) DESC LIMIT 1`,
      )
      .get()!
    const id = publicID('hadith', row.book, row.file, row.number)
    expect(content.narration(id)!.html.ar.length).toBeGreaterThan(300_000)
    const [preview] = content.hydrate([{ kind: 'hadith', book: row.book, chapter: row.file, number: row.number }])
    expect(preview!.id).toBe(id)
    expect([...preview!.text.ar].length).toBeLessThanOrEqual(221)
  })

  test('Wasail numbers narrations by source ID', () => {
    const row = hadith()
      .query<{ book: string; file: string; number: number; source: number }, []>(
        `SELECT h.book_id AS book, c.file_name AS file, h.id_in_book AS number, h.source_id AS source
         FROM hadith h JOIN chapter c ON c.id = h.chapter_id
         WHERE h.book_id LIKE 'openiti-wasail%' AND h.source_id != h.id_in_book LIMIT 1`,
      )
      .get()!
    const found = content.narration(publicID('hadith', row.book, row.file, row.number))!
    expect(found.title.ar).toEndWith(` · ${row.source}`)
  })

  test('only judgments with content are shown as gradings', () => {
    const row = hadith()
      .query<{ book: string; file: string; number: number }, []>(
        `SELECT h.book_id AS book, c.file_name AS file, h.id_in_book AS number
         FROM hadith_grading g JOIN hadith h ON h.id = g.hadith_id JOIN chapter c ON c.id = h.chapter_id
         WHERE g.status = 'judgment' LIMIT 1`,
      )
      .get()!
    const { gradings } = content.narration(publicID('hadith', row.book, row.file, row.number))!
    expect(gradings.length).toBeGreaterThan(0)
    for (const grading of gradings) expect(grading.grade.ar).not.toBe('')
  })

  test('introductions open', () => {
    let count = 0
    for (const collection of content.collections) {
      const { introduction } = content.contents(collection.id)!
      if (!introduction) continue
      count++
      expect(content.narration(introduction.id)!.kind).toBe('introduction')
    }
    expect(count).toBeGreaterThan(0)
  })

  test('supplications keep attribution and license', () => {
    const list = content.supplicationList()
    expect(list).toHaveLength(57)
    let translations = 0
    for (const item of list) {
      const found = content.supplication(item.id)!
      expect(found.title.ar).not.toBe('')
      for (const translation of found.translations) {
        translations++
        expect(translation.attribution).not.toBe('')
        expect(translation.license).not.toBe('')
      }
    }
    expect(translations).toBe(5)
  })

  test('every ruling placement is reachable from the contents', () => {
    const db = rulings()
    const expected = db.query<{ n: number }, []>('SELECT count(*) AS n FROM placement').get()!.n
    let count = 0
    const seen = new Set<string>()
    const visit = (id: string) => {
      if (seen.has(id)) return
      seen.add(id)
      let after: number | undefined
      do {
        const page: any = content.topic(id, after)
        for (const topic of page.topics) visit(topic.id)
        count += page.items.length
        after = page.next
      } while (after !== undefined)
    }
    for (const authority of content.authorities)
      for (const language of authority.languages)
        for (const topic of content.rulingContents(authority.code, language.code)!) visit(topic.id)
    expect(count).toBe(expected)
  }, 300_000)

  test('every ruling reference hydrates, and footnotes come along', () => {
    const db = rulings()
    const rows = db
      .query<{ authority: string; language: string; id: string }, []>(
        'SELECT authority_code AS authority, language_code AS language, site_id AS id FROM entry',
      )
      .all()
    for (let start = 0; start < rows.length; start += 1000) {
      const chunk = rows.slice(start, start + 1000)
      expect(content.hydrate(chunk.map(row => ({ kind: 'rulings', ...row })))).toHaveLength(chunk.length)
    }
    const noted = db
      .query<{ authority: string; language: string; id: string }, []>(
        `SELECT e.authority_code AS authority, e.language_code AS language, e.site_id AS id
         FROM footnote f JOIN entry e ON e.id = f.entry_id LIMIT 1`,
      )
      .get()!
    const found = content.ruling(publicID('ruling', noted.authority, noted.language, noted.id))!
    expect(found.footnotes.some(note => !note.chapter)).toBe(true)
  }, 120_000)

  test('ruling previews say where they sit', () => {
    const row = rulings()
      .query<{ authority: string; language: string; id: string; context: string }, []>(
        `SELECT authority_code AS authority, language_code AS language, site_id AS id, context
         FROM entry WHERE language_code = 'fa' LIMIT 1`,
      )
      .get()!
    expect(content.hydrate([{ kind: 'rulings', ...row }])[0]!.context).toBe(row.context)
  })

  test('unresolvable references are dropped', () => {
    expect(
      content.hydrate([
        null,
        'x',
        { kind: 'quran', chapter: 115, verse: 1 },
        { kind: 'hadith', book: 'none', chapter: '1.json', number: 1 },
        { kind: 'dua', id: '1' },
        { kind: 'rulings', authority: 'none', language: 'ar', id: '1' },
        { kind: 'figure', id: 'someone' },
      ]),
    ).toEqual([])
    expect(content.hydrate([{ kind: 'quran', chapter: 2, verse: 255 }, { kind: 'quran', chapter: 2, verse: 255 }]))
      .toHaveLength(1)
  })

  test('IDs fit a Telegram button', () => {
    const id = content.surah(1)!.items[0]!.id
    expect(isPublicID(id)).toBe(true)
    expect(Buffer.byteLength(`o:${id}`)).toBeLessThanOrEqual(64)
    for (const wrong of ['', 'q', `${id}x`, "q' OR 1=1 --_____", '../../../../../../x']) {
      expect(isPublicID(wrong)).toBe(false)
      expect(content.narration(wrong)).toBeNull()
    }
  })
})

describe('text', () => {
  test('markup in scraped text stays inert', () => {
    const html = toHTML('<script>x()</script> [1](https://example.com) ![i](https://example.com/i.png) **b**')
    for (const tag of ['<script', '<a ', '<img']) expect(html).not.toContain(tag)
    expect(html).toContain('<strong>b</strong>')
    expect(toHTML('    indented')).not.toContain('<code>')
  })

  test('plain text joins soft breaks and keeps list markers', () => {
    expect(toPlain('one\ntwo\n\n- three\n\n3. four\n4. five')).toBe('one two\n\n• three\n\n3. four\n\n4. five')
  })

  test('split respects the limit and loses nothing', () => {
    const source = 'كلمة '.repeat(3000) + '😀'.repeat(3000)
    const parts = split(source, 4096)
    for (const part of parts) {
      expect(part.length).toBeLessThanOrEqual(4096)
      expect(part.isWellFormed()).toBe(true)
    }
    expect(parts.join('').replaceAll(' ', '')).toBe(source.replaceAll(' ', ''))
    expect(excerpt('a  b\nc')).toBe('a b c')
  })
})

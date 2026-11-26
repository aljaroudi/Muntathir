import { Database, type SQLQueryBindings } from 'bun:sqlite'
import dailyIDs from '../../../apple/Muntathir/Resources/quran-daily-ids.json'
import surahNames from '../../../apple/Muntathir/Resources/quran-surahs.json'
import { excerpt, httpsURL } from '../core/text.ts'
import type * as T from '../core/types.ts'
import { Index } from './ids.ts'
import { toHTML, toPlain } from './markdown.ts'

export const PAGE_SIZE = 50
export const DATABASES = ['quran', 'en.qarai', 'hadith', 'supplications', 'rulings'] as const

const HADITH_APP_ID = 1_230_262_606
const RULINGS_APP_ID = 1_179_809_601
/** Long texts are cut before parsing, as in the apps' previews. */
const PREVIEW_SOURCE = 700

// The readers mirror HadithReader.swift and RulingsReader.swift. These two collections number
// narrations by their printed source ID.
const SOURCE_NUMBERED = ['openiti-wasail', 'openiti-bihar']
const SAHIFA = 'openiti-Sahifa-Sajjadiyya'
// HadithBookGroup in Hadith.swift.
const FOUR = ['alkafi', 'additional-Man-La-Yahduruh-al-Faqih-Saduq', 'additional-Tahdhib-al-Ahkam-Tusi', 'additional-Al-Istibsar-Tusi']
const SIX = ['bukhari', 'muslim', 'abudawud', 'tirmidhi', 'nasai', 'ibnmajah']

export function collectionGroup(id: string): T.CollectionGroup {
  return SIX.includes(id) ? 'six' : FOUR.includes(id) ? 'four' : 'other'
}

type Row<K extends string, V = string> = Record<K, V>
type HadithRow = {
  id: number
  collection: string
  collection_ar: string
  collection_en: string
  book_ar: string
  book_en: string
  chapter_ar: string
  chapter_en: string
  number: number
  source_id: number | null
  display_number: number | null
  arabic: string
  narrator: string
  english: string
}
type IntroductionRow = {
  id: number
  title: string
  arabic: string
  english: string
  url: string
  book_ar: string
  book_en: string
  collection_ar: string
  collection_en: string
  author: string
  author_ar: string
}
type QuestionRow = { id: number; question: string; answer: string; kind: string; context: string }

const HADITH_JOINS = `FROM hadith h
  JOIN book b ON b.id = h.book_id
  JOIN chapter c ON c.id = h.chapter_id
  JOIN collection l ON l.id = b.collection_id
  LEFT JOIN hadith_reading r ON r.hadith_id = h.id`
const hadithColumns = (body: (column: string) => string) => `h.id, b.collection_id AS collection,
  l.name_ar AS collection_ar, l.name_en AS collection_en, b.name_ar AS book_ar, b.name_en AS book_en,
  c.name_ar AS chapter_ar, c.name_en AS chapter_en, h.id_in_book AS number, h.source_id,
  r.display_number, ${body('h.arabic')} AS arabic, ${body('h.english_narrator')} AS narrator,
  ${body('h.english_text')} AS english`
const FULL = hadithColumns(column => column)
const SHORT = hadithColumns(column => `substr(${column}, 1, ${PREVIEW_SOURCE})`)

function text(arabic: string, english: string): T.Text {
  return { ar: arabic, en: english }
}
function localized(arabic: string, english: string): T.Text {
  return { ar: arabic || english, en: english || arabic }
}
function bookName(collection: string, book: string): string {
  return collection === book || !collection ? book : `${collection} · ${book}`
}
function hadithBook(row: HadithRow): T.Text {
  return localized(bookName(row.collection_ar, row.book_ar), bookName(row.collection_en, row.book_en))
}
function displayNumber(row: HadithRow): number | null {
  return SOURCE_NUMBERED.includes(row.collection) ? row.source_id : (row.display_number ?? row.number)
}
function hadithTitle(row: HadithRow): T.Text {
  const book = hadithBook(row)
  const number = displayNumber(row)
  return number == null ? book : { ar: `${book.ar} · ${number}`, en: `${book.en} · ${number}` }
}
function questionPreview(row: QuestionRow): string {
  return row.kind === 'qa' ? row.question : [row.question, row.answer].filter(Boolean).join(' · ')
}
function paged<R, O>(rows: R[], map: (row: R) => O, cursor: (row: R) => number): T.Page<O> {
  const shown = rows.slice(0, PAGE_SIZE)
  return {
    items: shown.map(map),
    ...(rows.length > PAGE_SIZE ? { next: cursor(shown.at(-1)!) } : {}),
  }
}

export class Content {
  private readonly quran: Database
  private readonly qarai: Database
  private readonly hadith: Database
  private readonly supplications: Database
  private readonly rulings: Database

  private readonly verseIDs = new Index('verse')
  private readonly hadithIDs = new Index('hadith')
  private readonly duaIDs = new Index('dua')
  private readonly rulingIDs = new Index('ruling')
  private readonly chapterIDs = new Index('chapter')
  private readonly topicIDs = new Index('topic')
  private readonly introductionIDs = new Index('introduction')

  readonly surahs: T.Surah[]
  readonly collections: T.Collection[]
  readonly authorities: T.Authority[]
  private readonly basmala: string

  constructor(directory: string) {
    const open = (name: (typeof DATABASES)[number]) =>
      new Database(`${directory}/${name}.db`, { readonly: true, strict: true })
    this.quran = open('quran')
    this.qarai = open('en.qarai')
    this.hadith = open('hadith')
    this.supplications = open('supplications')
    this.rulings = open('rulings')
    this.expect(this.hadith, HADITH_APP_ID, 8)
    this.expect(this.supplications, HADITH_APP_ID, 8)
    this.expect(this.rulings, RULINGS_APP_ID, 2)
    this.buildIndexes()

    const counts = this.all<{ sura: number; count: number }>(
      this.quran,
      'SELECT sura, count(*) AS count FROM quran GROUP BY sura ORDER BY sura',
    )
    if (counts.length !== 114 || surahNames.length !== 114) throw new Error('Incomplete Quran')
    this.surahs = surahNames.map((surah, index) => ({
      number: surah.id,
      name: text(surah.arabic, surah.transliteration),
      verses: counts[index]!.count,
    }))
    // Tanzil's text is never edited; the first verse is the basmala itself.
    this.basmala = this.get<Row<'text'>>(
      this.quran,
      'SELECT text FROM quran WHERE sura = 1 AND aya = 1',
    )!.text.trim()
    if (dailyIDs.length !== 360 || !dailyIDs.every(id => this.verseAt(id)))
      throw new Error('Incomplete daily verses')

    this.collections = this.all<{ id: string; name_ar: string; name_en: string; count: number }>(
      this.hadith,
      `SELECT l.id, l.name_ar, l.name_en, count(*) AS count
       FROM collection l JOIN book b ON b.collection_id = l.id JOIN hadith h ON h.book_id = b.id
       WHERE l.id NOT IN ('${SAHIFA}', 'mafatih-supplications')
       GROUP BY l.id ORDER BY l.sort_order, l.id`,
    ).map(row => ({ id: row.id, name: localized(row.name_ar, row.name_en), count: row.count, group: collectionGroup(row.id) }))

    const languages = this.all<{
      authority: string
      code: string
      name: string
      direction: string
      count: number
    }>(
      this.rulings,
      `SELECT e.authority_code AS authority, l.code, l.name, l.direction, count(*) AS count
       FROM entry e JOIN language l ON l.code = e.language_code
       GROUP BY e.authority_code, l.code ORDER BY l.code`,
    )
    this.authorities = this.all<{ code: string; name_ar: string; name_en: string }>(
      this.rulings,
      'SELECT code, name_ar, name_en FROM authority ORDER BY sort_order',
    ).map(authority => ({
      code: authority.code,
      name: localized(authority.name_ar, authority.name_en),
      languages: languages
        .filter(language => language.authority === authority.code)
        .map(({ code, name, direction, count }) => ({ code, name, rtl: direction === 'rtl', count })),
    }))
  }

  close() {
    for (const db of [this.quran, this.qarai, this.hadith, this.supplications, this.rulings]) db.close()
  }

  private all<R>(db: Database, sql: string, ...values: SQLQueryBindings[]): R[] {
    return db.query<R, SQLQueryBindings[]>(sql).all(...values)
  }

  private get<R>(db: Database, sql: string, ...values: SQLQueryBindings[]): R | null {
    return db.query<R, SQLQueryBindings[]>(sql).get(...values)
  }

  private expect(db: Database, application: number, version: number) {
    const found = {
      ...this.get<Row<'application_id', number>>(db, 'PRAGMA application_id'),
      ...this.get<Row<'user_version', number>>(db, 'PRAGMA user_version'),
    }
    if (found.application_id !== application || found.user_version !== version)
      throw new Error('Incompatible content database')
  }

  private buildIndexes() {
    for (const row of this.all<Row<'id' | 'sura' | 'aya', number>>(
      this.quran,
      'SELECT "index" AS id, sura, aya FROM quran',
    ))
      this.verseIDs.add(row.id, row.sura, row.aya)

    // file_name isn't a chapter key, but book + file + number is unique for narrations.
    const narrations = `SELECT h.id, h.book_id AS book, c.file_name AS file, h.id_in_book AS number
      FROM hadith h JOIN chapter c ON c.id = h.chapter_id`
    type Key = { id: number; book: string; file: string; number: number }
    for (const row of this.all<Key>(this.hadith, narrations))
      this.hadithIDs.add(row.id, row.book, row.file, row.number)
    for (const row of this.all<Key>(this.supplications, `${narrations} WHERE c.chapter_idx > 0`))
      this.duaIDs.add(row.id, row.book, row.file, row.number)

    for (const row of this.all<{ id: number; book: string; position: number }>(
      this.hadith,
      'SELECT id, book_id AS book, chapter_idx AS position FROM chapter',
    ))
      this.chapterIDs.add(row.id, row.book, row.position)
    for (const row of this.all<{ id: number; book: string; position: number; title: string }>(
      this.hadith,
      'SELECT id, book_id AS book, sort_order AS position, title FROM introduction',
    ))
      this.introductionIDs.add(row.id, row.book, row.position, row.title)

    type Ruling = { id: number; authority: string; language: string; site: string }
    const rulingKey = 'SELECT id, authority_code AS authority, language_code AS language, site_id AS site'
    for (const row of this.all<Ruling>(this.rulings, `${rulingKey} FROM entry`))
      this.rulingIDs.add(row.id, row.authority, row.language, row.site)
    for (const row of this.all<Ruling>(this.rulings, `${rulingKey} FROM topic`))
      this.topicIDs.add(row.id, row.authority, row.language, row.site)
  }

  // Quran

  private verseAt(index: number): T.Verse | null {
    const row = this.get<{ sura: number; aya: number; text: string }>(
      this.quran,
      'SELECT sura, aya, text FROM quran WHERE "index" = ?',
      index,
    )
    if (!row) return null
    const english = this.get<Row<'text'>>(this.qarai, 'SELECT text FROM quran WHERE "index" = ?', index)
    const name = surahNames[row.sura - 1]!
    return {
      id: this.verseIDs.id(index),
      surah: row.sura,
      number: row.aya,
      name: text(name.arabic, name.transliteration),
      text: text(row.text.trim(), english?.text.trim() ?? ''),
    }
  }

  verse(id: string): T.Verse | null {
    const row = this.verseIDs.row(id)
    return row === undefined ? null : this.verseAt(row)
  }

  /** [index] is the position in quran-daily-ids.json. */
  dailyVerse(index: number): T.Verse | null {
    const id = dailyIDs[index]
    return id === undefined ? null : this.verseAt(id)
  }

  surah(number: number, after = 0): T.SurahPage | null {
    const surah = this.surahs[number - 1]
    if (!surah) return null
    const rows = this.all<{ id: number; aya: number }>(
      this.quran,
      'SELECT "index" AS id, aya FROM quran WHERE sura = ? AND aya > ? ORDER BY aya LIMIT ?',
      number,
      after,
      PAGE_SIZE + 1,
    )
    return {
      surah,
      ...(after === 0 && number !== 1 && number !== 9 ? { basmala: this.basmala } : {}),
      ...paged(rows, row => this.verseAt(row.id)!, row => row.aya),
    }
  }

  // Hadith

  contents(id: string): T.CollectionContents | null {
    const collection = this.collections.find(item => item.id === id)
    if (!collection) return null
    const rows = this.all<{
      id: number
      book: string
      book_ar: string
      book_en: string
      name_ar: string
      name_en: string
      count: number
    }>(
      this.hadith,
      `SELECT c.id, b.id AS book, b.name_ar AS book_ar, b.name_en AS book_en,
         c.name_ar, c.name_en, c.hadith_count AS count
       FROM chapter c JOIN book b ON b.id = c.book_id
       WHERE c.hadith_count > 0 AND b.collection_id = ?
       ORDER BY b.sort_order, c.chapter_idx, c.id`,
      id,
    )
    const books = new Map<string, T.Book>()
    for (const row of rows) {
      let book = books.get(row.book)
      if (!book) {
        book = { id: row.book, name: localized(row.book_ar, row.book_en), chapters: [] }
        books.set(row.book, book)
      }
      const name = localized(row.name_ar, row.name_en)
      book.chapters.push({
        id: this.chapterIDs.id(row.id),
        name: name.ar ? name : book.name,
        count: row.count,
      })
    }
    // Like the apps, a collection lists only its first introduction.
    const first = this.get<IntroductionRow>(
      this.hadith,
      `${INTRODUCTION} WHERE b.collection_id = ? ORDER BY b.sort_order, i.sort_order, i.id LIMIT 1`,
      id,
    )
    return {
      collection,
      ...(first ? { introduction: this.introductionPreview(first) } : {}),
      books: [...books.values()],
    }
  }

  chapter(id: string, after?: number): T.ChapterPage | null {
    const chapter = this.chapterIDs.row(id)
    if (chapter === undefined) return null
    const head = this.get<{ name_ar: string; name_en: string; book_ar: string; book_en: string }>(
      this.hadith,
      `SELECT c.name_ar, c.name_en, b.name_ar AS book_ar, b.name_en AS book_en
       FROM chapter c JOIN book b ON b.id = c.book_id WHERE c.id = ?`,
      chapter,
    )!
    const rows = this.all<HadithRow>(
      this.hadith,
      `SELECT ${SHORT} ${HADITH_JOINS} WHERE h.chapter_id = ? AND h.id > ? ORDER BY h.id LIMIT ?`,
      chapter,
      after ?? Number.MIN_SAFE_INTEGER,
      PAGE_SIZE + 1,
    )
    const book = localized(head.book_ar, head.book_en)
    const title = localized(head.name_ar, head.name_en)
    return {
      title: title.ar ? title : book,
      book,
      ...paged(rows, row => this.hadithPreview(row), row => row.id),
    }
  }

  private hadithPreview(row: HadithRow): T.Preview {
    return {
      id: this.hadithIDs.id(row.id),
      kind: 'hadith',
      title: hadithTitle(row),
      text: text(excerpt(toPlain(row.arabic)), excerpt(toPlain(`${row.narrator} ${row.english}`.trim()))),
    }
  }

  private introductionPreview(row: IntroductionRow): T.Preview {
    const book = localized(bookName(row.collection_ar, row.book_ar), bookName(row.collection_en, row.book_en))
    return {
      id: this.introductionIDs.id(row.id),
      kind: 'introduction',
      title: row.title ? text(row.title, row.title) : book,
      text: text(
        excerpt(toPlain(row.arabic.slice(0, PREVIEW_SOURCE))),
        excerpt(toPlain(row.english.slice(0, PREVIEW_SOURCE))),
      ),
    }
  }

  /** The text of a narration as stored, for chat. */
  narrationText(id: string): { title: T.Text; arabic: string; english: string; url?: string } | null {
    const row = this.hadithIDs.row(id)
    if (row === undefined) return null
    const found = this.get<HadithRow & { url: string }>(
      this.hadith,
      `SELECT ${FULL}, h.url ${HADITH_JOINS} WHERE h.id = ?`,
      row,
    )!
    return {
      title: hadithTitle(found),
      arabic: toPlain(found.arabic),
      english: [found.narrator, toPlain(found.english)].filter(Boolean).join('\n\n'),
      url: httpsURL(found.url),
    }
  }

  narration(id: string): T.Narration | null {
    const introduction = this.introductionIDs.row(id)
    if (introduction !== undefined) {
      const row = this.get<IntroductionRow>(this.hadith, `${INTRODUCTION} WHERE i.id = ?`, introduction)!
      return {
        id,
        kind: 'introduction',
        title: this.introductionPreview(row).title,
        book: localized(bookName(row.collection_ar, row.book_ar), bookName(row.collection_en, row.book_en)),
        author: localized(row.author_ar, row.author),
        narrator: '',
        html: text(toHTML(row.arabic), row.english ? toHTML(row.english) : ''),
        gradings: [],
        url: httpsURL(row.url),
      }
    }
    const rowID = this.hadithIDs.row(id)
    if (rowID === undefined) return null
    const row = this.get<HadithRow & { url: string; author: string; author_ar: string }>(
      this.hadith,
      `SELECT ${FULL}, h.url, coalesce(b.author, '') AS author, b.author_ar ${HADITH_JOINS} WHERE h.id = ?`,
      rowID,
    )!
    const gradings = this.all<Record<string, string>>(
      this.hadith,
      `SELECT coalesce(r.name_ar, '') AS grader_ar, coalesce(r.name_en, '') AS grader_en,
         g.grade_ar, g.grade_en, g.reference_ar, g.reference_en
       FROM hadith_grading g LEFT JOIN grader r ON r.id = g.grader_id
       WHERE g.hadith_id = ? AND g.status = 'judgment' ORDER BY g.id`,
      rowID,
    ).map(grading => ({
      grader: localized(grading.grader_ar!, grading.grader_en!),
      grade: localized(grading.grade_ar!, grading.grade_en!),
      reference: localized(grading.reference_ar!, grading.reference_en!),
    }))
    const adjacent = (comparison: '<' | '>', order: 'ASC' | 'DESC') => {
      const found = this.get<Row<'id', number>>(
        this.hadith,
        `SELECT h.id FROM hadith h JOIN book b ON b.id = h.book_id
         WHERE b.collection_id = ? AND h.id ${comparison} ? ORDER BY h.id ${order} LIMIT 1`,
        row.collection,
        rowID,
      )
      return found ? this.hadithIDs.id(found.id) : undefined
    }
    return {
      id,
      kind: 'hadith',
      title: hadithTitle(row),
      book: localized(row.chapter_ar, row.chapter_en),
      author: localized(row.author_ar, row.author),
      narrator: row.narrator,
      html: text(toHTML(row.arabic), row.english ? toHTML(row.english) : ''),
      gradings,
      url: httpsURL(row.url),
      previous: adjacent('<', 'DESC'),
      next: adjacent('>', 'ASC'),
    }
  }

  // Supplications

  private supplicationBook(row: HadithRow): T.Text {
    const book = hadithBook(row)
    return row.collection === SAHIFA ? { ...book, ar: 'الصحيفة السجادية' } : book
  }

  private supplicationPreview(row: HadithRow): T.Preview {
    return {
      id: this.duaIDs.id(row.id),
      kind: 'dua',
      title: localized(row.chapter_ar, row.chapter_en),
      text: this.supplicationBook(row),
    }
  }

  supplicationList(): T.Preview[] {
    return this.all<HadithRow>(
      this.supplications,
      `SELECT ${SHORT} ${HADITH_JOINS} WHERE c.chapter_idx > 0 ORDER BY b.sort_order, c.chapter_idx, h.id`,
    ).map(row => this.supplicationPreview(row))
  }

  private supplicationRows(id: string) {
    const rowID = this.duaIDs.row(id)
    if (rowID === undefined) return null
    return {
      row: this.get<HadithRow & { url: string }>(
        this.supplications,
        `SELECT ${FULL}, h.url ${HADITH_JOINS} WHERE h.id = ?`,
        rowID,
      )!,
      translations: this.all<
        Row<'language' | 'edition' | 'text' | 'attribution' | 'url' | 'license'>
      >(
        this.supplications,
        `SELECT language, edition, text, attribution, url, license
         FROM supplication_translation WHERE hadith_id = ? ORDER BY language, edition`,
        rowID,
      ),
    }
  }

  supplication(id: string): T.Supplication | null {
    const found = this.supplicationRows(id)
    if (!found) return null
    return {
      id,
      title: localized(found.row.chapter_ar, found.row.chapter_en),
      book: this.supplicationBook(found.row),
      html: toHTML(found.row.arabic),
      translations: found.translations.map(({ text: body, url, ...translation }) => ({
        ...translation,
        html: toHTML(body),
        url: httpsURL(url),
      })),
      url: httpsURL(found.row.url),
    }
  }

  /** The text of a supplication, for chat. A translation always travels with its attribution. */
  supplicationText(id: string, language: string) {
    const found = this.supplicationRows(id)
    if (!found) return null
    const translation = found.translations.find(item => item.language === language)
    return {
      title: localized(found.row.chapter_ar, found.row.chapter_en),
      arabic: toPlain(found.row.arabic),
      translation: translation && {
        body: toPlain(translation.text),
        credit: [translation.attribution, translation.license].filter(Boolean).join('\n'),
      },
      url: httpsURL(found.row.url),
    }
  }

  // Rulings

  private authority(code: string) {
    return this.authorities.find(authority => authority.code === code)
  }

  private topics(authority: string, language: string, parent: number | null) {
    return this.all<{ id: number; title: string }>(
      this.rulings,
      `SELECT id, title FROM topic
       WHERE authority_code = ? AND language_code = ? AND parent_id IS ?
       ORDER BY position, id`,
      authority,
      language,
      parent,
    )
  }

  private toTopic = (row: { id: number; title: string }): T.Topic => ({
    id: this.topicIDs.id(row.id),
    title: row.title,
  })

  rulingContents(authority: string, language: string): T.Topic[] | null {
    if (!this.authority(authority)?.languages.some(item => item.code === language)) return null
    let topics = this.topics(authority, language, null)
    // A lone root is only a wrapper, unless it holds entries of its own.
    if (topics.length === 1) {
      const root = topics[0]!
      const children = this.topics(authority, language, root.id)
      const entries = this.get(this.rulings, 'SELECT 1 FROM placement WHERE topic_id = ? LIMIT 1', root.id)
      if (children.length) topics = entries ? [root, ...children] : children
    }
    return topics.map(this.toTopic)
  }

  topic(id: string, after?: number): T.TopicPage | null {
    const rowID = this.topicIDs.row(id)
    if (rowID === undefined) return null
    const head = this.get<{ title: string; authority: string; language: string }>(
      this.rulings,
      'SELECT title, authority_code AS authority, language_code AS language FROM topic WHERE id = ?',
      rowID,
    )!
    const rows = this.all<QuestionRow & { position: number }>(
      this.rulings,
      `SELECT q.id, q.question, substr(q.answer, 1, ${PREVIEW_SOURCE}) AS answer, q.kind, q.context, p.position
       FROM placement p JOIN question q ON q.id = p.question_id
       WHERE p.topic_id = ? AND p.position > ? ORDER BY p.position LIMIT ?`,
      rowID,
      after ?? Number.MIN_SAFE_INTEGER,
      PAGE_SIZE + 1,
    )
    const name = this.authority(head.authority)!.name
    return {
      title: head.title,
      topics: after === undefined ? this.topics(head.authority, head.language, rowID).map(this.toTopic) : [],
      ...paged(rows, row => this.rulingPreview(row, name), row => row.position),
    }
  }

  private rulingPreview(row: QuestionRow, authority: T.Text): T.Preview {
    const body = excerpt(questionPreview(row) || row.answer)
    return {
      id: this.rulingIDs.id(row.id),
      kind: 'rulings',
      title: authority,
      text: text(body, body),
      ...(row.context ? { context: row.context } : {}),
    }
  }

  ruling(id: string): T.Ruling | null {
    const rowID = this.rulingIDs.row(id)
    if (rowID === undefined) return null
    const row = this.get<
      Row<'authority' | 'language' | 'direction' | 'context' | 'question' | 'answer' | 'url'>
    >(
      this.rulings,
      `SELECT q.authority_code AS authority, q.language_code AS language, l.direction,
         q.context, q.question, q.answer, q.url
       FROM question q JOIN language l ON l.code = q.language_code WHERE q.id = ?`,
      rowID,
    )!
    const topics = this.all<{ id: number; title: string }>(
      this.rulings,
      `SELECT t.id, t.title FROM topic t JOIN placement p ON p.topic_id = t.id
       WHERE p.question_id = ? ORDER BY t.position, t.id`,
      rowID,
    )
    const footnotes = this.all<{ label: string; body: string; chapter: number }>(
      this.rulings,
      `SELECT f.label, f.body, f.entry_id IS NULL AS chapter
       FROM placement p JOIN footnote f ON f.topic_id = p.topic_id
       WHERE p.question_id = ?1 AND (f.entry_id = ?1 OR f.entry_id IS NULL) ORDER BY f.rowid`,
      rowID,
    )
    return {
      id,
      authority: this.authority(row.authority)!.name,
      language: row.language,
      rtl: row.direction === 'rtl',
      context: row.context,
      question: row.question,
      answer: row.answer,
      topics: topics.map(this.toTopic),
      footnotes: footnotes.map(note => ({ ...note, chapter: note.chapter !== 0 })),
      url: httpsURL(row.url),
    }
  }

  /** Turns search references into previews, in ranked order, dropping any that don't resolve. */
  hydrate(references: unknown[]): T.Preview[] {
    const seen = new Set<string>()
    const result: T.Preview[] = []
    for (const value of references) {
      const preview = this.hydrateOne(value)
      if (!preview || seen.has(preview.id)) continue
      seen.add(preview.id)
      result.push(preview)
    }
    return result
  }

  private hydrateOne(value: unknown): T.Preview | null {
    if (typeof value !== 'object' || value === null) return null
    const reference = value as Record<string, unknown>
    switch (reference.kind) {
      case 'quran': {
        const index = this.verseIDs.resolve(String(reference.chapter), String(reference.verse))
        const verse = index === undefined ? null : this.verseAt(index)
        if (!verse) return null
        const position = `${verse.surah}:${verse.number}`
        return {
          id: verse.id,
          kind: 'quran',
          title: text(`${verse.name.ar} ${position}`, `${verse.name.en} ${position}`),
          text: text(excerpt(verse.text.ar), excerpt(verse.text.en)),
        }
      }
      case 'hadith': {
        const row = this.hadithIDs.resolve(
          String(reference.book),
          String(reference.chapter),
          String(reference.number),
        )
        if (row === undefined) return null
        return this.hadithPreview(
          this.get<HadithRow>(this.hadith, `SELECT ${SHORT} ${HADITH_JOINS} WHERE h.id = ?`, row)!,
        )
      }
      case 'dua': {
        // The locator is book:file:number.
        const parts = typeof reference.locator === 'string' ? reference.locator.split(':') : []
        if (parts.length < 3) return null
        const row = this.duaIDs.resolve(parts[0]!, parts.slice(1, -1).join(':'), parts.at(-1)!)
        if (row === undefined) return null
        return this.supplicationPreview(
          this.get<HadithRow>(this.supplications, `SELECT ${SHORT} ${HADITH_JOINS} WHERE h.id = ?`, row)!,
        )
      }
      case 'rulings': {
        const row = this.rulingIDs.resolve(
          String(reference.authority),
          String(reference.language),
          String(reference.id),
        )
        const authority = this.authority(String(reference.authority))
        if (row === undefined || !authority) return null
        return this.rulingPreview(
          this.get<QuestionRow>(
            this.rulings,
            `SELECT id, question, substr(answer, 1, ${PREVIEW_SOURCE}) AS answer, kind, context FROM question WHERE id = ?`,
            row,
          )!,
          authority.name,
        )
      }
      default:
        return null
    }
  }
}

const INTRODUCTION = `SELECT i.id, i.title, i.arabic, i.english, i.url,
    b.name_ar AS book_ar, b.name_en AS book_en, l.name_ar AS collection_ar, l.name_en AS collection_en,
    coalesce(b.author, '') AS author, b.author_ar
  FROM introduction i JOIN book b ON b.id = i.book_id JOIN collection l ON l.id = b.collection_id`

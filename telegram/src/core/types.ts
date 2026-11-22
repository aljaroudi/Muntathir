import type { CalendarData } from './calendar.ts'

/** Arabic and English; English may be empty, and then Arabic is shown. */
export type Text = { ar: string; en: string }

export type Kind = 'quran' | 'hadith' | 'dua' | 'rulings' | 'introduction'
export type Preview = { id: string; kind: Kind; title: Text; text: Text }
export type Page<T> = { items: T[]; next?: number }

export type Bootstrap = { calendar: CalendarData }

export type Surah = { number: number; name: Text; verses: number }
export type Verse = { id: string; surah: number; number: number; name: Text; text: Text }
export type SurahPage = Page<Verse> & { surah: Surah; basmala?: string }

export type Collection = { id: string; name: Text; count: number }
export type Chapter = { id: string; name: Text; count: number }
export type Book = { id: string; name: Text; chapters: Chapter[] }
export type CollectionContents = {
  collection: Collection
  introduction?: Preview
  books: Book[]
}
export type ChapterPage = Page<Preview> & { title: Text; book: Text }

export type Grading = { grader: Text; grade: Text; reference: Text }
/** `html` is rendered server-side from Markdown with raw HTML, links and images disabled. */
export type Narration = {
  id: string
  kind: 'hadith' | 'introduction'
  title: Text
  book: Text
  author: Text
  narrator: string
  html: Text
  gradings: Grading[]
  url?: string
  previous?: string
  next?: string
}

export type Translation = {
  language: string
  edition: string
  html: string
  attribution: string
  url?: string
  license: string
}
export type Supplication = {
  id: string
  title: Text
  book: Text
  html: string
  translations: Translation[]
  url?: string
}

export type Language = { code: string; name: string; rtl: boolean; count: number }
export type Authority = { code: string; name: Text; languages: Language[] }
export type Topic = { id: string; title: string }
export type TopicPage = Page<Preview> & { title: string; topics: Topic[] }
export type Ruling = {
  id: string
  authority: Text
  language: string
  rtl: boolean
  context: string
  question: string
  answer: string
  topics: Topic[]
  footnotes: { label: string; body: string; chapter: boolean }[]
  url?: string
}

export const SCOPES = ['library', 'quran', 'hadith', 'dua', 'rulings'] as const
export type Scope = (typeof SCOPES)[number]
export type SearchProblem = 'empty' | 'long' | 'invalid' | 'limited' | 'unavailable'

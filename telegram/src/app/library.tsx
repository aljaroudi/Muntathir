import { useEffect, useRef } from 'preact/hooks'
import type * as T from '../core/types.ts'
import { useGet, usePages } from './api.ts'
import { useApp } from './state.ts'
import { device } from './telegram.ts'
import { VerseCard } from './today.tsx'
import { External, Failed, Header, Loading, Markup, More, Previews, Row, useText } from './ui.tsx'

const POSITION = 'quran_position'
type Position = { surah: number; verse: number }
let position: Position | null = null

export async function loadPosition() {
  const use = (saved: Position | null) => {
    if (Number.isInteger(saved?.surah) && Number.isInteger(saved?.verse)) position = saved
  }
  use(await device.get<Position>(POSITION, use))
}

export function Library() {
  const { t } = useApp()
  return (
    <>
      <Header title={t.library} />
      <ul class="list">
        <Row to={{ page: 'quran' }} title={t.quran} />
        <Row to={{ page: 'hadith' }} title={t.hadith} />
        <Row to={{ page: 'supplications' }} title={t.supplications} />
        <Row to={{ page: 'authorities' }} title={t.rulings} />
      </ul>
    </>
  )
}

export function Quran() {
  const { t } = useApp()
  const text = useText()
  const { data, failure, retry } = useGet<T.Surah[]>('quran')
  const saved = data && position ? data[position.surah - 1] : undefined
  return (
    <>
      <Header title={t.quran} />
      {failure && <Failed failure={failure} retry={retry} />}
      {!data && !failure && <Loading />}
      {saved && (
        <ul class="list">
          <Row
            to={{ page: 'surah', number: saved.number, verse: position!.verse }}
            title={t.continueReading}
            detail={`${text(saved.name)} ${saved.number}:${position!.verse}`}
          />
        </ul>
      )}
      {data && (
        <ul class="list">
          {data.map(surah => (
            <Row
              key={surah.number}
              to={{ page: 'surah', number: surah.number }}
              title={`${surah.number}. ${text(surah.name)}`}
              detail={`${surah.verses} ${t.verses}`}
            />
          ))}
        </ul>
      )}
      <p class="note"><External url="https://tanzil.net/">{t.quranCredit}</External></p>
    </>
  )
}

export function Surah({ number, verse }: { number: number; verse?: number }) {
  const { t, locale } = useApp()
  const text = useText()
  const { head, items, hasMore, loading, failure, more } = usePages<T.SurahPage>(`quran/${number}`)
  const list = useRef<HTMLOListElement>(null)
  // An invalid verse just opens the surah.
  const wanted = verse && head && verse <= head.surah.verses ? verse : undefined
  // Some verses past it too, so it can scroll to the top.
  const through = wanted && Math.min(head!.surah.verses, wanted + 10)
  const reached = !through || items.some(item => item.number === through)
  const jumped = useRef(false)
  // Where the jump left the page: that scroll isn't reading, and near the end it can't reach the verse.
  const landed = useRef<number | null>(null)

  useEffect(() => {
    if (!reached && hasMore && !loading && !failure) void more()
  }, [reached, hasMore, loading, failure, more])

  useEffect(() => {
    if (!wanted || !reached || jumped.current) return
    const target = list.current?.querySelector(`[data-verse="${wanted}"]`)
    if (!target) return
    jumped.current = true
    // After the screen's own scroll restoration.
    requestAnimationFrame(() => {
      target.scrollIntoView({ block: 'start' })
      landed.current = window.scrollY
    })
  }, [wanted, reached])

  useEffect(() => {
    if (!list.current || !reached) return
    let timer: ReturnType<typeof setTimeout> | undefined
    const save = () => {
      if (wanted && landed.current === null) return
      if (landed.current !== null && Math.abs(window.scrollY - landed.current) < 4) return
      landed.current = -Infinity
      clearTimeout(timer)
      timer = setTimeout(() => {
        const top = [...(list.current?.children ?? [])].find(row => row.getBoundingClientRect().bottom > 80)
        if (!top) return
        position = { surah: number, verse: Number(top.getAttribute('data-verse')) }
        device.set(POSITION, position)
      }, 700)
    }
    window.addEventListener('scroll', save, { passive: true })
    return () => {
      clearTimeout(timer)
      window.removeEventListener('scroll', save)
    }
  }, [number, reached, items.length > 0])

  return (
    <>
      <Header title={head ? text(head.surah.name) : t.quran} />
      {head?.basmala && <p class="quran basmala" dir="rtl" lang="ar">{head.basmala}</p>}
      <ol class="verses" ref={list}>
        {items.map(item => (
          <li key={item.id} data-verse={item.number}>
            <p class="quran" dir="rtl" lang="ar">
              {item.text.ar} <span class="verse-number">{item.number}</span>
            </p>
            {locale === 'en' && <p class="translation" dir="ltr" lang="en">{item.text.en}</p>}
          </li>
        ))}
      </ol>
      <More show={hasMore} loading={loading} failure={failure} load={more} />
      {head && (
        <p class="note">
          <External url="https://tanzil.net/">{t.quranCredit}</External>
          {locale === 'en' && (
            <>
              <br />
              <External url="https://tanzil.net/trans/en.qarai">{t.translationCredit}</External>
            </>
          )}
        </p>
      )}
    </>
  )
}

export function VersePage({ id }: { id: string }) {
  const { t, locale } = useApp()
  const { data, failure, retry } = useGet<T.Verse>(`verse/${id}`)
  return (
    <>
      <Header title={t.quran} />
      {failure && <Failed failure={failure} retry={retry} />}
      {!data && !failure && <Loading />}
      {data && <VerseCard verse={data} />}
      <p class="note">
        <External url="https://tanzil.net/">{t.quranCredit}</External>
        {locale === 'en' && <><br />{t.translationCredit}</>}
      </p>
    </>
  )
}

export function Collections() {
  const { t } = useApp()
  const text = useText()
  const { data, failure, retry } = useGet<T.Collection[]>('hadith')
  return (
    <>
      <Header title={t.hadith} />
      {failure && <Failed failure={failure} retry={retry} />}
      {!data && !failure && <Loading />}
      <ul class="list">
        {data?.map(item => (
          <Row key={item.id} to={{ page: 'collection', id: item.id }} title={text(item.name)} trailing={item.count} />
        ))}
      </ul>
    </>
  )
}

// Kept outside the screen, so Back from a chapter finds its volume still open.
const openVolumes = new Set<string>()

export function Collection({ id }: { id: string }) {
  const { t } = useApp()
  const text = useText()
  const { data, failure, retry } = useGet<T.CollectionContents>(`hadith/${id}`)
  return (
    <>
      <Header title={data ? text(data.collection.name) : t.hadith} />
      {failure && <Failed failure={failure} retry={retry} />}
      {!data && !failure && <Loading />}
      {data?.introduction && (
        <ul class="list">
          <Row
            to={{ page: 'narration', id: data.introduction.id }}
            title={t.introduction}
            detail={text(data.introduction.title)}
          />
        </ul>
      )}
      {data?.books.map(book => {
        const chapters = (
          <ul class="list">
            {book.chapters.map(chapter => (
              <Row key={chapter.id} to={{ page: 'chapter', id: chapter.id }} title={text(chapter.name)} trailing={chapter.count} />
            ))}
          </ul>
        )
        // Bihar has 106 volumes.
        return data.books.length === 1 ? (
          <div key={book.id}>{chapters}</div>
        ) : (
          <details
            key={book.id}
            class="volume"
            open={openVolumes.has(book.id)}
            onToggle={event => {
              if (event.currentTarget.open) openVolumes.add(book.id)
              else openVolumes.delete(book.id)
            }}
          >
            <summary dir="auto">{text(book.name)}</summary>
            {chapters}
          </details>
        )
      })}
    </>
  )
}

export function Chapter({ id }: { id: string }) {
  const { t } = useApp()
  const text = useText()
  const { head, items, hasMore, loading, failure, more } = usePages<T.ChapterPage>(`chapter/${id}`)
  return (
    <>
      <Header title={head ? text(head.title) : t.hadith} subtitle={head ? text(head.book) : undefined} />
      <Previews items={items} />
      <More show={hasMore} loading={loading} failure={failure} load={more} />
    </>
  )
}

export function Narration({ id }: { id: string }) {
  const { t, locale, push } = useApp()
  const text = useText()
  const { data, failure, retry } = useGet<T.Narration>(`narration/${id}`)
  if (!data) return failure ? <Failed failure={failure} retry={retry} /> : <Loading />
  return (
    <article>
      <Header title={text(data.title)} subtitle={text(data.book)} />
      {text(data.author) && <p class="muted" dir="auto">{text(data.author)}</p>}
      <Markup html={data.html.ar} class="arabic" lang="ar" />
      {locale === 'en' && data.html.en && (
        <div class="translation" lang="en">
          {data.narrator && <p dir="auto">{data.narrator}</p>}
          <Markup html={data.html.en} lang="en" />
        </div>
      )}
      {data.gradings.length > 0 && (
        <section class="card">
          <h2>{t.gradings}</h2>
          {data.gradings.map((grading, index) => (
            <p key={index} dir="auto">
              <b>{text(grading.grade)}</b>
              {text(grading.grader) && ` · ${text(grading.grader)}`}
              {text(grading.reference) && <span class="muted"> · {text(grading.reference)}</span>}
            </p>
          ))}
        </section>
      )}
      {data.url && <External url={data.url}>{t.source}</External>}
      {(data.previous || data.next) && (
        <div class="pager">
          <button class="button" disabled={!data.previous} onClick={() => push({ page: 'narration', id: data.previous! })}>
            {t.previous}
          </button>
          <button class="button" disabled={!data.next} onClick={() => push({ page: 'narration', id: data.next! })}>
            {t.next}
          </button>
        </div>
      )}
    </article>
  )
}

export function Supplications() {
  const { t } = useApp()
  const { data, failure, retry } = useGet<T.Preview[]>('supplications')
  return (
    <>
      <Header title={t.supplications} />
      {failure && <Failed failure={failure} retry={retry} />}
      {!data && !failure && <Loading />}
      {data && <Previews items={data} />}
    </>
  )
}

export function SupplicationPage({ id }: { id: string }) {
  const { t, locale } = useApp()
  const text = useText()
  const { data, failure, retry } = useGet<T.Supplication>(`supplication/${id}`)
  if (!data) return failure ? <Failed failure={failure} retry={retry} /> : <Loading />
  return (
    <article>
      <Header title={text(data.title)} subtitle={text(data.book)} />
      <Markup html={data.html} class="arabic" lang="ar" />
      {data.translations.map(translation => (
        <details
          key={`${translation.language}:${translation.edition}`}
          class="volume"
          open={translation.language === locale}
        >
          <summary>{t.translation} · {languageName(translation.language, locale)}</summary>
          <Markup html={translation.html} lang={translation.language} />
          <p class="note" dir="auto">
            {translation.url ? <External url={translation.url}>{translation.attribution}</External> : translation.attribution}
            <br />
            {translation.license}
          </p>
        </details>
      ))}
      {data.url && <External url={data.url}>{t.source}</External>}
    </article>
  )
}

function languageName(code: string, locale: string): string {
  try {
    return new Intl.DisplayNames([locale], { type: 'language' }).of(code) ?? code
  } catch {
    return code
  }
}

export function RulingsNotice() {
  return <p class="notice" role="note">{useApp().t.rulingsNotice}</p>
}

export function Authorities() {
  const { t } = useApp()
  const text = useText()
  const { data, failure, retry } = useGet<T.Authority[]>('rulings')
  return (
    <>
      <Header title={t.rulings} />
      <RulingsNotice />
      {failure && <Failed failure={failure} retry={retry} />}
      {!data && !failure && <Loading />}
      {data?.map(authority => (
        <section key={authority.code}>
          <h2 dir="auto">{text(authority.name)}</h2>
          <ul class="list">
            {authority.languages.map(language => (
              <Row
                key={language.code}
                to={{ page: 'contents', authority: authority.code, language: language.code }}
                title={language.name}
                trailing={language.count}
              />
            ))}
          </ul>
        </section>
      ))}
    </>
  )
}

export function RulingContents({ authority, language }: { authority: string; language: string }) {
  const { t } = useApp()
  const text = useText()
  const authorities = useGet<T.Authority[]>('rulings')
  const { data, failure, retry } = useGet<T.Topic[]>(`rulings/${authority}/${language}`)
  const name = authorities.data?.find(item => item.code === authority)?.name
  return (
    <>
      <Header title={name ? text(name) : t.rulings} />
      <RulingsNotice />
      {failure && <Failed failure={failure} retry={retry} />}
      {!data && !failure && <Loading />}
      <ul class="list">
        {data?.map(topic => <Row key={topic.id} to={{ page: 'topic', id: topic.id }} title={topic.title} />)}
      </ul>
    </>
  )
}

export function TopicPage({ id }: { id: string }) {
  const { t } = useApp()
  const { head, items, hasMore, loading, failure, more } = usePages<T.TopicPage>(`topic/${id}`)
  return (
    <>
      <Header title={head?.title ?? t.rulings} />
      {head && head.topics.length > 0 && (
        <ul class="list">
          {head.topics.map(topic => <Row key={topic.id} to={{ page: 'topic', id: topic.id }} title={topic.title} />)}
        </ul>
      )}
      {items.length > 0 && <Previews items={items} titled={false} />}
      <More show={hasMore} loading={loading} failure={failure} load={more} />
    </>
  )
}

/** Plain text on purpose: scraped rulings contain `<` and bracketed numbers that aren't markup. */
export function RulingPage({ id }: { id: string }) {
  const { t, push } = useApp()
  const text = useText()
  const { data, failure, retry } = useGet<T.Ruling>(`ruling/${id}`)
  if (!data) return failure ? <Failed failure={failure} retry={retry} /> : <Loading />
  const dir = data.rtl ? 'rtl' : 'ltr'
  return (
    <article>
      <Header title={text(data.authority)} />
      <RulingsNotice />
      <div dir={dir} lang={data.language} class="ruling">
        {data.context && <p class="muted prose">{data.context}</p>}
        {data.question && <h2 class="prose">{data.question}</h2>}
        <p class="prose">{data.answer}</p>
        {data.footnotes.length > 0 && (
          <section class="footnotes">
            <h3>{t.footnotes}</h3>
            {data.footnotes.map((note, index) => (
              <p key={index} class="prose"><b>{note.label}</b> {note.body}</p>
            ))}
          </section>
        )}
      </div>
      <div class="actions">
        {data.topics.map(topic => (
          <button key={topic.id} class="link" onClick={() => push({ page: 'topic', id: topic.id })}>
            <bdi>{topic.title}</bdi>
          </button>
        ))}
      </div>
      {data.url && <External url={data.url}>{t.officialSource}</External>}
    </article>
  )
}

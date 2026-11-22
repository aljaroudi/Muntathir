import { religiousDay, upcomingEvent, verseIndex } from '../core/calendar.ts'
import { dayIn, hijri } from '../core/day.ts'
import {
  formatDay,
  formatHijri,
  formatTime,
  formatTiming,
  METHOD_NAMES,
  pick,
  TIME_NAMES,
} from '../core/i18n.ts'
import { nextPrayer, prayerTimes } from '../core/prayer.ts'
import type { Verse } from '../core/types.ts'
import { useGet } from './api.ts'
import { LocationForm } from './settings.tsx'
import { deviceZone, useApp, useNow } from './state.ts'
import { openTelegramLink } from './telegram.ts'
import { Failed, Header, Loading } from './ui.tsx'

function Countdown({ to }: { to: number }) {
  const left = Math.max(0, Math.ceil((to - useNow(1000)) / 1000))
  const pad = (value: number) => String(value).padStart(2, '0')
  return (
    <span class="number countdown" dir="ltr">
      {Math.floor(left / 3600)}:{pad(Math.floor(left / 60) % 60)}:{pad(left % 60)}
    </span>
  )
}

export function VerseCard({ verse, heading }: { verse: Verse; heading?: string }) {
  const { t, locale, push, data } = useApp()
  const reference = `${pick(verse.name, locale)} ${verse.surah}:${verse.number}`
  const share = () => {
    const link = `https://t.me/${data.username}?startapp=${verse.id}`
    const text = `${verse.text.ar}\n${reference}`
    openTelegramLink(
      `https://t.me/share/url?url=${encodeURIComponent(link)}&text=${encodeURIComponent(text)}`,
    )
  }
  return (
    <section class="card">
      {heading && <h2>{heading}</h2>}
      <p class="quran" dir="rtl" lang="ar">{verse.text.ar}</p>
      {locale === 'en' && verse.text.en && <p class="translation" dir="ltr" lang="en">{verse.text.en}</p>}
      <div class="actions">
        <button
          class="link"
          onClick={() => push({ page: 'surah', number: verse.surah, verse: verse.number })}
        >
          <bdi>{reference}</bdi>
        </button>
        {data.username && <button class="button" onClick={share}>{t.share}</button>}
      </div>
    </section>
  )
}

export function Today() {
  const { t, locale, data, place, method, push } = useApp()
  const now = useNow(15_000)
  const zone = place?.zone ?? deviceZone()
  const today = dayIn(now, zone)
  const { calendar } = data
  const date = hijri(calendar.months, today)
  const times = place ? prayerTimes(place, today, method) : []
  const next = place ? nextPrayer(place, today, method, now) : null
  const event = upcomingEvent(calendar, place, today, now)
  const verseDate = hijri(calendar.months, religiousDay(place, today, now))
  const verse = useGet<Verse>(verseDate ? `daily/${verseIndex(verseDate)}` : null)

  return (
    <>
      <Header
        title={date ? formatHijri(date, locale) : t.today}
        subtitle={formatDay(today, locale)}
        action={
          <button class="icon" aria-label={t.settings} title={t.settings} onClick={() => push({ page: 'settings' })}>
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M4 7h10m4 0h2M4 17h4m4 0h8" />
              <circle cx="16" cy="7" r="2.5" />
              <circle cx="10" cy="17" r="2.5" />
            </svg>
          </button>
        }
      />

      {!place ? (
        <section class="card">
          <h2>{t.prayers}</h2>
          <LocationForm />
        </section>
      ) : (
        <>
          {next && (
            <section class="hero">
              <p>{t.next}</p>
              <p class="hero-name">
                {TIME_NAMES[locale][next.name]} <bdi>{formatTime(next.at, zone, locale)}</bdi>
              </p>
              <Countdown to={next.at} />
            </section>
          )}
          <section class="card">
            <h2>{t.prayers}</h2>
            {times.length ? (
              <dl class="times">
                {times.map(({ name, at }) => (
                  <div key={name} class={next?.name === name && next.at === at ? 'current' : ''}>
                    <dt>{TIME_NAMES[locale][name]}</dt>
                    <dd class="number"><bdi>{formatTime(at, zone, locale)}</bdi></dd>
                  </div>
                ))}
              </dl>
            ) : (
              <p>{t.prayersUnavailable}</p>
            )}
            <button class="link" onClick={() => push({ page: 'settings' })}>
              {METHOD_NAMES[locale][method]} · <bdi>{zone}</bdi>
            </button>
          </section>
        </>
      )}

      {event && (
        <section class="card">
          <h2>{t.nextEvent}</h2>
          <p class="muted">{formatTiming(event.timing, locale)} · {formatHijri(event.hijri, locale)}</p>
          <ul class="plain">
            {event.events.map(item => <li key={item.id} dir="auto">{pick(item.title, locale)}</li>)}
          </ul>
        </section>
      )}

      {verse.data ? (
        <VerseCard verse={verse.data} heading={t.dailyAyah} />
      ) : verse.failure ? (
        <Failed failure={verse.failure} retry={verse.retry} />
      ) : (
        <Loading />
      )}
    </>
  )
}

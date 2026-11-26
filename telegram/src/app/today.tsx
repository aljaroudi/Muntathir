import type { JSX } from 'preact'
import { religiousDay, upcomingEvent, verseIndex } from '../core/calendar.ts'
import { dayIn, hijri } from '../core/day.ts'
import { formatCountdown, formatDay, formatTime, formatTiming, monthTitle, pick, TIME_NAMES } from '../core/i18n.ts'
import { DEFAULT_METHOD, nextPrayer, prayerTimes, type TimeName } from '../core/prayer.ts'
import type { Verse } from '../core/types.ts'
import { useGet } from './api.ts'
import { LocationForm } from './settings.tsx'
import { deviceZone, useApp, useNow } from './state.ts'
import { openTelegramLink } from './telegram.ts'
import { Failed, Loading } from './ui.tsx'

/** Drawn after the apps' SF Symbols for each time. */
const MOON = 'M14 4a8 8 0 1 0 6 12.5A6.5 6.5 0 0 1 14 4Z'
const TIME_ICONS: Record<TimeName, JSX.Element> = {
  imsak: <path d="M3 19h18M13 6a5.5 5.5 0 1 0 4.5 9A4.5 4.5 0 0 1 13 6Z" />,
  fajr: <path d="M3 18h18M7 18a5 5 0 0 1 10 0M12 8v2M5.8 11.8l1.4 1.4M18.2 11.8l-1.4 1.4" />,
  sunrise: <path d="M3 20h18M7 20a5 5 0 0 1 10 0M12 4v7m-2.5-4.5L12 4l2.5 2.5" />,
  dhuhr: <><circle cx="12" cy="12" r="4" /><path d="M12 3v2m0 14v2M3 12h2m14 0h2M5.6 5.6 7 7m10 10 1.4 1.4m0-12.8L17 7M7 17l-1.4 1.4" /></>,
  asr: <><circle cx="12" cy="9" r="3.5" /><path d="M12 2.5V4M4.5 9H6m12 0h1.5M6.7 3.7l1 1m9.6-1-1 1M5 16h14M8 20h8" /></>,
  sunset: <path d="M3 20h18M7 20a5 5 0 0 1 10 0M12 4v7m-2.5-2.5L12 11l2.5-2.5" />,
  maghrib: <path d="M5 17h14M8 21h8M12 3a6 6 0 1 0 5 9.5A5 5 0 0 1 12 3Z" />,
  isha: <path d={`${MOON}M19 3v3m-1.5-1.5h3`} />,
  midnight: <path d={`${MOON}M16 3h4l-4 4h4`} />,
}

const Icon = ({ children }: { children: JSX.Element }) => (
  <svg class="symbol" viewBox="0 0 24 24" aria-hidden="true">{children}</svg>
)

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
    <section class="card verse-card">
      {heading && (
        <h2 class="label">
          <Icon><path d="M12 7c-3-2.5-6-2.5-8-1.5v13c2-1 5-1 8 1.5 3-2.5 6-2.5 8-1.5v-13c-2-1-5-1-8 1.5Zm0 0v13" /></Icon>
          {heading}
        </h2>
      )}
      <p class="quran" dir="rtl" lang="ar">{verse.text.ar}</p>
      {locale === 'en' && verse.text.en && <p class="translation" dir="ltr" lang="en">{verse.text.en}</p>}
      <div class="actions">
        <button
          class="link reference"
          onClick={() => push({ page: 'surah', number: verse.surah, verse: verse.number })}
        >
          <bdi>{reference}</bdi>
        </button>
        {data.username && (
          <button class="icon" aria-label={t.share} title={t.share} onClick={share}>
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15V3m-4 4 4-4 4 4M7 10H5v11h14V10h-2" /></svg>
          </button>
        )}
      </div>
    </section>
  )
}

export function Today() {
  const { t, locale, data, place, push } = useApp()
  const now = useNow(15_000)
  const zone = place?.zone ?? deviceZone()
  const today = dayIn(now, zone)
  const { calendar } = data
  const date = hijri(calendar.months, today)
  const times = place ? prayerTimes(place, today, DEFAULT_METHOD) : []
  const next = place ? nextPrayer(place, today, DEFAULT_METHOD, now) : null
  const event = upcomingEvent(calendar, place, today, now)
  const verseDate = hijri(calendar.months, religiousDay(place, today, now))
  const verse = useGet<Verse>(verseDate ? `daily/${verseIndex(verseDate)}` : null)

  return (
    <>
      <header class="header">
        <h1>{date ? `${date.date} ${monthTitle(date.month, locale)}` : t.today}</h1>
        <button class="icon" aria-label={t.settings} title={t.settings} onClick={() => push({ page: 'settings' })}>
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M4 7h10m4 0h2M4 17h4m4 0h8" />
            <circle cx="16" cy="7" r="2.5" />
            <circle cx="10" cy="17" r="2.5" />
          </svg>
        </button>
      </header>

      <section class="card">
        <p class="day">{formatDay(today, locale, 'short')}</p>
        {!place ? (
          <LocationForm />
        ) : times.length ? (
          <ul class="times">
            {times.map(({ name, at }) => {
              // By name, as in the app: after Isha, today's Fajr counts down to tomorrow's.
              const upcoming = next?.name === name
              return (
                <li key={name} class={upcoming ? 'upcoming' : undefined}>
                  <Icon>{TIME_ICONS[name]}</Icon>
                  <span class="time-name">{TIME_NAMES[locale][name]}</span>
                  {upcoming && next && <span class="pill number">{formatCountdown(next.at - now, locale)}</span>}
                  <span class="time number"><bdi>{formatTime(at, zone, locale, false)}</bdi></span>
                </li>
              )
            })}
          </ul>
        ) : (
          <p class="muted">{t.prayersUnavailable}</p>
        )}
      </section>

      {verse.data ? (
        <VerseCard verse={verse.data} heading={t.dailyAyah} />
      ) : verse.failure ? (
        <Failed failure={verse.failure} retry={verse.retry} />
      ) : (
        <Loading />
      )}

      {event && (
        <section class="card">
          <h2 class="label">
            <Icon><><rect x="4" y="5" width="16" height="15" rx="3" /><path d="M4 10h16M9 3v4m6-4v4" /></></Icon>
            {formatTiming(event.timing, locale)}
          </h2>
          {event.events.map(item => <p key={item.id} class="event-name" dir="auto">{pick(item.title, locale)}</p>)}
        </section>
      )}
    </>
  )
}

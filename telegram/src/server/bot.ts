import { Bot, InlineKeyboard, Keyboard, type BotConfig, type Context } from 'grammy'
import { upcomingEvent, religiousDay, verseIndex } from '../core/calendar.ts'
import { dayIn, hijri } from '../core/day.ts'
import {
  formatDay,
  formatHijri,
  formatTime,
  formatTiming,
  localeOf,
  METHOD_NAMES,
  pick,
  PROBLEMS,
  strings,
  TIME_NAMES,
  type Locale,
} from '../core/i18n.ts'
import {
  DEFAULT_METHOD,
  METHODS,
  nextPrayer,
  prayerTimes,
  qibla,
  validPlace,
  type Method,
  type Place,
} from '../core/prayer.ts'
import { excerpt, split } from '../core/text.ts'
import { SCOPES, type Scope, type Verse } from '../core/types.ts'
import type { CalendarSource } from './calendar.ts'
import type { Content } from './content.ts'
import { isPublicID, PREFIX } from './ids.ts'
import { log } from './log.ts'
import type { Search } from './search.ts'
import { zoneAt } from './timezone.ts'

export const MESSAGE_LIMIT = 4096
/** Longer texts continue in the Mini App: Telegram allows about one message a second per chat. */
const MAX_PARTS = 3
const RESULTS = 8
const RESULT_EXCERPT = 140
const MAX_SHARE_URL = 1900
/** Without a location there's no time zone, so dates follow Riyadh and say so. */
const DEFAULT_ZONE = 'Asia/Riyadh'

const METHOD_CODES: Record<Method, string> = { tehran: 't', jafari: 'j', ummAlQura: 'u' }
const COORDINATES = String.raw`(-?\d{1,2}\.\d{3}):(-?\d{1,3}\.\d{3})`
const PLACE_BUTTON = new RegExp(`^p:([tju]):${COORDINATES}$`)
const VERSE_BUTTON = new RegExp(`^v:${COORDINATES}$`)
const SCOPE_BUTTON = /^s:([a-z]+)(?::([a-z]{1,20}))?$/

type Options = {
  token: string
  username?: string
  /** The Mini App's origin. */
  publicURL: string
  privacy: Record<Locale, string>
  content: Content
  calendar: CalendarSource
  search: Search
  now?: () => number
  config?: BotConfig<Context>
}

/** Three decimals, about 110 m, is all a button carries. */
function coordinates({ latitude, longitude }: Place): string {
  return `${latitude.toFixed(3)}:${longitude.toFixed(3)}`
}

/** The words searched for: a message's text without a leading command. */
export function queryOf(text: string): string {
  return text.replace(/^\/\w+(@\w+)?\s*/u, '').trim()
}

export function createBot(options: Options) {
  const { content, calendar, search, now = Date.now } = options
  const bot = new Bot(options.token, options.config)
  const privateChat = bot.chatType('private')
  const localeFor = (context: Context) => localeOf(context.from?.language_code)
  const username = (context: Context) => options.username ?? context.me.username
  const plain = { link_preview_options: { is_disabled: true } } as const

  function appURL(open?: string): string {
    const url = new URL('/', options.publicURL)
    if (open) url.searchParams.set('open', open)
    return url.href
  }

  function openButton(locale: Locale, open?: string, label = strings[locale].open) {
    return new InlineKeyboard().webApp(label, appURL(open))
  }

  async function askLocation(context: Context) {
    const t = strings[localeFor(context)]
    await context.reply(t.askLocation, {
      reply_markup: new Keyboard().requestLocation(t.shareLocation).resized().oneTime(),
    })
  }

  function dateLines(locale: Locale, place: Place | null, zone: string): string[] {
    const t = strings[locale]
    const instant = now()
    const data = calendar.current(instant)
    const today = dayIn(instant, zone)
    const date = hijri(data.months, today)
    const lines = [date ? formatHijri(date, locale) : '', formatDay(today, locale)].filter(Boolean)
    const event = upcomingEvent(data, place, today, instant)
    if (event) {
      lines.push(
        '',
        `${t.nextEvent} · ${formatTiming(event.timing, locale)} · ${formatDay(event.day, locale, 'short')}`,
        ...event.events.map(item => `• ${pick(item.title, locale)}`),
      )
    }
    return lines
  }

  function placeMessage(locale: Locale, place: Place, method: Method) {
    const t = strings[locale]
    const instant = now()
    const zone = zoneAt(place)
    const today = dayIn(instant, zone)
    const times = prayerTimes(place, today, method)
    const next = nextPrayer(place, today, method, instant)
    const lines = [`${t.prayers} · ${METHOD_NAMES[locale][method]}`, '']
    if (!times.length) lines.push(t.prayersUnavailable)
    for (const { name, at } of times) {
      const marker = next?.name === name && next.at === at ? ` ← ${t.next}` : ''
      lines.push(`${TIME_NAMES[locale][name]}: ${formatTime(at, zone, locale)}${marker}`)
    }
    lines.push('', `${t.qibla}: ${qibla(place).toFixed(1)}° ${t.fromNorth}`)
    lines.push('', ...dateLines(locale, place, zone), '', zone)

    const keyboard = new InlineKeyboard()
    for (const other of METHODS) {
      if (other !== method)
        keyboard
          .text(METHOD_NAMES[locale][other], `p:${METHOD_CODES[other]}:${coordinates(place)}`)
          .row()
    }
    keyboard.text(t.dailyAyah, `v:${coordinates(place)}`).webApp(t.qibla, appURL('qibla'))
    return { text: lines.join('\n'), keyboard }
  }

  function dailyVerse(place: Place | null, zone: string): Verse | null {
    const instant = now()
    const day = religiousDay(place, dayIn(instant, zone), instant)
    const date = hijri(calendar.current(instant).months, day)
    return date && content.dailyVerse(verseIndex(date))
  }

  function verseText(locale: Locale, verse: Verse): string {
    const t = strings[locale]
    const lines = [`${pick(verse.name, locale)} ${verse.surah}:${verse.number}`, '', verse.text.ar]
    const translated = locale === 'en' && verse.text.en
    if (translated) lines.push('', verse.text.en)
    lines.push('', t.quranCredit)
    if (translated) lines.push(t.translationCredit)
    return lines.join('\n')
  }

  function shareURL(context: Context, locale: Locale, verse: Verse): string {
    const link = `https://t.me/${username(context)}?startapp=${verse.id}`
    const reference = `${pick(verse.name, locale)} ${verse.surah}:${verse.number}`
    const url = (text: string) =>
      `https://t.me/share/url?url=${encodeURIComponent(link)}&text=${encodeURIComponent(text)}`
    const full = url(`${verse.text.ar}\n${reference}`)
    // A long verse would overflow the button's URL, so only its reference is shared.
    return full.length <= MAX_SHARE_URL ? full : url(reference)
  }

  async function sendVerse(context: Context, verse: Verse | null, before: string[] = []) {
    const locale = localeFor(context)
    if (!verse) return void (await context.reply(strings[locale].notFound))
    const parts = split([...before, verseText(locale, verse)].join('\n'), MESSAGE_LIMIT)
    for (const [index, part] of parts.entries()) {
      await context.reply(part, {
        ...plain,
        ...(index === parts.length - 1
          ? {
              reply_markup: openButton(locale, verse.id).url(
                strings[locale].share,
                shareURL(context, locale, verse),
              ),
            }
          : {}),
      })
    }
  }

  async function sendLong(context: Context, id: string, body: string, source?: string) {
    const locale = localeFor(context)
    const t = strings[locale]
    let parts = split(body, MESSAGE_LIMIT)
    if (parts.length > MAX_PARTS) {
      parts = parts.slice(0, MAX_PARTS)
      const note = `\n\n… ${t.continues}`
      parts[MAX_PARTS - 1] = split(parts[MAX_PARTS - 1]!, MESSAGE_LIMIT - note.length)[0] + note
    }
    const keyboard = openButton(locale, id, t.openFull)
    if (source) keyboard.row().url(id.startsWith(PREFIX.ruling) ? t.officialSource : t.source, source)
    for (const [index, part] of parts.entries()) {
      await context.reply(part, {
        ...plain,
        ...(index === parts.length - 1 ? { reply_markup: keyboard } : {}),
      })
    }
  }

  async function sendItem(context: Context, id: string) {
    const locale = localeFor(context)
    const t = strings[locale]
    if (id.startsWith(PREFIX.verse)) return sendVerse(context, content.verse(id))
    if (id.startsWith(PREFIX.introduction) && content.narration(id)) {
      await context.reply(t.introduction, { reply_markup: openButton(locale, id, t.openFull) })
      return
    }
    if (id.startsWith(PREFIX.hadith)) {
      const item = content.narrationText(id)
      if (item) {
        const body = [pick(item.title, locale), item.arabic]
        if (locale === 'en' && item.english) body.push(item.english)
        return sendLong(context, id, body.join('\n\n'), item.url)
      }
    }
    if (id.startsWith(PREFIX.dua)) {
      const item = content.supplicationText(id, locale)
      if (item) {
        const body = [pick(item.title, locale)]
        // The credit comes before the text, so it survives when a long text is cut.
        if (item.translation) body.push(`${t.translation}: ${item.translation.credit}`)
        body.push(item.arabic)
        if (item.translation) body.push(item.translation.body)
        return sendLong(context, id, body.join('\n\n'), item.url)
      }
    }
    if (id.startsWith(PREFIX.ruling)) {
      const item = content.ruling(id)
      if (item) {
        // Authority and notice come first, so a cut text still carries them.
        const body = [pick(item.authority, locale), t.rulingsNotice, item.context, item.question, item.answer]
        if (item.footnotes.length) {
          body.push(
            t.footnotes,
            ...item.footnotes.map(note => `${note.label} ${note.body}`.trim()),
          )
        }
        return sendLong(context, id, body.filter(Boolean).join('\n\n'), item.url)
      }
    }
    await context.reply(t.notFound)
  }

  async function searchMessage(
    user: number,
    locale: Locale,
    query: string,
    scope: Scope,
    authority?: string,
  ) {
    const t = strings[locale]
    const selected = content.authorities.find(item => item.code === authority)
    const title =
      scope === 'rulings'
        ? `${t.rulings} · ${selected ? pick(selected.name, locale) : t.allAuthorities}`
        : scope === 'dua'
          ? t.supplications
          : t.quranHadith
    const outcome = await search.run(user, { query, scope, authority: selected?.code, limit: RESULTS })
    const lines = [title]
    if (scope === 'rulings') lines.push(t.rulingsNotice)
    const keyboard = new InlineKeyboard()
    if ('problem' in outcome) {
      lines.push('', PROBLEMS[locale][outcome.problem])
    } else if (!outcome.items.length) {
      lines.push('', t.noResults)
    } else {
      outcome.items.slice(0, RESULTS).forEach((item, index) => {
        lines.push(
          '',
          `${index + 1}. ${excerpt(pick(item.title, locale), 100)}`,
          excerpt(pick(item.text, locale), RESULT_EXCERPT),
        )
        if (index && index % 4 === 0) keyboard.row()
        keyboard.text(String(index + 1), `o:${item.id}`)
      })
      keyboard.row()
    }
    if (scope !== 'library') keyboard.text(t.quranHadith, 's:library')
    if (scope !== 'dua') keyboard.text(t.supplications, 's:dua')
    if (scope !== 'rulings') keyboard.text(t.rulings, 's:rulings')
    else keyboard.row().text(t.authority, 'a')
    keyboard.row().webApp(t.open, appURL('search'))
    return { text: split(lines.join('\n'), MESSAGE_LIMIT)[0]!, keyboard }
  }

  async function startSearch(context: Context, query: string, scope: Scope) {
    const locale = localeFor(context)
    if (!context.from || !context.message) return
    await context.replyWithChatAction('typing').catch(error => log('bot.action_failed', error))
    const { text, keyboard } = await searchMessage(context.from.id, locale, query, scope)
    await context.reply(text, {
      ...plain,
      reply_markup: keyboard,
      // The buttons read the query back from this message, so nothing is stored here.
      reply_parameters: { message_id: context.message.message_id, allow_sending_without_reply: true },
    })
  }

  privateChat.command('start', async context => {
    const locale = localeFor(context)
    const t = strings[locale]
    const payload = context.match.trim()
    if (isPublicID(payload)) return sendItem(context, payload)
    // A reply keyboard and an inline one can't share a message.
    await context.reply(`${t.name}\n\n${t.intro}`, { reply_markup: openButton(locale) })
    await context.reply(t.helpText, {
      reply_markup: new Keyboard().requestLocation(t.shareLocation).resized(),
    })
  })

  privateChat.command(['help', 'settings'], async context => {
    const locale = localeFor(context)
    await context.reply(strings[locale].helpText, { reply_markup: openButton(locale) })
  })
  privateChat.command(['prayers', 'qibla'], askLocation)

  privateChat.command('today', async context => {
    const locale = localeFor(context)
    const before = [...dateLines(locale, null, DEFAULT_ZONE), '', strings[locale].riyadhNote, '']
    await sendVerse(context, dailyVerse(null, DEFAULT_ZONE), before)
  })
  privateChat.command('verse', async context => {
    const before = [strings[localeFor(context)].riyadhNote, '']
    await sendVerse(context, dailyVerse(null, DEFAULT_ZONE), before)
  })

  privateChat.command('search', async context => {
    const query = context.match.trim()
    if (!query) return void (await context.reply(strings[localeFor(context)].searchPrompt))
    await startSearch(context, query, 'library')
  })
  privateChat.command('rulings', async context => {
    const query = context.match.trim()
    if (!query) return void (await context.reply(strings[localeFor(context)].searchUsage))
    await startSearch(context, query, 'rulings')
  })

  privateChat.command('privacy', async context => {
    const locale = localeFor(context)
    await context.reply(`${strings[locale].privacy}\n${options.privacy[locale]}`, plain)
  })

  privateChat.on('message:location', async context => {
    const locale = localeFor(context)
    const { latitude, longitude } = context.message.location
    const { text, keyboard } = placeMessage(locale, { latitude, longitude }, DEFAULT_METHOD)
    await context.reply(text, { reply_markup: keyboard })
  })

  privateChat.on('message:text', async context => {
    // An unknown command gets help rather than becoming a search.
    if (context.message.text.startsWith('/')) {
      const locale = localeFor(context)
      await context.reply(strings[locale].helpText, { reply_markup: openButton(locale) })
      return
    }
    await startSearch(context, context.message.text, 'library')
  })

  privateChat.on('callback_query:data', async context => {
    const locale = localeFor(context)
    const t = strings[locale]
    const data = context.callbackQuery.data
    // Answered first: a search can outlast the button's spinner.
    const answer = (text?: string) =>
      context
        .answerCallbackQuery(text ? { text } : undefined)
        .catch(error => log('bot.answer_failed', error))

    const placeButton = PLACE_BUTTON.exec(data)
    const verseButton = VERSE_BUTTON.exec(data)
    if (placeButton || verseButton) {
      const [latitude, longitude] = placeButton ? placeButton.slice(2) : verseButton!.slice(1)
      const place = { latitude: Number(latitude), longitude: Number(longitude) }
      await answer()
      if (!validPlace(place)) return
      if (!placeButton) return sendVerse(context, dailyVerse(place, zoneAt(place)))
      const method = METHODS.find(item => METHOD_CODES[item] === placeButton[1])!
      const { text, keyboard } = placeMessage(locale, place, method)
      await context.editMessageText(text, { reply_markup: keyboard })
      return
    }

    if (data.startsWith('o:') && isPublicID(data.slice(2))) {
      await answer()
      return sendItem(context, data.slice(2))
    }

    if (data === 'a') {
      await answer()
      const keyboard = new InlineKeyboard().text(t.allAuthorities, 's:rulings').row()
      for (const authority of content.authorities)
        keyboard.text(pick(authority.name, locale), `s:rulings:${authority.code}`).row()
      await context.editMessageReplyMarkup({ reply_markup: keyboard })
      return
    }

    const scopeButton = SCOPE_BUTTON.exec(data)
    const scope = SCOPES.find(item => item === scopeButton?.[1])
    const authority = scopeButton?.[2]
    if (
      !scope ||
      (authority && (scope !== 'rulings' || !content.authorities.some(item => item.code === authority)))
    ) {
      await answer()
      return
    }
    const query = queryOf(context.callbackQuery.message?.reply_to_message?.text ?? '')
    if (!query) return void (await answer(t.searchExpired))
    await answer(t.searching)
    const { text, keyboard } = await searchMessage(context.from.id, locale, query, scope, authority)
    await context.editMessageText(text, { ...plain, reply_markup: keyboard })
  })

  bot.catch(async ({ error, ctx }) => {
    // Pressing the button that is already active.
    if (
      (error as { description?: string } | null)?.description?.includes('message is not modified')
    )
      return
    log('bot.failed', error)
    if (ctx.chat?.type === 'private')
      await ctx
        .reply(strings[localeFor(ctx)].failed)
        .catch(failure => log('bot.reply_failed', failure))
  })

  return bot
}

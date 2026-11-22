import { Api } from 'grammy'
import { strings, type Locale } from '../src/core/i18n.ts'
import { paths, PUBLIC_URL } from './host.ts'

const COMMANDS: Record<Locale, [string, string][]> = {
  en: [
    ['start', 'Start'],
    ['prayers', 'Prayer times for your location'],
    ['qibla', 'Qibla direction'],
    ['today', 'Date, event and ayah'],
    ['verse', 'Daily ayah'],
    ['search', 'Search the Quran and Hadith'],
    ['rulings', 'Search rulings'],
    ['language', 'Reply language'],
    ['privacy', 'Privacy policy'],
    ['help', 'Help'],
  ],
  ar: [
    ['start', 'البداية'],
    ['prayers', 'أوقات الصلاة في موقعك'],
    ['qibla', 'اتجاه القبلة'],
    ['today', 'التاريخ والمناسبة والآية'],
    ['verse', 'آية اليوم'],
    ['search', 'البحث في القرآن والحديث'],
    ['rulings', 'البحث في الأحكام'],
    ['language', 'لغة الردود'],
    ['privacy', 'سياسة الخصوصية'],
    ['help', 'المساعدة'],
  ],
}
const SHORT: Record<Locale, string> = {
  en: 'Prayer times, Qibla, Hijri calendar, daily ayah, Quran, Hadith, supplications and rulings.',
  ar: 'أوقات الصلاة والقبلة والتقويم الهجري وآية اليوم والقرآن والحديث والأدعية والأحكام.',
}
// English is the default for every other language.
const LANGUAGES = [
  { locale: 'en', code: {} },
  { locale: 'ar', code: { language_code: 'ar' } },
] as const

async function token(): Promise<string> {
  const file = Bun.file(paths.env)
  if (!(await file.exists())) throw new Error(`Create ${paths.env} with TELEGRAM_BOT_TOKEN first`)
  const value = /^\s*TELEGRAM_BOT_TOKEN\s*=\s*["']?(\d+:[\w-]+)["']?\s*$/m.exec(await file.text())?.[1]
  if (!value) throw new Error('TELEGRAM_BOT_TOKEN is missing or malformed')
  return value
}

async function main() {
  const options = Bun.argv.slice(2)
  const apply = options[0] === '--apply'
  if (options.length > (apply ? 1 : 0)) throw new Error('Usage: configure.ts [--apply]')
  const api = new Api(await token())

  const me = await api.getMe()
  const webhook = await api.getWebhookInfo()
  console.log(`Bot: @${me.username}`)
  console.log(`Groups allowed: ${me.can_join_groups} (turn off in @BotFather)`)
  console.log(`Main Mini App: ${me.has_main_web_app} (share links need it)`)
  // A webhook URL can contain a secret, so only its host is shown.
  console.log(`Webhook: ${webhook.url ? new URL(webhook.url).host : 'none'}`)
  console.log(`Waiting updates: ${webhook.pending_update_count}`)
  for (const type of ['default', 'all_private_chats'] as const)
    for (const { locale, code } of LANGUAGES) {
      const list = await api.getMyCommands({ scope: { type }, ...code })
      console.log(`Commands, ${type}, ${locale}: ${list.map(item => item.command).join(', ') || 'none'}`)
    }
  for (const { locale, code } of LANGUAGES) {
    console.log(`Description, ${locale}: ${JSON.stringify((await api.getMyDescription(code)).description)}`)
    console.log(`About, ${locale}: ${JSON.stringify((await api.getMyShortDescription(code)).short_description)}`)
  }
  console.log(`Menu button: ${JSON.stringify(await api.getChatMenuButton())}`)

  if (webhook.url) throw new Error('A webhook is set, so something else may use this bot. Nothing was changed.')
  if (!apply) return console.log('Read-only: nothing changed. Use --apply to replace the settings above.')

  for (const { locale, code } of LANGUAGES) {
    const commands = COMMANDS[locale].map(([command, description]) => ({ command, description }))
    for (const type of ['default', 'all_private_chats'] as const)
      await api.setMyCommands(commands, { scope: { type }, ...code })
    await api.setMyDescription(strings[locale].intro, code)
    await api.setMyShortDescription(SHORT[locale], code)
  }
  await api.setChatMenuButton({
    menu_button: { type: 'web_app', text: strings.ar.name, web_app: { url: `${PUBLIC_URL}/` } },
  })
  console.log('Commands, descriptions and menu button updated.')
}

main().catch(error => {
  // Network errors can carry the token in their URL.
  const { name, error_code, description } = error ?? {}
  console.error(name === 'Error' ? error.message : [name, error_code, description].filter(Boolean).join(' '))
  process.exit(1)
})

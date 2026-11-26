import { existsSync, statSync } from 'node:fs'
import { mkdir } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { run } from './data.ts'
import { domain, isLoaded, paths, SERVICE, serviceEnvironment } from './host.ts'

// Only the bot's agent. The Mini App's hostname is a route on the existing search tunnel.
const options = Bun.argv.slice(2)
const apply = options[0] === '--apply'

function need(condition: unknown, message: string): asserts condition {
  if (condition) return
  // A dry run lists everything that's missing.
  if (apply) throw new Error(message)
  console.log(`Missing: ${message}`)
}

function plist(label: string, command: string[], environment: Record<string, string>, log: string, cwd: string) {
  const escape = (value: string) => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  const string = (value: string) => `<string>${escape(value)}</string>`
  const variables = Object.entries(environment)
    .map(([key, value]) => `    <key>${key}</key>${string(value)}`)
    .join('\n')
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>${string(label)}
  <key>ProgramArguments</key>
  <array>
${command.map(value => `    ${string(value)}`).join('\n')}
  </array>
  <key>WorkingDirectory</key>${string(cwd)}
  <key>EnvironmentVariables</key>
  <dict>
${variables}
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>15</integer>
  <key>ExitTimeOut</key><integer>25</integer>
  <key>StandardOutPath</key>${string(log)}
  <key>StandardErrorPath</key>${string(log)}
</dict>
</plist>
`
}

async function installAgent() {
  need(existsSync(join(paths.current, 'main.js')), 'a release; run `just telegram-release`')
  need(existsSync(paths.env), `${paths.env} with TELEGRAM_BOT_TOKEN`)
  if (existsSync(paths.env))
    need((statSync(paths.env).mode & 0o077) === 0, `owner-only permissions (chmod 600) on ${paths.env}`)

  const file = join(homedir(), 'Library/LaunchAgents', `${SERVICE}.plist`)
  console.log(`Install and start ${SERVICE}\n  ${file}`)
  if (!apply) return console.log('Dry run: nothing changed.')

  await mkdir(paths.logs, { recursive: true })
  await Bun.write(
    file,
    plist(
      SERVICE,
      [join(paths.current, 'bun'), `--env-file=${paths.env}`, join(paths.current, 'main.js')],
      serviceEnvironment(paths.current),
      join(paths.logs, 'service.log'),
      paths.current,
    ),
  )
  await run('plutil', '-lint', '-s', file)
  if (await isLoaded(SERVICE)) {
    await run('launchctl', 'bootout', `${domain()}/${SERVICE}`)
    for (let tries = 0; tries < 60 && (await isLoaded(SERVICE)); tries++) await Bun.sleep(500)
  }
  await run('launchctl', 'bootstrap', domain(), file)
}

try {
  if (options.length > (apply ? 1 : 0)) throw new Error('Usage: install.ts [--apply]')
  await installAgent()
} catch (error) {
  console.error((error as Error).message)
  process.exit(1)
}

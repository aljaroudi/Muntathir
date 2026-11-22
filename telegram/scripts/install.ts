import { existsSync, statSync } from 'node:fs'
import { chmod, mkdir } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { run } from './data.ts'
import {
  domain,
  HOST,
  isLoaded,
  paths,
  PORT,
  root,
  SERVICE,
  serviceEnvironment,
  TUNNEL_NAME,
  TUNNEL_SERVICE,
} from './host.ts'

const options = new Set(Bun.argv.slice(2))
const apply = options.has('--apply')
const agentsDirectory = join(homedir(), 'Library/LaunchAgents')
const certificate = join(homedir(), '.cloudflared/cert.pem')

function need(condition: unknown, message: string): asserts condition {
  if (condition) return
  // A dry run lists everything that's missing.
  if (apply) throw new Error(message)
  console.log(`Missing: ${message}`)
}

function tunnelConfig(id?: string): string {
  return [
    ...(id ? [`tunnel: ${id}`, `credentials-file: ${JSON.stringify(paths.tunnelCredentials)}`] : []),
    'ingress:',
    `  - hostname: ${HOST}`,
    `    service: http://127.0.0.1:${PORT}`,
    '  - service: http_status:404',
    '',
  ].join('\n')
}

/** Its own tunnel: backend/cloudflare_setup.py replaces the search tunnel's whole ingress list. */
async function installTunnel() {
  const binary = Bun.which('cloudflared')
  need(binary, 'cloudflared is not installed')
  need(existsSync(certificate), 'run `cloudflared tunnel login` first')
  const existing = existsSync(paths.tunnelCredentials)
  console.log(existing ? `Reuse tunnel ${TUNNEL_NAME}` : `Create tunnel ${TUNNEL_NAME}`)
  console.log(`Create DNS CNAME ${HOST}, never overwriting an existing record`)
  console.log(`Write ${paths.tunnelConfig}`)
  if (!apply) return

  await mkdir(root, { recursive: true })
  await chmod(root, 0o700)
  // An explicit config on every command, so ~/.cloudflared/config.yml is never involved.
  const cloudflared = [binary!, 'tunnel', '--config', paths.tunnelConfig, '--origincert', certificate]
  await Bun.write(paths.tunnelConfig, tunnelConfig())
  if (!existing)
    await run(...cloudflared, 'create', '--credentials-file', paths.tunnelCredentials, TUNNEL_NAME)
  await chmod(paths.tunnelCredentials, 0o600)
  const { TunnelID: id } = await Bun.file(paths.tunnelCredentials).json()
  if (typeof id !== 'string' || !/^[0-9a-f-]{36}$/.test(id)) throw new Error('Unexpected tunnel credentials')
  await Bun.write(paths.tunnelConfig, tunnelConfig(id))
  await run(...cloudflared, 'route', 'dns', id, HOST)
  console.log(`Tunnel ready. Check that the record is exactly ${HOST}: a login for another zone appends that zone.`)
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

async function installAgents() {
  const binary = Bun.which('cloudflared')
  need(binary, 'cloudflared is not installed')
  need(existsSync(join(paths.current, 'main.js')), 'a release; run `just telegram-release`')
  need(existsSync(paths.env), `${paths.env} with TELEGRAM_BOT_TOKEN`)
  if (existsSync(paths.env))
    need((statSync(paths.env).mode & 0o077) === 0, `owner-only permissions (chmod 600) on ${paths.env}`)
  need(existsSync(paths.tunnelCredentials), 'the tunnel; run with --tunnel first')

  const agents = [
    {
      label: SERVICE,
      command: [join(paths.current, 'bun'), `--env-file=${paths.env}`, join(paths.current, 'main.js')],
      environment: serviceEnvironment(paths.current),
      log: join(paths.logs, 'service.log'),
      cwd: paths.current,
    },
    {
      // The tunnel gets no token and no .env. Debug logging would record auth headers, so only warnings.
      label: TUNNEL_SERVICE,
      command: [binary ?? 'cloudflared', 'tunnel', '--config', paths.tunnelConfig, '--no-autoupdate', '--metrics', '127.0.0.1:0', '--loglevel', 'warn', 'run'],
      environment: { HOME: homedir() },
      log: join(paths.logs, 'tunnel.log'),
      cwd: root,
    },
  ]
  for (const { label, command, environment, log, cwd } of agents) {
    const file = join(agentsDirectory, `${label}.plist`)
    console.log(`Install and start ${label}\n  ${file}`)
    if (!apply) continue
    await mkdir(paths.logs, { recursive: true })
    await Bun.write(file, plist(label, command, environment, log, cwd))
    await run('plutil', '-lint', '-s', file)
    if (await isLoaded(label)) {
      await run('launchctl', 'bootout', `${domain()}/${label}`)
      for (let tries = 0; tries < 60 && (await isLoaded(label)); tries++) await Bun.sleep(500)
    }
    await run('launchctl', 'bootstrap', domain(), file)
  }
}

try {
  const unknown = [...options].some(option => !['--tunnel', '--agents', '--apply'].includes(option))
  if (unknown || (apply && options.has('--tunnel') === options.has('--agents')))
    throw new Error('Usage: install.ts [--tunnel | --agents] [--apply]')
  const all = !options.has('--tunnel') && !options.has('--agents')
  if (all || options.has('--tunnel')) await installTunnel()
  if (all || options.has('--agents')) await installAgents()
  if (!apply) console.log('Dry run: nothing changed.')
} catch (error) {
  console.error((error as Error).message)
  process.exit(1)
}

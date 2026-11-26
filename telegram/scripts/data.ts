import { Database } from 'bun:sqlite'
import { mkdir } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { DATABASES } from '../src/server/content.ts'

export const repository = resolve(import.meta.dir, '../..')

const SOURCES: Record<(typeof DATABASES)[number], string> = {
  quran: 'apple/Muntathir/Resources/Quran/quran.db',
  'en.qarai': 'apple/Muntathir/Resources/Quran/en.qarai.db',
  hadith: 'build/hadith/dist/hadith.db',
  supplications: 'build/hadith/dist/supplications.db',
  rulings: 'build/rulings/dist/rulings.db',
}
/** Built databases are ignored by Git, so a worktree reads them from the main checkout. */
const GENERATED = ['hadith', 'supplications', 'rulings']

export async function run(...command: string[]): Promise<string> {
  const child = Bun.spawn(command, { cwd: repository, stdout: 'pipe', stderr: 'inherit' })
  const output = await new Response(child.stdout).text()
  if ((await child.exited) !== 0) throw new Error(`Failed: ${command[0]} ${command[1] ?? ''}`)
  return output.trim()
}

/** Clones the databases into [destination] with APFS copy-on-write and returns their digest. */
export async function cloneData(destination: string): Promise<string> {
  const main = dirname(await run('git', 'rev-parse', '--path-format=absolute', '--git-common-dir'))
  const content = Bun.env.MUNTATHIR_CONTENT ?? main
  await mkdir(destination, { recursive: true })
  const digest = new Bun.CryptoHasher('sha256')
  for (const name of DATABASES) {
    const source = join(GENERATED.includes(name) ? content : repository, SOURCES[name])
    const target = join(destination, `${name}.db`)
    await run('cp', '-cf', source, target)
    const db = new Database(target, { readonly: true })
    const result = db.query<{ quick_check: string }, []>('PRAGMA quick_check').all()
    db.close()
    if (result.length !== 1 || result[0]!.quick_check !== 'ok') throw new Error(`Damaged ${name}.db`)
    for await (const chunk of Bun.file(target).stream()) digest.update(chunk)
  }
  return digest.digest('hex').slice(0, 12)
}

if (import.meta.main) {
  console.log(`Content ready: ${await cloneData(resolve(import.meta.dir, '../.data'))}`)
}

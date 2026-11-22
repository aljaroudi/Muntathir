import { cp, mkdir, rm } from 'node:fs/promises'
import { basename, dirname, join, resolve } from 'node:path'

const root = resolve(import.meta.dir, '..')

async function licenses(): Promise<string> {
  const { dependencies } = await Bun.file(join(root, 'package.json')).json()
  // Every installed package, since bundling pulls in transitive ones too.
  const parts: string[] = []
  const manifests: string[] = []
  for (const pattern of ['*/package.json', '@*/*/package.json'])
    for await (const path of new Bun.Glob(pattern).scan({ cwd: join(root, 'node_modules') })) manifests.push(path)
  for (const path of manifests) {
    const folder = join(root, 'node_modules', dirname(path))
    const { name, version, license } = await Bun.file(join(root, 'node_modules', path)).json()
    if (name.startsWith('@types/') || ['typescript', 'bun-types'].includes(name)) continue
    let body = ''
    for await (const file of new Bun.Glob('*').scan({ cwd: folder }))
      if (/^(license|licence|notice)/i.test(file)) body += await Bun.file(join(folder, file)).text()
    parts.push(`${name} ${version} (${license ?? 'see text'})${name in dependencies ? '' : ' [transitive]'}\n\n${body}`)
  }
  return parts.sort().join('\n\n========================================\n\n')
}

/** Builds the service and the Mini App into [destination]. */
export async function build(destination: string) {
  await rm(join(destination, 'app'), { recursive: true, force: true })
  await mkdir(join(destination, 'app'), { recursive: true })
  const define = { 'process.env.NODE_ENV': '"production"' }

  const client = await Bun.build({
    entrypoints: [join(root, 'src/app/main.tsx'), join(root, 'src/app/style.css')],
    outdir: join(destination, 'app/assets'),
    target: 'browser',
    minify: true,
    naming: '[name]-[hash].[ext]',
    define,
  })
  const output = (extension: string) => {
    const file = client.outputs.find(item => item.path.endsWith(extension))
    if (!file) throw new Error(`No ${extension} output`)
    return `assets/${basename(file.path)}`
  }
  const html = (await Bun.file(join(root, 'src/app/index.html')).text())
    .replace('{{script}}', output('.js'))
    .replace('{{style}}', output('.css'))
  await Bun.write(join(destination, 'app/index.html'), html)
  await Bun.write(join(destination, 'app/licenses.txt'), await licenses())

  await Bun.build({
    entrypoints: [join(root, 'src/main.ts')],
    outdir: destination,
    target: 'bun',
    naming: 'main.js',
    define,
  })
  // The bundle can't find geo-tz's data itself: the service runs with GEO_TZ_DATA_PATH set to this.
  await mkdir(join(destination, 'tz'), { recursive: true })
  const data = 'timezones-1970.geojson.geo.dat'
  await cp(join(root, 'node_modules/geo-tz/data', data), join(destination, 'tz', data))
}

if (import.meta.main) {
  await build(join(root, 'dist'))
  console.log('Built dist/')
}

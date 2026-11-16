// Offline query vectors verify source isolation and local hydration without paid query calls.
import { Qdrant, retrieve } from './search.ts'
import { Database } from 'bun:sqlite'

const [workdir, database] = Bun.argv.slice(2)
if (!workdir || !database) throw new Error('Usage: rulings.verify.ts <workdir> <rulings.db>')
const manifest = await Bun.file(`${workdir}/manifest.json`).json()
const state = await Bun.file(`${workdir}/qdrant-progress.json`).json()
if (!state.validated) throw new Error('Import has not validated')
const qdrant = new Qdrant(Bun.env.QDRANT_URL ?? state.url, Bun.env.QDRANT_API_KEY)
const local = new Database(database, { readonly: true })
const query = local.query('SELECT 1 FROM question WHERE authority_code=? AND language_code=? AND site_id=?')
const items = new Map<string, any>(manifest.items.map((item: any) => [item.id, item]))
const texts = new Map<string, any>(manifest.texts.map((text: any) => [text.id, text]))
const scopes = new Set<string>()
for (const passage of manifest.passages) {
  const text = texts.get(passage.text_id)
  const item = items.get(text.item_id)
  if (item.kind !== 'rulings') continue
  const scope = `${item.source_id}:${text.language}`
  if (scopes.has(scope)) continue
  scopes.add(scope)
  const vector = (await Bun.file(`${workdir}/vectors/${passage.input_hash}.json`).json()).slice(0, 1536)
  const norm = Math.hypot(...vector)
  const result = await retrieve(qdrant, state.collection, {
    query: passage.text.slice(0, 512), kinds: ['rulings'], sources: [item.source_id],
    languages: [text.language], limit: 20,
  }, vector.map((value: number) => value / norm), null)
  if (!result.results.length) throw new Error(`No results for ${scope}`)
  if (!result.results.some(hit => hit.kind === 'rulings' && hit.id === item.navigation.id))
    throw new Error(`Self-retrieval failed for ${scope}`)
  for (const hit of result.results) {
    if (hit.kind !== 'rulings' || hit.authority !== item.source_id || hit.language !== text.language)
      throw new Error(`Cross-scope result for ${scope}`)
    if (!query.get(hit.authority, hit.language, hit.id)) throw new Error(`Missing local reference: ${hit.id}`)
  }
  console.log(`${scope}: ${result.results.length} scoped, hydratable results`)
}
local.close()
if (!scopes.size) throw new Error('No rulings in candidate collection')
console.log(`Passed ${scopes.size} authority/language scopes`)

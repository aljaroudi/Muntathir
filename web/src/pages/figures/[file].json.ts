import type { APIRoute } from "astro"
import dataset from "../../../../shared/figures/figures.json"
import schema from "../../../../shared/figures/schema.json?raw"

// Add IDs here once their records have been verified.
const publishedIDs = new Set(["prophet-muhammad", "fatima-al-zahra", "ali-ibn-abi-talib", "hasan-ibn-ali", "husayn-ibn-ali"])

function publishedDataset() {
  const people = dataset.people.filter(person => publishedIDs.has(person.id))
  const unions = dataset.unions.filter(union => union.partner_ids.every(id => publishedIDs.has(id)))
  const unionIDs = new Set(unions.map(union => union.id))
  const parentages = dataset.parentages.filter(
    claim =>
      publishedIDs.has(claim.child_id) &&
      [claim.father_id, claim.mother_id].every(id => id == null || publishedIDs.has(id)) &&
      (claim.union_id == null || unionIDs.has(claim.union_id)),
  )
  const claims = [...people.flatMap(person => [...person.birth_dates, ...person.death_dates]), ...unions, ...parentages]
  const sourceIDs = new Set(claims.flatMap(claim => claim.citations.map(citation => citation.source_id)))
  const sources = dataset.sources.filter(source => sourceIDs.has(source.id))
  return { ...dataset, people, unions, parentages, sources }
}

export function getStaticPaths() {
  return [
    { params: { file: "figures" }, props: { json: JSON.stringify(publishedDataset()) } },
    { params: { file: "schema" }, props: { json: schema } },
  ]
}

export const GET: APIRoute = ({ props }) =>
  new Response(props.json, { headers: { "Content-Type": "application/json; charset=utf-8" } })

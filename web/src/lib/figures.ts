import dataset from "../../../shared/figures/figures.json"
import schema from "../../../shared/figures/schema.json"

type Claim = { citations?: { source_id: string }[]; notes?: string | Record<string, string> }

function legacyClaim<T extends Claim>(claim: T) {
  const notes = claim.notes
  return {
    ...claim,
    citations: claim.citations ?? [],
    ...(notes == null
      ? {}
      : {
          notes:
            typeof notes === "string" ? notes : (notes.en ?? notes.ar ?? Object.values(notes)[0]),
        }),
  }
}

// Installed apps still consume the original string-note, required-citations contract.
export function legacyDataset({ browser_groups: _, ...source } = dataset) {
  const people = source.people
    .filter(person => "verified" in person && person.verified === true)
    .map(person => {
      const {
        verified: _,
        birth_place: _birthPlace,
        death_place: _deathPlace,
        ...published
      } = person as typeof person & {
        verified?: boolean
        birth_place?: Record<string, string>
        death_place?: Record<string, string>
      }
      return {
        ...published,
        birth_dates: person.birth_dates.map(legacyClaim),
        death_dates: person.death_dates.map(legacyClaim),
      }
    })
  const ids = new Set(people.map(person => person.id))
  const unions = source.unions
    .filter(union => union.partner_ids.every(id => ids.has(id)))
    .map(legacyClaim)
  const unionIDs = new Set(unions.map(union => union.id))
  const parentages = source.parentages
    .filter(
      claim =>
        ids.has(claim.child_id) &&
        [claim.father_id, claim.mother_id].every(id => id == null || ids.has(id)) &&
        (claim.union_id == null || unionIDs.has(claim.union_id))
    )
    .map(legacyClaim)
  const claims = [
    ...people.flatMap(person => [...person.birth_dates, ...person.death_dates]),
    ...unions,
    ...parentages,
  ]
  const sourceIDs = new Set(
    claims.flatMap(claim => claim.citations.map(citation => citation.source_id))
  )
  return {
    ...source,
    people,
    unions,
    parentages,
    sources: source.sources.filter(source => sourceIDs.has(source.id)),
  }
}

export function legacySchema() {
  const legacy = structuredClone(schema)
  const { browser_groups: _, ...properties } = legacy.properties
  const definitions = legacy.$defs as unknown as Record<
    string,
    { properties: Record<string, unknown>; required?: string[] }
  >
  delete definitions.person.properties.verified
  delete definitions.person.properties.birth_place
  delete definitions.person.properties.death_place
  for (const name of ["dateClaim", "parentage", "union"]) {
    definitions[name].properties.notes = { type: "string" }
  }
  definitions.dateClaim.required!.push("citations")
  return { ...legacy, properties }
}

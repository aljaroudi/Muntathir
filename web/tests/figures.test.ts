import { describe, expect, test } from "bun:test"
import dataset from "../../shared/figures/figures.json"
import { legacyDataset, legacySchema } from "../src/lib/figures"

describe("legacy figures feed", () => {
  test("publishes verified people and only complete relationships", () => {
    const published = legacyDataset()
    expect("browser_groups" in published).toBe(false)
    expect("browser_groups" in legacySchema().properties).toBe(false)
    const ids = new Set(published.people.map(person => person.id))
    expect([...ids]).toEqual(
      dataset.people
        .filter(person => "verified" in person && person.verified)
        .map(person => person.id)
    )
    expect(published.people.every(person => !("verified" in person))).toBe(true)
    for (const union of published.unions)
      expect(union.partner_ids.every(id => ids.has(id))).toBe(true)
    for (const claim of published.parentages) {
      expect(ids.has(claim.child_id)).toBe(true)
      expect([claim.father_id, claim.mother_id].every(id => id == null || ids.has(id))).toBe(true)
      if (claim.union_id)
        expect(published.unions.some(union => union.id === claim.union_id)).toBe(true)
    }
  })

  test("flattens localized claim notes when a person becomes verified", () => {
    const source = structuredClone(dataset)
    const person = source.people.find(person => person.id === "ali-al-ridha")!
    Object.assign(person, {
      verified: true,
      birth_place: { en: "Birthplace" },
      death_place: { en: "Deathplace" },
    })
    const published = legacyDataset(source).people.find(person => person.id === "ali-al-ridha")!
    expect(published.death_dates[0].notes).toBe("The last day of Safar.")
    expect("birth_place" in published).toBe(false)
    expect("death_place" in published).toBe(false)
  })

  test("keeps notes and citations compatible with released decoders", () => {
    const published = legacyDataset()
    const claims = [
      ...published.people.flatMap(person => [...person.birth_dates, ...person.death_dates]),
      ...published.parentages,
      ...published.unions,
    ]
    for (const claim of claims) {
      expect(Array.isArray(claim.citations)).toBe(true)
      if ("notes" in claim) expect(typeof claim.notes).toBe("string")
      for (const citation of claim.citations)
        expect(published.sources.some(source => source.id === citation.source_id)).toBe(true)
    }
    expect(
      published.people.find(person => person.id === "abbas-ibn-ali")?.death_dates[0].citations
    ).toEqual([])
    const schema = legacySchema()
    expect(schema.$defs.dateClaim.required).toContain("citations")
    expect(schema.$defs.dateClaim.properties.notes as unknown).toEqual({ type: "string" })
    expect("verified" in schema.$defs.person.properties).toBe(false)
  })
})

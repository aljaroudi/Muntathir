import type { APIRoute } from "astro"
import { legacyDataset, legacySchema } from "../../lib/figures"

export function getStaticPaths() {
  return [
    { params: { file: "figures" }, props: { json: JSON.stringify(legacyDataset()) } },
    { params: { file: "schema" }, props: { json: JSON.stringify(legacySchema()) } },
  ]
}

export const GET: APIRoute = ({ props }) =>
  new Response(props.json, { headers: { "Content-Type": "application/json; charset=utf-8" } })

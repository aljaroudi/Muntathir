"""Validate both figure datasets and the calendar's figure references."""

import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent


def load(path):
    return json.loads(path.read_text())


def validate(path, validator):
    data = load(path)
    schema_errors = list(validator.iter_errors(data))
    for error in schema_errors:
        location = list(error.absolute_path)
        candidate = data[location[0]][location[1]] if len(location) >= 2 and isinstance(location[1], int) else None
        record = candidate if isinstance(candidate, dict) else {}
        yield f"{path.name}:{error.json_path} ({record.get('id', 'dataset')}): {error.message}"

    if schema_errors:
        return

    errors = []

    def require(condition, field, message):
        if not condition:
            errors.append(f"{path.name}:{field}: {message}")

    indexes = {}
    for collection in ("people", "parentages", "unions", "sources"):
        index = indexes[collection] = {}
        for row in data[collection]:
            require(row["id"] not in index, f"{collection}.{row['id']}.id", "duplicate ID")
            index[row["id"]] = row

    people, unions, sources = (indexes[key] for key in ("people", "unions", "sources"))
    ancestry = {person: set() for person in people}
    for row in data["parentages"]:
        field = f"parentages.{row['id']}"
        child = row["child_id"]
        parents = [row[key] for key in ("father_id", "mother_id") if row[key] is not None]
        require(child in people, field + ".child_id", "unknown child")
        require(parents and len(set(parents)) == len(parents) and child not in parents,
                field, "invalid parent pair")
        for key in ("father_id", "mother_id"):
            require(row[key] is None or row[key] in people, field + "." + key, "unknown parent")
        if child in people and row["kind"] == "biological":
            ancestry[child].update(parent for parent in parents if parent in people)
        if union_id := row.get("union_id"):
            require(union_id in unions and set(unions[union_id]["partner_ids"]) == set(parents),
                    field + ".union_id", "union must exist and match both parents")

    for row in data["unions"]:
        require(all(partner in people for partner in row["partner_ids"]),
                f"unions.{row['id']}.partner_ids", "unknown partner")

    visited = set()
    active = set()

    def visit(person):
        if person in active:
            require(False, f"people.{person}", "biological ancestry cycle")
            return
        if person not in visited:
            active.add(person)
            for parent in ancestry[person]:
                visit(parent)
            active.remove(person)
            visited.add(person)

    for person in people:
        visit(person)

    def check_date(date, field):
        def bound(point, latest):
            year = point["year"]
            if date["era"] in ("BH", "BCE"):
                year = -year
            month = point.get("month", 12 if latest else 1)
            if date["calendar"] == "hijri":
                # Historical Hijri month lengths depend on observation.
                limit = 30
            else:
                leap_year = year + 1 if date["era"] == "BCE" else year
                leap = leap_year % 4 == 0 and (
                    date["calendar"] == "julian" or leap_year % 100 != 0 or leap_year % 400 == 0
                )
                limit = (31, 28 + leap, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month - 1]
            require(point.get("day", 1) <= limit, field, "day exceeds month length")
            return year, month, point.get("day", limit if latest else 1)

        start = bound(date["start"], False)
        if "end" in date:
            require(start <= bound(date["end"], True), field + ".end", "range ends before it starts")

    for collection in ("people", "parentages", "unions"):
        for row in data[collection]:
            field = f"{collection}.{row['id']}"
            claims = [(field, row)]
            for key in ("birth_dates", "death_dates", "start_dates", "end_dates"):
                for i, date in enumerate(row.get(key, [])):
                    date_field = f"{field}.{key}[{i}]"
                    check_date(date, date_field)
                    claims.append((date_field, date))
            for claim_field, claim in claims:
                for i, citation in enumerate(claim.get("citations", [])):
                    require(citation["source_id"] in sources, f"{claim_field}.citations[{i}].source_id",
                            "unknown source")

    if path.name == "figures.json":
        for event in load(ROOT.parent / "events.json"):
            ids = event.get("figure_ids", [])
            require(isinstance(ids, list) and all(isinstance(i, str) and i in people for i in ids)
                    and len(set(ids)) == len(ids), f"events.{event['id']}.figure_ids",
                    "expected distinct known figure IDs")

    yield from errors


if __name__ == "__main__":
    schema = load(ROOT / "schema.json")
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
    errors = [error for name in ("figures.json", "example.json") for error in validate(ROOT / name, validator)]
    if errors:
        sys.exit("\n".join(errors))
    print("Validated figures, example, and calendar references.")

#!/usr/bin/env python3
"""Prepare, batch-embed, upload, and activate a versioned search corpus."""
import argparse
from decimal import Decimal
import hashlib
import fcntl
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import time
import unicodedata
import urllib.error
import urllib.request
import uuid

MODEL = "gemini-embedding-2"
PROFILE = MODEL + ":3072:search-v1"
BATCH_USD_PER_MILLION_TOKENS = Decimal("0.10")
ROOT = Path(__file__).resolve().parents[1]
NAMESPACE = uuid.UUID("f678aa34-838c-4d55-b4c2-502385d5cc76")


def identity(*parts):
    return str(uuid.uuid5(NAMESPACE, json.dumps(parts, ensure_ascii=False, separators=(",", ":"))))


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def normalize(text):
    text = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.category(c).startswith("M"))
    return re.sub("[\u0640\u06d6-\u06ed]", "", text).translate(str.maketrans("أإآٱى", "ااااي")).lower()


def clean(text):
    # Keep display text intact; remove markup only from embedding inputs.
    return re.sub(r"<[^>]+>", "", re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text))


def chunks(text, max_chars=3500):
    """Code-point offsets into original text; paragraphs first, punctuation then words."""
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        if end < len(text):
            boundaries = list(re.finditer(r"\n\s*\n|[.!?؟؛]\s+|\s+", text[start:end]))
            paragraphs = [m for m in boundaries if "\n" in m.group() and m.start() >= max_chars // 3]
            sentences = [m for m in boundaries if m.group()[0] in ".!?؟؛" and m.start() >= max_chars // 3]
            candidates = paragraphs or sentences or boundaries
            if candidates:
                end = start + candidates[-1].end()
        if text[start:end].strip():
            yield start, end, text[start:end]
        start = end


def atomic_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def read_db(path):
    db = sqlite3.connect(f"file:{Path(path).resolve()}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    return db


def prepare(args):
    output = Path(args.workdir)
    output.mkdir(parents=True, exist_ok=True)
    path = output / "manifest.json"
    if path.exists():
        raise ValueError("Workdir already prepared; resume it or choose a new directory")
    provenance = json.loads(Path(args.provenance).read_text()) if args.provenance else {}
    records, sources = [], {}

    def source(key, name):
        provenance.setdefault(key, {"edition": key, "attribution": name})
        if not all(provenance[key].get(k) for k in ("edition", "attribution")):
            raise ValueError(f"Missing source edition or attribution for {key}")
        sources[key] = {"id": key, "name": name, "provenance": provenance[key]}

    def add(kind, source_id, reference, navigation, title, variants):
        if args.limit and len(records) >= args.limit:
            return
        item_id = identity(kind, source_id, reference)
        records.append({"item": {"id": item_id, "kind": kind, "source_id": source_id,
                                 "reference": reference, "navigation": navigation, "title": title}, "variants": variants})

    if args.quran:
        source("quran", "The Holy Quran")
        translations = []
        for spec in args.translation:
            language, edition, filename = spec.split(":", 2)
            key = "quran:" + edition
            source(key, edition)
            translations.append((language, edition, { (r["sura"], r["aya"]): r["text"] for r in read_db(filename).execute("select sura,aya,text from quran") }))
        for row in read_db(args.quran).execute("select sura,aya,text from quran order by sura,aya"):
            chapter, verse = row["sura"], row["aya"]
            variants = [{"language": "ar", "edition": provenance["quran"]["edition"], "attribution": provenance["quran"]["attribution"], "text": row["text"]}]
            for language, edition, values in translations:
                if values.get((chapter, verse)):
                    variants.append({"language": language, "edition": edition, "attribution": provenance["quran:" + edition]["attribution"], "text": values[(chapter, verse)]})
            add("quran", "quran", {"chapter": chapter, "verse": verse}, {"chapter": chapter, "verse": verse}, f"{chapter}:{verse}", variants)
    if args.hadith:
        db = read_db(args.hadith)
        query = """select h.*, c.file_name, c.name_ar as chapter_name_ar, c.name_en as chapter_name_en,
                   b.name_ar,b.name_en,b.collection_id from hadith h
                   join chapter c on c.id=h.chapter_id join book b on b.id=h.book_id order by h.book_id,c.chapter_idx,h.id_in_book"""
        for row in db.execute(query):
            source_id = row["book_id"]
            source(source_id, row["name_en"] or row["name_ar"])
            nav = {"book": source_id, "chapterFile": row["file_name"], "number": row["id_in_book"], "sourceID": row["source_id"]}
            ref = {"book": source_id, "number": str(row["id_in_book"]), "numbering_scheme": "asset-v6", "chapter_file": row["file_name"]}
            variants = []
            for language, column in [("ar", "arabic"), ("en", "english_text")]:
                if row[column].strip():
                    variants.append({"language": language, "edition": provenance[source_id]["edition"], "attribution": provenance[source_id]["attribution"], "text": row[column]})
            chapter_name = row["chapter_name_en"] or row["chapter_name_ar"] or f"Chapter {row['chapter_idx'] + 1}"
            add("hadith", source_id, ref, nav, f"{row['name_en'] or row['name_ar']} · {chapter_name} · {row['id_in_book']}", variants)
    if getattr(args, "supplications", None):
        with read_db(args.supplications) as db:
            translations = {}
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='supplication_translation'").fetchone():
                for row in db.execute("SELECT * FROM supplication_translation ORDER BY language, edition"):
                    translations.setdefault(row["hadith_id"], []).append(dict(row))
            query = """SELECT h.*, c.file_name, c.name_en AS chapter_en, c.name_ar AS chapter_ar,
                       b.name_en, b.name_ar FROM hadith h JOIN chapter c ON c.id=h.chapter_id
                       JOIN book b ON b.id=h.book_id ORDER BY h.book_id,c.file_name,h.id_in_book"""
            for row in db.execute(query):
                book = row["book_id"]
                source(book, row["name_en"] or row["name_ar"])
                dua_id = identity(book, row["file_name"], row["id_in_book"])
                variants = [{k: t[k] for k in ("language", "edition", "attribution", "text")}
                            for t in translations.get(row["id"], [])]
                for language, column in (("ar", "arabic"), ("en", "english_text")):
                    if row[column].strip() and not any(t["language"] == language and t["text"] == row[column] for t in variants):
                        variants.append({"language": language, "text": row[column], **{
                            k: provenance[book][k] for k in ("edition", "attribution")}})
                add("dua", book, {"dua_id": dua_id}, {"dua_id": dua_id, "locator": f"{book}:{row['file_name']}:{row['id_in_book']}"},
                    row["chapter_en"] or row["chapter_ar"] or row["name_en"] or row["name_ar"], variants)

    if args.dua:
        for row in json.loads(Path(args.dua).read_text()):
            source(row["source_id"], row["source_name"])
            add("dua", row["source_id"], {"dua_id": row["id"]}, {"dua_id": row["id"]}, row["title"], row["texts"])

    if getattr(args, "rulings", None):
        db = read_db(args.rulings)
        if db.execute("PRAGMA application_id").fetchone()[0] != 1179809601 or db.execute("PRAGMA user_version").fetchone()[0] not in (1, 2):
            raise ValueError("Incompatible rulings database")
        for authority in db.execute("SELECT * FROM authority ORDER BY sort_order"):
            source(authority["code"], authority["name_en"] or authority["name_ar"])
        for row in db.execute("SELECT * FROM question ORDER BY authority_code, language_code, site_id"):
            if not (row["question"] + row["answer"]).strip():
                raise ValueError("Empty rulings entry")
            ref = {"authority": row["authority_code"], "language": row["language_code"], "id": row["site_id"]}
            title = sources[row["authority_code"]]["name"] + " · " + row["site_id"]
            if "context" in row.keys() and row["site_id"].startswith("book:"):
                title = row["context"]
            add("rulings", row["authority_code"], ref, ref, title,
                [{"language": row["language_code"], "edition": row["url"],
                  "attribution": sources[row["authority_code"]]["name"],
                  "text": row["question"] + "\n\n" + row["answer"]}])
        db.close()

    if getattr(args, "figures", None):
        source("figures", "Muntathir figure library")
        for person in json.loads(Path(args.figures).read_text())["people"]:
            variants = []
            for language in sorted(person["names"].keys() | person["display_names"].keys()):
                names = person["names"].get(language, {})
                parts = [person["display_names"].get(language, "")]
                for value in names.values():
                    parts.extend(value if isinstance(value, list) else [value])
                variants.append({"language": language, "edition": "figures", "attribution": "Muntathir figure library",
                                 "text": " ".join(dict.fromkeys(filter(None, parts)))})
            ref = {"id": person["id"]}
            add("figure", "figures", ref, ref, person["display_names"]["en"], variants)

    if not records:
        raise ValueError("No content selected")
    if args.pilot:
        judged = json.loads((Path(__file__).with_name("evaluation.json")).read_text())["queries"]
        required = {key for query in judged for key in query["relevant"]}
        selected = {r["item"]["id"] for r in records if r["item"]["id"] in required}
        # Include both evaluated positives and a deterministic spread of distractors.
        for kind in ("quran", "hadith", "dua", "rulings", "figure"):
            candidates = [r for r in records if r["item"]["kind"] == kind]
            if candidates:
                step = max(1, len(candidates) // 100)
                selected.update(r["item"]["id"] for r in candidates[::step][:100])
        records = [r for r in records if r["item"]["id"] in selected]
    # A new revision keeps earlier display text and passage boundaries available for rollback.
    revision = str(uuid.uuid4())
    texts, passages, items = [], [], []
    for record in records:
        item = record["item"]
        items.append(item)
        for variant in record["variants"]:
            full = variant["text"]
            text_id = identity(revision, item["id"], variant["language"], variant["edition"])
            texts.append({"id": text_id, "revision_id": revision, "item_id": item["id"], "language": variant["language"],
                          "edition": variant["edition"], "attribution": variant["attribution"], "full_text": full})
            parts = [(0, len(full), full)] if item["kind"] == "quran" else list(chunks(full))
            for ordinal, (start, end, value) in enumerate(parts, 1):
                prefix = item["title"]
                embedding_input = f"title: {prefix} | text: {clean(value)}"
                if len(embedding_input.encode()) > 8000:
                    raise ValueError(f"Passage {item['id']} exceeds the conservative token budget; split it before embedding")
                passages.append({"id": identity(text_id, ordinal), "text_id": text_id, "ordinal": ordinal,
                                 "start_offset": start, "end_offset": end, "text": value, "search_text": normalize(clean(value)),
                                 "input": embedding_input, "input_hash": digest(PROFILE + ":" + embedding_input)})
    # UTF-8 byte length is a conservative token estimate, not a tokenizer assertion.
    token_upper_bound = sum(len(p["input"].encode()) for p in passages)
    manifest = {"revision": revision, "profile": PROFILE, "sources": list(sources.values()), "items": items,
                "texts": texts, "passages": passages, "jobs": [],
                "estimate": {"token_upper_bound": token_upper_bound, "batch_usd_upper_bound": float(batch_cost(token_upper_bound))}}
    atomic_json(path, manifest)
    print(json.dumps({"items": len(items), "passages": len(passages), **manifest["estimate"]}, indent=2))


def validate_vector(vector):
    if not isinstance(vector, list) or len(vector) != 3072 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in vector) or not any(vector):
        raise ValueError("Invalid 3072-dimensional embedding")


def batch_cost(utf8_bytes):
    # One token per UTF-8 byte is a conservative estimate for these text inputs.
    return utf8_bytes * BATCH_USD_PER_MILLION_TOKENS / 1_000_000


def submission_plan(manifest, vector_dir, reuse):
    inputs = {p["input_hash"]: p for p in manifest["passages"]}
    cached = {p.stem for p in vector_dir.glob("*.json")} & inputs.keys()
    reusable = ({p.stem for p in reuse.glob("*.json")} & inputs.keys()) - cached if reuse else set()
    reserved_jobs = [job for job in manifest["jobs"] if job["name"] or job["state"] != "failed"]
    pending = {key for job in reserved_jobs if job["state"] not in ("done", "failed") for key in job["keys"]}
    pending -= cached | reusable
    missing = [p for key, p in inputs.items() if key not in cached and key not in reusable and key not in pending]
    missing_bytes = sum(len(p["input"].encode()) for p in missing)
    reserved_bytes = sum(len(inputs[key]["input"].encode()) for job in reserved_jobs for key in job["keys"])
    return reusable, missing, {
        "cached": len(cached), "reusable": len(reusable), "pending": len(pending), "missing": len(missing),
        "missing_utf8_bytes": missing_bytes,
        "batch_usd_per_million_tokens": str(BATCH_USD_PER_MILLION_TOKENS),
        "new_batch_usd_estimate": str(batch_cost(missing_bytes)),
        "reserved_batch_usd_estimate": str(batch_cost(reserved_bytes)),
        "total_batch_usd_estimate": str(batch_cost(reserved_bytes + missing_bytes)),
    }


def gemini_client():
    from google import genai
    return genai.Client(api_key=os.environ["GEMINI_API_KEY"])


def run(args):
    path = Path(args.workdir) / "manifest.json"
    manifest = json.loads(path.read_text())
    if manifest["profile"] != PROFILE:
        raise ValueError("Embedding profile mismatch")
    work = path.parent
    vector_dir = work / "vectors"
    if args.command in ("estimate", "submit"):
        previous = Path(args.reuse) / "vectors" if args.reuse else None
        reusable, values, estimate = submission_plan(manifest, vector_dir, previous)
        print(json.dumps(estimate, indent=2), flush=True)
        if args.command == "estimate":
            return
        if values:
            if args.max_usd is None or Decimal(estimate["total_batch_usd_estimate"]) > args.max_usd:
                raise ValueError("Estimated revision cost exceeds --max-usd or no cap was supplied")
            if any(job["state"] == "submitting" for job in manifest["jobs"]):
                raise ValueError("Poll to reconcile interrupted submissions before submitting new jobs")
        vector_dir.mkdir(exist_ok=True)
        # Stored vectors are immutable and keyed by exact input hash.
        for key in reusable:
            name = key + ".json"
            candidate = previous / name
            vector = json.loads(candidate.read_text())
            validate_vector(vector)
            if candidate.stat().st_dev == vector_dir.stat().st_dev:
                os.link(candidate, vector_dir / name)
            else:
                atomic_json(vector_dir / name, vector)
        if not values:
            return
        client = gemini_client()
        for offset in range(0, len(values), 10000):
            group = values[offset:offset + 10000]
            batch_file = work / f"requests-{len(manifest['jobs'])}.jsonl"
            with batch_file.open("w") as handle:
                for p in group:
                    handle.write(json.dumps({"key": p["input_hash"], "request": {"content": {"parts": [{"text": p["input"]}]}, "output_dimensionality": 3072}}, ensure_ascii=False) + "\n")
            uploaded = client.files.upload(file=str(batch_file), config={"mime_type": "application/jsonl"})
            # Persist submission intent before the billable operation. An interrupted submission
            # must be reconciled by job display name rather than automatically paid for again.
            job = {"name": None, "display_name": f"{manifest['revision']}-{len(manifest['jobs'])}", "state": "submitting", "keys": [p["input_hash"] for p in group]}
            manifest["jobs"].append(job); atomic_json(path, manifest)
            try:
                result = client.batches.create_embeddings(model=MODEL, src={"file_name": uploaded.name}, config={"display_name": job["display_name"]})
            except Exception as error:
                # Definite rejections can be retried; connection failures remain
                # ambiguous and must be reconciled before another paid request.
                if getattr(error, "code", None) in (400, 401, 403, 404, 429):
                    job["state"] = "failed"
                    atomic_json(path, manifest)
                if getattr(error, "code", None) == 429:
                    print("Concurrent batch quota reached; poll accepted jobs, then submit remaining inputs", flush=True)
                    return
                raise
            job.update(name=result.name, state="pending"); atomic_json(path, manifest)
            print(f"Accepted batch {len(manifest['jobs'])}: {len(group)} inputs", flush=True)
        print(f"Submitted {len(values)} missing embeddings")
    elif args.command == "poll":
        vector_dir.mkdir(exist_ok=True)
        client = gemini_client()
        for job in manifest["jobs"]:
            if job["state"] in ("done", "failed"):
                continue
            if not job["name"]:
                matches = [j for j in client.batches.list() if j.display_name == job["display_name"]]
                if len(matches) != 1:
                    raise ValueError(f"Reconcile interrupted submission {job['display_name']} in AI Studio before retrying")
                job.update(name=matches[0].name, state="pending")
                atomic_json(path, manifest)
            result = client.batches.get(name=job["name"])
            state = str(result.state)
            if "SUCCEEDED" in state:
                output_path = work / (job["name"].split("/")[-1] + ".results.jsonl")
                if not output_path.exists():
                    temporary = output_path.with_suffix(".tmp")
                    temporary.write_bytes(client.files.download(file=result.dest.file_name))
                    temporary.replace(output_path)
                failures = []
                keys = set(job["keys"])
                tokens = 0
                with output_path.open() as output:
                    for line in output:
                        record = json.loads(line)
                        key = record["key"]
                        if key not in keys:
                            raise ValueError("Unexpected batch result key")
                        if record.get("error"):
                            failures.append(key); continue
                        response = record.get("response", {})
                        vector = response.get("embedding", {}).get("values")
                        validate_vector(vector)
                        tokens += response.get("tokenCount") or response.get("usageMetadata", {}).get("promptTokenCount", 0) or 0
                        filename = vector_dir / (key + ".json")
                        if not filename.exists():
                            atomic_json(filename, vector)
                job["state"] = "done"
                job["failed_keys"] = failures
                job["reported_tokens"] = tokens
                atomic_json(path, manifest)
                output_path.unlink()
            elif any(s in state for s in ("FAILED", "CANCELLED", "EXPIRED")):
                job["state"] = "failed"
                atomic_json(path, manifest)
            print(f"{job['name']}: {job['state']}")
    elif args.command in ("upload", "activate"):
        from qdrant_import import Client, import_corpus, activate
        (import_corpus if args.command == "upload" else activate)(work, Client())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "estimate", "submit", "poll", "upload", "activate"])
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--quran")
    parser.add_argument("--translation", action="append", default=[], help="language:edition:SQLite path")
    parser.add_argument("--hadith")
    parser.add_argument("--figures")
    parser.add_argument("--dua")
    parser.add_argument("--supplications", help="Built Supplications SQLite database")
    parser.add_argument("--rulings")
    parser.add_argument("--provenance")
    parser.add_argument("--limit", type=int, help="Pilot item limit")
    parser.add_argument("--pilot", action="store_true", help="Include judged positives and representative distractors")
    parser.add_argument("--reuse", help="Reuse a previous workdir's exact-input vectors")
    parser.add_argument("--max-usd", type=Decimal, help="Maximum estimated Gemini Batch cost for this revision")
    args = parser.parse_args()
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be positive")
    if args.max_usd is not None and (not args.max_usd.is_finite() or args.max_usd < 0):
        parser.error("--max-usd must be finite and nonnegative")
    try:
        work = Path(args.workdir)
        work.mkdir(parents=True, exist_ok=True)
        with (work / ".lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            prepare(args) if args.command == "prepare" else run(args)
    except BlockingIOError:
        parser.exit(1, "Another importer is using this workdir\n")
    except (ValueError, KeyError, RuntimeError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()

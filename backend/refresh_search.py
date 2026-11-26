"""Refresh the active corpus from locally built reader databases."""
from argparse import Namespace
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

import ingest
from qdrant_import import Client
from serve import environment


def read(path):
    return json.loads(path.read_text())


def active(client):
    return next(row["collection_name"] for row in client.call("GET", "/aliases")["aliases"]
                if row["alias_name"] == "search")


def prior_workdir(base, collection):
    for progress in sorted(base.glob("*/qdrant-progress.json")):
        state = read(progress)
        if state["collection"] == collection and state.get("validated"):
            if (progress.parent / "manifest.json").is_file() and (progress.parent / "vectors").is_dir():
                return progress.parent
    raise ValueError(f"No validated local manifest and vectors for active collection {collection}")


def reusable_workdirs(base, prior, current):
    """The active workdir first, then every other workdir whose vectors share the embedding profile."""
    others = []
    for manifest in sorted(base.glob("*/manifest.json")):
        directory = manifest.parent
        if directory in (prior, current) or not (directory / "vectors").is_dir():
            continue
        # Manifests are huge; "profile" is written within the first few bytes.
        with manifest.open(encoding="utf-8") as handle:
            match = re.search(r'"profile":\s*"([^"]+)"', handle.read(512))
        if match and match[1] == ingest.PROFILE:
            others.append(directory)
    return [prior, *others]


def keys(manifest):
    """Compare corpus content independently of generated revision, text and passage IDs."""
    texts = {row["id"]: row for row in manifest["texts"]}
    passages = []
    for row in manifest["passages"]:
        text = texts[row["text_id"]]
        passages.append([text["item_id"], text["language"], text["edition"],
                         {k: v for k, v in row.items() if k not in ("id", "text_id")}])
    return {
        "profile": manifest["profile"],
        "sources": sorted((row for row in manifest["sources"]), key=lambda row: row["id"]),
        "items": sorted(manifest["items"], key=lambda row: row["id"]),
        "texts": sorted(({k: v for k, v in row.items() if k not in ("id", "revision_id")}
                         for row in texts.values()), key=lambda row: (row["item_id"], row["language"], row["edition"])),
        "passages": sorted(passages, key=lambda row: (*row[:3], row[3]["ordinal"])),
    }


def preserve_other_sources(candidate, prior):
    sources = {row["id"] for row in candidate["sources"]}
    rebuilt = {(row["kind"], row["source_id"]) for row in candidate["items"]}
    retained = [row for row in prior["items"] if (row["kind"], row["source_id"]) not in rebuilt]
    item_ids = {row["id"] for row in retained}
    candidate["items"].extend(retained)
    candidate["sources"].extend(row for row in prior["sources"]
                                if row["id"] in {item["source_id"] for item in retained} - sources)
    text_ids = {}
    for row in prior["texts"]:
        if row["item_id"] in item_ids:
            text_id = ingest.identity(candidate["revision"], row["item_id"], row["language"], row["edition"])
            text_ids[row["id"]] = text_id
            candidate["texts"].append(dict(row, id=text_id, revision_id=candidate["revision"]))
    for row in prior["passages"]:
        if row["text_id"] in text_ids:
            text_id = text_ids[row["text_id"]]
            candidate["passages"].append(dict(row, id=ingest.identity(text_id, row["ordinal"]), text_id=text_id))


def report(manifest, work, reuse):
    reusable, missing, estimate = ingest.submission_plan(manifest, work / "vectors", [d / "vectors" for d in reuse])
    texts = {row["id"]: row["item_id"] for row in manifest["texts"]}
    kinds = {row["id"]: row["kind"] for row in manifest["items"]}
    missing_by_hash = {p["input_hash"]: p for p in missing}
    for kind, label in (("quran", "Quran"), ("hadith", "Hadith"), ("dua", "Supplications"), ("rulings", "Rulings"), ("figure", "Figures")):
        inputs = {p["input_hash"] for p in manifest["passages"] if kinds[texts[p["text_id"]]] == kind}
        cost = ingest.batch_cost(sum(len(missing_by_hash[key]["input"].encode()) for key in inputs & missing_by_hash.keys()))
        print(f"{label}: {len(inputs & reusable):,} reusable, "
              f"{len(inputs & missing_by_hash.keys()):,} missing, ${cost:.6f}")
    total = Decimal(estimate["total_batch_usd_estimate"])
    print(f"Total: {estimate['missing']:,} missing, {estimate['reusable']:,} reusable, "
          f"{estimate['pending']:,} pending, ${total:.6f} including prior submissions", flush=True)
    return estimate, total


def authorize(total, cap):
    if total <= cap:
        return cap
    if not sys.stdin.isatty() or input(f"Approve estimated revision cost of ${total:.6f}? [y/N] ").strip().lower() not in {"y", "yes"}:
        raise ValueError("Embedding submission requires approval above --max-budget")
    return total


def alias(client, collection):
    client.call("POST", "/collections/aliases", {"actions": [
        {"delete_alias": {"alias_name": "search"}},
        {"create_alias": {"alias_name": "search", "collection_name": collection}},
    ]})


def public_results(env, body):
    url = env.get("SEARCH_PUBLIC_URL", "https://search.xn--pgbou4cf.com/v1/search")
    # Cloudflare rejects urllib's default user agent (error 1010).
    req = urllib.request.Request(url, json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "User-Agent": "Muntathir/1.0"})
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)["results"]


def smoke(env):
    # Allow the API's cached collection alias to expire after activation.
    deadline = time.monotonic() + 35
    while not public_results(env, {"query": "Prophet Muhammad", "kinds": ["figure"]}):
        if time.monotonic() >= deadline:
            raise ValueError("Figure index unavailable after activation")
        time.sleep(3)
    for kind, query, filters in (
        ("quran", "mercy and forgiveness", {}),
        ("hadith", "honesty in trade", {"sources": ["bukhari"]}),
        ("rulings", "make up missed daily prayers", {"sources": ["sistani"], "languages": ["en"]}),
        ("dua", "supplication for forgiveness", {}),
        (None, "Prophet Muhammad", {}),
    ):
        results = public_results(env, {"query": query, **({"kinds": [kind]} if kind else {}), **filters})
        allowed = {kind} if kind else {"quran", "hadith", "rulings", "dua"}
        if not results or any(row["kind"] not in allowed for row in results):
            raise ValueError(f"Production smoke test failed for {kind}")


def promote(client, collection, target, work, activate, env):
    if active(client) != collection:
        raise ValueError("Production alias changed during validation. Rerun against the new revision.")
    ingest.atomic_json(work / "rollback.json", {"previous": collection, "candidate": target})
    activate()
    try:
        smoke(env)
    except Exception:
        if active(client) == target:
            alias(client, collection)
        raise
    print(f"Activated and smoke-tested {target}")


def refresh(root, quran, hadith, rulings, cap, *, dry_run=False):
    env = environment()
    client = Client(env.get("QDRANT_URL"), api_key=env.get("QDRANT_API_KEY"))
    try:
        collection = active(client)
    except StopIteration as error:
        raise ValueError("Qdrant has no active search alias") from error
    base = root / "backend/work"
    prior = prior_workdir(base, collection)
    previous = read(prior / "manifest.json")
    quran = root / quran
    hadith = root / hadith
    rulings = root / rulings
    translations = []
    for database in sorted(quran.glob("*.db")):
        edition = database.stem
        if edition != "quran":
            language = {"zh.jian": "zh-Hans", "zh.majian": "zh-Hant"}.get(edition, edition.split(".")[0])
            translations.append(f"{language}:{edition}:{database}")
    if len(translations) != 13:
        raise ValueError("Expected 13 Quran translation databases")
    python = root / "backend/.venv/bin/python"
    python = str(python) if python.is_file() else sys.executable

    def run(*args, **overrides):
        subprocess.run(args, cwd=root, env={**env, **overrides}, check=True)

    with tempfile.TemporaryDirectory(dir=None if dry_run else base) as temp:
        provenance = Path(temp) / "provenance.json"
        ingest.atomic_json(provenance, {row["id"]: row["provenance"] for row in previous["sources"]})
        ingest.prepare(Namespace(workdir=temp, quran=quran / "quran.db", translation=translations,
                                 hadith=hadith / "hadith.db", supplications=hadith / "supplications.db",
                                 rulings=rulings, figures=root / "shared/figures/figures.json", dua=None, provenance=provenance, limit=None, pilot=False))
        candidate = read(Path(temp) / "manifest.json")
        preserve_other_sources(candidate, previous)
        content = keys(candidate)
        if content == keys(previous):
            print("Search corpus unchanged")
            return
        fingerprint = hashlib.sha256(json.dumps(content, sort_keys=True).encode()).hexdigest()
    work = base / ("refresh-" + fingerprint)
    if (work / "manifest.json").exists():
        candidate = read(work / "manifest.json")
    reuse = reusable_workdirs(base, prior, work)
    estimate, total = report(candidate, work, reuse)
    print("New embeddings required" if estimate["missing"] or estimate["pending"] else "Index update requires no new embeddings")
    if dry_run:
        return
    work.mkdir(exist_ok=True)
    if not (work / "manifest.json").exists():
        ingest.atomic_json(work / "manifest.json", candidate)

    def command(action, *args):
        run(python, "backend/ingest.py", action, "--workdir", str(work), *args)

    # Poll once per invocation. Gemini Batch can take hours, and the saved revision resumes on rerun.
    if any(job["state"] not in {"done", "failed"} for job in candidate["jobs"]):
        command("poll")
        candidate = read(work / "manifest.json")
        estimate, total = report(candidate, work, reuse)
    if estimate["missing"] or estimate["reusable"]:
        approval = work / "budget.json"
        approved = max(cap, Decimal(read(approval)["approved_usd"])) if approval.exists() else cap
        if estimate["missing"] and total > approved:
            approved = authorize(total, approved)
            ingest.atomic_json(approval, {"approved_usd": str(approved)})
        command("submit", *(arg for directory in reuse for arg in ("--reuse", str(directory))), "--max-usd", str(approved))
        candidate = read(work / "manifest.json")
        estimate, _ = report(candidate, work, reuse)
    if estimate["pending"] or estimate["missing"]:
        print(f"Search refresh pending. Rerun this command to resume {work.name}.")
        return
    command("upload")
    target = read(work / "qdrant-progress.json")["collection"]
    exact = work / "exact-1536.json"
    run(python, "backend/exact_reference.py", "--corpus", str(work), "--output", str(exact))
    run("bun", "backend/api/verify.ts", "quality", str(work / "quality.json"), "backend/evaluation.json",
        str(exact), SEARCH_COLLECTION=target)
    run("bun", "backend/api/rulings.verify.ts", str(work), str(rulings))
    for name, rate, seconds in (("sustained", "2", "60"), ("burst", "20", "10")):
        run("bun", "backend/api/verify.ts", "load", str(work / f"{name}.json"),
            SEARCH_COLLECTION=target, TEST_RATE=rate, TEST_SECONDS=seconds)
    # An older API rejects the new kind. Keep its active index intact until the API is upgraded.
    public_results(env, {"query": "Prophet Muhammad", "kinds": ["figure"]})
    promote(client, collection, target, work, lambda: command("activate"), env)

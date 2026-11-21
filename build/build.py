#!/usr/bin/env python3
"""Build reader databases, package Xcode assets, and refresh search."""
import argparse
from decimal import Decimal
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
QURAN = Path("apple/Muntathir/Resources/Quran")
HADITH = Path("build/hadith/dist")
RULINGS = Path("build/rulings/dist/rulings.db")
ARCHIVES = Path("apple/build/AssetPacks/archives")
SIZES = Path("apple/Muntathir/Resources/AssetDownloadSizes.json")
MANIFESTS = Path("apple/AssetPacks/manifests")
sys.path[:0] = [str(ROOT / "backend"), str(ROOT / MANIFESTS.parent)]
import assets
from assets import archive_matches, db_hash
from refresh_search import refresh


def run(*args, **kwargs):
    subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def install(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    os.replace(source, target)


def build_assets(stage):
    run("bash", "build/quran/build.sh", stage / "quran", stage / QURAN)
    hadith_builder = ("build/hadith/build.py", "--sittah", "--four", "--output", stage / HADITH / "hadith.db")
    if sys.version_info >= (3, 14):
        run(sys.executable, *hadith_builder)
    else:
        run("uv", "run", *hadith_builder)
    run(sys.executable, "build/rulings/build.py", "--output", stage / RULINGS)
    shutil.copytree(ROOT / MANIFESTS, stage / MANIFESTS)
    packs = (assets.validate_quran(stage, stage / MANIFESTS)
             + assets.validate_hadith("hadith", stage, stage / MANIFESTS)
             + assets.validate_hadith("supplications", stage, stage / MANIFESTS)
             + assets.validate_rulings(stage, stage / MANIFESTS))
    sizes = json.loads((ROOT / SIZES).read_text()) if (ROOT / SIZES).exists() else {}
    sermons = Path("shared/sermons/sermons.db")
    run(sys.executable, "build/sermons/build.py", "--output", stage / sermons)
    replacements = {stage / sermons: ROOT / sermons}
    for path in packs:
        pack = json.loads(path.read_text())
        name = path.stem
        archive = ROOT / ARCHIVES / f"{name}.aar"
        selected = [Path(entry["fileSource"]) for entry in pack["fileSelectors"]]
        bundled = [QURAN / f"{id}.db" for id in ("quran", "en.qarai")] if name == "quran-translations" else []
        files = selected + bundled
        changed = [f for f in files if not (ROOT / f).exists() or db_hash(ROOT / f) != db_hash(stage / f)]
        replacements.update((stage / f, ROOT / f) for f in changed)
        if archive_matches(archive, pack, stage, stage):
            sizes[name] = archive.stat().st_size
        else:
            output = stage / archive.name
            run("xcrun", "ba-package", "package", path, "--output-path", output)
            sizes[name] = output.stat().st_size
            replacements[output] = archive
        installed = sum((stage / f).stat().st_size for f in files)
        previous = sum((ROOT / f).stat().st_size for f in files if (ROOT / f).exists())
        old_archive = archive.stat().st_size if archive.exists() else 0
        label = "Quran" if bundled else name.capitalize()
        detail = f", bundled {sum((stage / f).stat().st_size for f in bundled):,} B" if bundled else ""
        print(f"{label}: {'changed' if changed else 'unchanged'}, installed {installed:,} B "
              f"({installed - previous:+,} B){detail}, archive {sizes[name]:,} B "
              f"({sizes[name] - old_archive:+,} B)", flush=True)
    metadata = json.dumps(sizes, indent=2) + "\n"
    if not (ROOT / SIZES).exists() or (ROOT / SIZES).read_text() != metadata:
        (stage / "sizes.json").write_text(metadata)
        replacements[stage / "sizes.json"] = ROOT / SIZES
    for source, target in replacements.items():
        install(source, target)
    for path in (stage / "quran").glob("*.db"):
        install(path, ROOT / "build/quran/dist" / path.name)
    for report in (stage / HADITH).glob("*.csv"):
        install(report, ROOT / HADITH / report.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-budget", type=Decimal, default=Decimal("10"), metavar="USD")
    parser.add_argument("--dry-run", action="store_true", help="Estimate from existing databases without writes")
    parser.add_argument("--assets-only", action="store_true", help="Build and package without refreshing search")
    args = parser.parse_args()
    if not args.max_budget.is_finite() or args.max_budget < 0:
        parser.error("--max-budget must be finite and nonnegative")
    try:
        if args.dry_run:
            if not args.assets_only:
                refresh(ROOT, QURAN, HADITH, RULINGS, args.max_budget, dry_run=True)
            return
        work = ROOT / "apple/build/AssetPacks"
        work.mkdir(parents=True, exist_ok=True)
        with (work / ".build.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with tempfile.TemporaryDirectory(dir=work) as stage:
                build_assets(Path(stage))
            if not args.assets_only:
                refresh(ROOT, QURAN, HADITH, RULINGS, args.max_budget)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Package Hadith and Quran asset packs and verify shipping bundles; no network or credentials."""
import argparse
import json
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
MANIFESTS = Path(__file__).parent / 'manifests'


def validate_quran():
    sources = ROOT / 'apple/Muntathir/Resources/Quran'
    expected = {p.stem for p in sources.glob('*.db') if p.stem not in {'quran', 'en.qarai'}}
    path = MANIFESTS / 'quran-translations.json'
    pack = json.loads(path.read_text())
    assert pack['assetPackID'] == 'quran-translations'
    assert pack['downloadPolicy'] == {'onDemand': {}} and 'language' not in pack
    assert pack['platforms'] == ['iOS']
    found = set()
    for selector in pack['fileSelectors']:
        source = (path.parent / pack['sourceRoot'] / selector['fileSource']).resolve()
        translation = source.stem
        assert translation in expected and translation not in found, f'Unexpected/duplicate translation: {translation}'
        assert source == sources / f'{translation}.db'
        assert selector['fileDestination'] == f'Quran/{translation}.db'
        with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as db:
            assert db.execute('PRAGMA quick_check').fetchone() == ('ok',), source
            assert db.execute('SELECT count(*), min("index"), max("index") FROM quran WHERE trim(text) != ""').fetchone() == (6236, 1, 6236), source
        found.add(translation)
    assert found == expected and len(found) == 12, 'Expected exactly 12 downloadable translations'
    return [path]


def validate_hadith(pack_id="hadith"):
    folder = "Hadith" if pack_id == "hadith" else "Supplications"
    path = MANIFESTS / f'{pack_id}.json'
    pack = json.loads(path.read_text())
    selector, = pack['fileSelectors']
    source = (path.parent / pack['sourceRoot'] / selector['fileSource']).resolve()
    assert pack['assetPackID'] == pack_id
    assert pack['downloadPolicy'] == {'onDemand': {}} and 'language' not in pack
    assert pack['platforms'] == ['iOS']
    assert source == ROOT / f'build/hadith/dist/{pack_id}.db'
    assert selector['fileDestination'] == f'{folder}/{pack_id}.db'
    with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as db:
        assert db.execute('PRAGMA quick_check').fetchone() == ('ok',)
        assert db.execute('PRAGMA application_id').fetchone() == (1230262606,)
        assert db.execute('PRAGMA user_version').fetchone() == (6,)
        assert db.execute('SELECT count(*) FROM hadith').fetchone()[0] > 0
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
        prayer_count = db.execute("SELECT count(*) FROM hadith h JOIN book b ON b.id=h.book_id WHERE b.collection_id='openiti-Sahifa-Sajjadiyya'").fetchone()[0]
        assert prayer_count == (55 if pack_id == 'supplications' else 0)
        # Never publish experimental mappings accidentally.
        assert not db.execute("SELECT name FROM sqlite_master WHERE name IN ('word_form','root','narrator','hadith_relation')").fetchall()
        assert [r[1] for r in db.execute('PRAGMA table_info(hadith_words)')] == ['text']
        for table in ('hadith_words', 'hadith_fts', 'hadith_en'):
            db.execute(f'SELECT rowid FROM {table} WHERE {table} MATCH ? LIMIT 1', ('test',)).fetchall()
    return [path]


def check_bundle(path):
    path = Path(path)
    if path.suffix == '.ipa':
        with zipfile.ZipFile(path) as archive:
            files = archive.namelist()
    else:
        assert path.is_dir() and path.suffix == '.app', 'Expected an .app directory or .ipa'
        files = [str(f.relative_to(path)) for f in path.rglob('*') if f.is_file()]
    expected = {'quran.db', 'en.qarai.db'}
    app_databases = {Path(f).name for f in files if f.endswith('.db') and '.appex/' not in f and '.xctest/' not in f and '/Watch/' not in f}
    widget_databases = {Path(f).name for f in files if f.endswith('.db') and 'MuntathirWidgets.appex/' in f}
    assert app_databases == expected, f'Unexpected app databases: {app_databases}'
    assert widget_databases == expected, f'Unexpected widget databases: {widget_databases}'
    assert any('Extensions/MuntathirAssetDownloader.appex/' in f for f in files), 'Missing Hadith downloader extension'
    def metadata(relative):
        if path.suffix == '.ipa':
            with zipfile.ZipFile(path) as archive:
                name, = [f for f in files if f.endswith('.app/' + relative) and '/Watch/' not in f and '.appex/' not in f.split('/' + relative)[0]]
                return plistlib.loads(archive.read(name))
        return plistlib.loads((path / relative).read_bytes())
    if path.suffix == '.ipa':
        with zipfile.ZipFile(path) as archive:
            size_file, = [f for f in files if f.endswith('.app/AssetDownloadSizes.json') and '/Watch/' not in f]
            sizes = json.loads(archive.read(size_file))
    else:
        sizes = json.loads((path / 'AssetDownloadSizes.json').read_text())
    assert all(isinstance(sizes.get(pack), int) and sizes[pack] > 0 for pack in ('hadith', 'supplications', 'quran-translations')), 'Missing download size estimates'
    info = metadata('Info.plist')
    downloader = metadata('Extensions/MuntathirAssetDownloader.appex/Info.plist')
    assert downloader.get('CFBundleDisplayName'), 'Missing downloader display name required by App Store validation'
    assert info.get('BAHasManagedAssetPacks') is True
    assert info.get('BAUsesAppleHosting') is True
    assert info.get('BAAppGroupID') == 'group.com.aljaroudi.Muntathir'

    assert not any(Path(f).name in {'hadith.db', 'supplications.db', 'rijal.db'} for f in files if '.xctest/' not in f), 'Content DB bundled unexpectedly'
    print('Verified only Arabic and English are bundled in app and widget')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['validate', 'package', 'check-bundle'])
    parser.add_argument('path', nargs='?')
    parser.add_argument('--content', choices=['hadith', 'supplications', 'quran', 'all'], default='hadith')
    args = parser.parse_args()
    manifests = []
    if args.command != 'check-bundle':
        if args.content in ('hadith', 'all'): manifests += validate_hadith()
        if args.content in ('supplications', 'all'): manifests += validate_hadith('supplications')
        if args.content in ('quran', 'all'): manifests += validate_quran()
    if args.command == 'package':
        output = Path(args.path).resolve() if args.path else ROOT / 'apple/build/AssetPacks'
        output.mkdir(parents=True, exist_ok=True)
        if args.content in ('quran', 'all'):
            # Old per-language archives would collide with the new pack in Xcode local testing.
            for obsolete in output.glob('quran-*.aar'):
                if obsolete.name != 'quran-translations.aar': obsolete.unlink()
        for manifest in manifests:
            archive = output / (manifest.stem + '.aar')
            archive.unlink(missing_ok=True)
            subprocess.run(['xcrun', 'ba-package', 'package', str(manifest), '--output-path', str(archive)], check=True)
        # The UI uses archive byte counts, never rounded MB constants treated as bytes.
        metadata_path = ROOT / 'apple/Muntathir/Resources/AssetDownloadSizes.json'
        sizes = json.loads(metadata_path.read_text()) if metadata_path.exists() else {}
        for manifest in manifests:
            sizes[manifest.stem] = (output / (manifest.stem + '.aar')).stat().st_size
        metadata_path.write_text(json.dumps(sizes, indent=2) + '\n')
        print(f'Packaged {len(manifests)} asset packs in {output}')
    elif args.command == 'check-bundle':
        assert args.path, 'Provide an .app or .ipa path'
        check_bundle(args.path)
    else:
        print(f'Validated {len(manifests)} on-demand manifests and database contents')


if __name__ == '__main__':
    main()

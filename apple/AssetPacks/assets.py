#!/usr/bin/env python3
"""Package Quran asset packs and verify shipping bundles; no network or credentials."""
import argparse
import json
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
MANIFESTS = Path(__file__).parent / 'manifests'


def validate():
    sources = ROOT / 'apple/Muntathir/Resources/Quran'
    expected = {p.stem for p in sources.glob('*.db') if p.stem != 'quran'}
    found = set()
    for path in sorted(MANIFESTS.glob('*.json')):
        pack = json.loads(path.read_text())
        selector, = pack['fileSelectors']
        source = (path.parent / pack['sourceRoot'] / selector['fileSource']).resolve()
        translation = source.stem
        assert translation in expected and translation not in found, f'Unexpected/duplicate translation: {path}'
        assert pack['assetPackID'] == 'quran-' + translation.replace('.', '-')
        assert pack['downloadPolicy'] == {'onDemand': {}} and 'language' not in pack
        assert pack['platforms'] == ['iOS']
        assert source == sources / f'{translation}.db'
        assert selector['fileDestination'] == f'Quran/{translation}.db'
        with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as db:
            assert db.execute('PRAGMA quick_check').fetchone() == ('ok',), source
            assert db.execute('SELECT count(*), min("index"), max("index") FROM quran WHERE trim(text) != ""').fetchone() == (6236, 1, 6236), source
        found.add(translation)
    assert found == expected and len(found) == 13, 'Expected exactly 13 translation manifests'
    return sorted(MANIFESTS.glob('*.json'))


def check_bundle(path):
    path = Path(path)
    if path.suffix == '.ipa':
        with zipfile.ZipFile(path) as archive:
            files = archive.namelist()
    else:
        assert path.is_dir() and path.suffix == '.app', 'Expected an .app directory or .ipa'
        files = [str(f.relative_to(path)) for f in path.rglob('*') if f.is_file()]
    expected = {'quran.db', 'en.qarai.db', 'es.bornez.db', 'de.bubenheim.db',
                'ru.kuliev.db', 'zh.jian.db', 'zh.majian.db'}
    app_databases = {Path(f).name for f in files if f.endswith('.db') and '.appex/' not in f and '.xctest/' not in f and '/Watch/' not in f}
    widget_databases = {Path(f).name for f in files if f.endswith('.db') and 'MuntathirWidgets.appex/' in f}
    assert app_databases == expected, f'Unexpected app databases: {app_databases}'
    assert widget_databases == expected, f'Unexpected widget databases: {widget_databases}'
    assert not any('MuntathirAssetDownloader.appex/' in f for f in files), 'Unexpected downloader extension'
    print('Verified bundled Quran translations in app and widget')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['validate', 'package', 'check-bundle'])
    parser.add_argument('path', nargs='?')
    args = parser.parse_args()
    manifests = validate()
    if args.command == 'package':
        output = Path(args.path).resolve() if args.path else ROOT / 'apple/build/AssetPacks'
        output.mkdir(parents=True, exist_ok=True)
        for manifest in manifests:
            subprocess.run(['xcrun', 'ba-package', str(manifest), '--output-path', str(output / (manifest.stem + '.aar'))], check=True)
        print(f'Packaged {len(manifests)} translations in {output}')
    elif args.command == 'check-bundle':
        assert args.path, 'Provide an .app or .ipa path'
        check_bundle(args.path)
    else:
        print('Validated 13 on-demand manifests and unchanged source database contents')


if __name__ == '__main__':
    main()

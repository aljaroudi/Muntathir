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
    downloader = 'Extensions/MuntathirAssetDownloader.appex/Info.plist'
    if path.suffix == '.ipa':
        with zipfile.ZipFile(path) as archive:
            files = archive.namelist()
            downloader_info = next((plistlib.loads(archive.read(f)) for f in files if f.endswith(downloader)), None)
    else:
        assert path.is_dir() and path.suffix == '.app', 'Expected an .app directory or .ipa'
        files = [str(f.relative_to(path)) for f in path.rglob('*') if f.is_file()]
        downloader_info = next((plistlib.loads((path / f).read_bytes()) for f in files if f.endswith(downloader)), None)
    translations = {json.loads(p.read_text())['fileSelectors'][0]['fileDestination'].split('/')[-1] for p in validate()}
    leaked = [f for f in files if Path(f).name in translations]
    assert not leaked, f'Translation databases leaked into shipping bundle: {leaked}'
    assert any(f.endswith('quran.db') for f in files), 'Missing Arabic database'
    assert any(f.endswith('MuntathirWidgets.appex/quran.db') for f in files), 'Missing widget Arabic database'
    assert downloader_info is not None, 'Missing ExtensionKit downloader'
    assert downloader_info.get('CFBundleDisplayName', '').strip(), 'Missing asset downloader display name required by App Store Connect'
    print('Verified Arabic-only app/widget and embedded asset downloader')


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

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('assets', HERE / 'assets.py')
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


class PackagingTests(unittest.TestCase):
    def test_default_output_matches_xcode_run_scheme(self):
        scheme = ET.parse(HERE.parent / 'Muntathir.xcodeproj/xcshareddata/xcschemes/Muntathir.xcscheme')
        folder = scheme.find('.//BackgroundAssetPacksFolderResolver').get('identifier')
        self.assertTrue(folder.startswith('container:'))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            resources = root / 'apple/Muntathir/Resources'
            resources.mkdir(parents=True)
            manifest = root / 'hadith.json'
            archive = root / 'apple' / folder.removeprefix('container:') / 'hadith.aar'

            def package(arguments, check):
                self.assertTrue(check)
                self.assertEqual(arguments, ['xcrun', 'ba-package', 'package', str(manifest), '--output-path', str(archive)])
                archive.write_bytes(b'test archive')

            with patch.object(assets, 'ROOT', root), patch.object(assets, 'validate_hadith', return_value=[manifest]), \
                 patch.object(assets.subprocess, 'run', side_effect=package), \
                 patch('sys.argv', ['assets.py', 'package']):
                assets.main()
            self.assertTrue(archive.exists())
            self.assertEqual(json.loads((resources / 'AssetDownloadSizes.json').read_text()), {'hadith': 12})

    def test_rulings_pack_preserves_other_download_sizes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            resources = root / 'apple/Muntathir/Resources'
            resources.mkdir(parents=True)
            sizes = resources / 'AssetDownloadSizes.json'
            sizes.write_text(json.dumps({'hadith': 123, 'supplications': 45}))
            manifest = root / 'rulings.json'
            def package(arguments, check):
                self.assertTrue(check)
                Path(arguments[-1]).write_bytes(b'rulings archive')
            with patch.object(assets, 'ROOT', root), patch.object(assets, 'validate_rulings', return_value=[manifest]), \
                 patch.object(assets.subprocess, 'run', side_effect=package), \
                 patch('sys.argv', ['assets.py', 'package', '--content', 'rulings']):
                assets.main()
            self.assertEqual(json.loads(sizes.read_text()), {'hadith': 123, 'supplications': 45, 'rulings': 15})

    def test_android_pack_copies_into_module_with_matching_delivery(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'build/hadith/dist/supplications.db'
            source.parent.mkdir(parents=True)
            source.write_bytes(b'database')
            manifest = root / 'apple/AssetPacks/manifests/supplications.json'
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({
                'assetPackID': 'supplications', 'sourceRoot': '../../..',
                'fileSelectors': [{'fileSource': 'build/hadith/dist/supplications.db',
                                   'fileDestination': 'Supplications/supplications.db'}],
            }))
            module = root / 'android/packs/supplications'
            module.mkdir(parents=True)
            build = module / 'build.gradle.kts'
            build.write_text('packName = "supplications"\ndeliveryType = "on-demand"\n')
            with self.assertRaises(AssertionError):
                assets.android_pack(manifest, root)
            build.write_text('packName = "supplications"\ndeliveryType = "fast-follow"\n')
            copied, = assets.android_pack(manifest, root)
            self.assertEqual(copied, module / 'src/main/assets/Supplications/supplications.db')
            self.assertEqual(copied.read_bytes(), b'database')

    def test_android_packs_match_repository_modules(self):
        for pack_id in ('hadith', 'supplications'):
            name, delivery = assets.ANDROID_PACKS[pack_id]
            script = (assets.ROOT / 'android/packs' / name / 'build.gradle.kts').read_text()
            self.assertIn(f'deliveryType = "{delivery}"', script)

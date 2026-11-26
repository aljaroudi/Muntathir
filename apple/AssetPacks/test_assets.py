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
            manifest = root / 'rulings-v2.json'
            def package(arguments, check):
                self.assertTrue(check)
                Path(arguments[-1]).write_bytes(b'rulings archive')
            with patch.object(assets, 'ROOT', root), patch.object(assets, 'validate_rulings', return_value=[manifest]), \
                 patch.object(assets.subprocess, 'run', side_effect=package), \
                 patch('sys.argv', ['assets.py', 'package', '--content', 'rulings']):
                assets.main()
            self.assertEqual(json.loads(sizes.read_text()), {'hadith': 123, 'supplications': 45, 'rulings-v2': 15})

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

    def test_android_rulings_pack_keeps_authorities_the_ios_pack_leaves_out(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            dist = root / 'build/rulings/dist'
            dist.mkdir(parents=True)
            (dist / 'rulings.db').write_bytes(b'full')
            (dist / 'rulings-apple.db').write_bytes(b'apple')
            module = root / 'android/packs/rulings'
            module.mkdir(parents=True)
            (module / 'build.gradle.kts').write_text('packName = "rulings"\ndeliveryType = "on-demand"\n')
            manifest = root / 'apple/AssetPacks/manifests/rulings-v2.json'
            manifest.parent.mkdir(parents=True)
            manifest.write_text((assets.MANIFESTS / 'rulings-v2.json').read_text())
            copied, = assets.android_pack(manifest, root)
            self.assertEqual(copied, module / 'src/main/assets/Rulings/rulings.db')
            self.assertEqual(copied.read_bytes(), b'full')

    def test_ios_rulings_pack_rejects_sanctioned_authority(self):
        import sqlite3
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            manifests = root / 'apple/AssetPacks/manifests'
            manifests.mkdir(parents=True)
            (manifests / 'rulings-v2.json').write_text((assets.MANIFESTS / 'rulings-v2.json').read_text())
            database = root / 'build/rulings/dist/rulings-apple.db'
            database.parent.mkdir(parents=True)
            with sqlite3.connect(database) as db:
                db.executescript("""
                    PRAGMA application_id = 1179809601; PRAGMA user_version = 2;
                    CREATE TABLE authority (code TEXT PRIMARY KEY);
                    CREATE TABLE topic (id INTEGER PRIMARY KEY, authority_code TEXT, language_code TEXT, url TEXT);
                    CREATE TABLE entry (id INTEGER PRIMARY KEY, authority_code TEXT, language_code TEXT, url TEXT);
                    CREATE VIEW question AS SELECT id, authority_code, language_code, 'q' AS question, 'الصلاة' AS answer FROM entry;
                    CREATE TABLE placement (topic_id INTEGER, question_id INTEGER);
                    CREATE VIRTUAL TABLE question_fts USING fts5(question, answer);
                    INSERT INTO question_fts VALUES ('q', 'الصلاة');
                    INSERT INTO authority VALUES ('sistani');
                    INSERT INTO entry VALUES (1, 'sistani', 'ar', 'https://www.sistani.org/1');
                """)
            self.assertEqual(assets.validate_rulings(root, manifests), [manifests / 'rulings-v2.json'])
            with sqlite3.connect(database) as db:
                db.execute("INSERT INTO entry VALUES (2, 'sistani', 'fa', 'https://www.rohani.ir/fa/idetail/1/x')")
            with self.assertRaisesRegex(AssertionError, 'rohani.ir'):
                assets.validate_rulings(root, manifests)
            with sqlite3.connect(database) as db:
                db.execute("DELETE FROM entry WHERE id = 2")
                db.execute("INSERT INTO authority VALUES ('rohani')")
            with self.assertRaisesRegex(AssertionError, '--exclude rohani'):
                assets.validate_rulings(root, manifests)

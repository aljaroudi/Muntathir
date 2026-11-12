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

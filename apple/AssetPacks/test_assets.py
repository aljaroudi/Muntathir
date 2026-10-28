"""Regression checks for exact downloader placement in exported bundles."""
import plistlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import assets


class BundlePlacementTests(unittest.TestCase):
    def check_fixture(self, misplaced, ipa):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / 'Muntathir.app'
            files = {
                'Info.plist': plistlib.dumps({'CFBundleIdentifier': 'com.aljaroudi.Muntathir'}),
                'quran.db': b'',
                'PlugIns/MuntathirWidgets.appex/quran.db': b'',
                ('Nested/' if misplaced else '') + 'Extensions/MuntathirAssetDownloader.appex/Info.plist':
                    plistlib.dumps({'CFBundleDisplayName': 'Downloads'}),
            }
            for name, content in files.items():
                target = app / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
            target = app
            if ipa:
                target = Path(folder) / 'Muntathir.ipa'
                with zipfile.ZipFile(target, 'w') as archive:
                    for name, content in files.items():
                        archive.writestr('Payload/Muntathir.app/' + name, content)
            with patch.object(assets, 'validate', return_value=[]):
                if misplaced:
                    with self.assertRaisesRegex(AssertionError, 'Missing ExtensionKit downloader'):
                        assets.check_bundle(target)
                else:
                    assets.check_bundle(target)

    def test_exact_location_required(self):
        for ipa in (False, True):
            for misplaced in (False, True):
                with self.subTest(ipa=ipa, misplaced=misplaced):
                    self.check_fixture(misplaced, ipa)


if __name__ == '__main__':
    unittest.main()

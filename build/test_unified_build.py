from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from build import build_assets, db_hash


class UnifiedBuildTests(unittest.TestCase):
    def test_hash_ignores_sqlite_header_counters_but_detects_payload_changes(self):
        with tempfile.TemporaryDirectory() as temp:
            db = Path(temp) / "test.db"
            data = bytearray(256)
            db.write_bytes(data)
            original = db_hash(db)
            data[24] = data[92] = 1
            db.write_bytes(data)
            self.assertEqual(db_hash(db), original)
            data[100] = 1
            db.write_bytes(data)
            self.assertNotEqual(db_hash(db), original)

    def test_failed_builder_stops_before_installing(self):
        with tempfile.TemporaryDirectory() as temp, \
                patch("build.run", side_effect=subprocess.CalledProcessError(1, "builder")), \
                patch("build.install") as install:
            with self.assertRaises(subprocess.CalledProcessError):
                build_assets(Path(temp))
            install.assert_not_called()

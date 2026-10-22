import csv
from contextlib import closing
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

from import_daily_verses import compile_schedule


class ImportDailyVersesTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "schedule.csv"
        self.database = Path(self.directory.name) / "quran.db"
        self.english = Path(self.directory.name) / "en.qarai.db"
        for path, text in [(self.database, "Arabic fixture"), (self.english, "English fixture")]:
            with closing(sqlite3.connect(path)) as connection, connection:
                connection.execute('CREATE TABLE quran ("index" INTEGER PRIMARY KEY, text TEXT)')
                connection.execute('INSERT INTO quran VALUES (2373, ?)', (text,))
        self.rows = [[month, day, 2373] for month in range(1, 13) for day in range(1, 31)]

    def compile(self, rows=None):
        with self.path.open("w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(["hijriMonth", "hijriDay", "verseID"])
            writer.writerows(self.rows if rows is None else rows)
        return compile_schedule(self.path, self.database)

    def test_complete_schedule_contains_only_numbers(self):
        result = self.compile()
        self.assertEqual(len(result["entries"]), 360)
        self.assertEqual(result["entries"][0], dict(hijriMonth=1, hijriDay=1, verseID=2373))
        self.assertEqual(result["entries"][-1], dict(hijriMonth=12, hijriDay=30, verseID=2373))
        self.assertTrue(all(isinstance(value, int) for entry in result["entries"] for value in entry.values()))

    def test_incomplete_duplicate_invalid_and_blank_references_fail(self):
        for rows in [self.rows[:-1], self.rows[:-1] + [self.rows[0]],
                     self.rows[:-1] + [[13, 1, 2373]], self.rows[:-1] + [[12, 31, 2373]],
                     self.rows[:-1] + [[12, 30, 99999]], self.rows[:-1] + [[12, 30, ""]]]:
            with self.subTest(last=rows[-1]):
                with self.assertRaises(ValueError):
                    self.compile(rows)

    def test_translations_are_required_and_database_stays_read_only(self):
        before = self.database.read_bytes()
        self.compile()
        self.assertEqual(self.database.read_bytes(), before)
        with closing(sqlite3.connect(self.english)) as connection, connection:
            connection.execute('UPDATE quran SET text = " "')
        with self.assertRaises(ValueError):
            self.compile()

    def test_failed_import_preserves_existing_output(self):
        self.compile(self.rows)
        output = Path(self.directory.name) / "output.json"
        output.write_text("previous valid output")
        self.path.write_text("hijriMonth,hijriDay,verseID\n1,1,2373\n")
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("import_daily_verses.py")),
                                 "--schedule", str(self.path), "--database", str(self.database),
                                 "--output", str(output)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("1/360", result.stderr)
        self.assertEqual(output.read_text(), "previous valid output")


if __name__ == "__main__":
    unittest.main()

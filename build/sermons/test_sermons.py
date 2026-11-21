import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

from fadak.publication import align, load_sermon, reader_text


class SermonBuildTests(unittest.TestCase):
    def test_published_editions_and_reproducibility(self):
        here = Path(__file__).resolve().parent
        published = (here.parents[1] / "shared/sermons/sermons.db").read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "sermons.db"
            for _ in range(2):
                subprocess.run([sys.executable, here / "build.py", "--output", output], check=True)
                self.assertEqual(output.read_bytes(), published)
        sermon = load_sermon()
        with sqlite3.connect(here.parents[1] / "shared/sermons/sermons.db") as db:
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual(list(db.execute("PRAGMA foreign_key_check")), [])
            self.assertEqual(db.execute("SELECT id,title,speaker_id,source FROM sermon").fetchall(),
                             [tuple(sermon[k] for k in ("id", "title", "speaker_id", "source"))])
            self.assertEqual(list(db.execute("SELECT id,section,kind,text FROM segment ORDER BY position")),
                             [tuple(s[k] for k in ("id", "section", "kind", "text")) for s in sermon["segments"]])
            self.assertEqual(list(db.execute("SELECT id,language,kind,credit FROM edition ORDER BY position")),
                             [tuple(e.get(k) for k in ("id", "language", "kind", "credit")) for e in sermon["editions"]])
            for edition in sermon["editions"]:
                self.assertEqual(dict(db.execute("SELECT segment,text FROM translation WHERE edition=?", (edition["id"],))),
                                 edition["aligned"])
        figures = json.loads((here.parents[1] / "shared/figures/figures.json").read_text())["people"]
        self.assertIn(sermon["speaker_id"], {f["id"] for f in figures if f.get("verified")})
        segments = sermon["segments"]
        self.assertEqual([s["id"] for s in segments[:2]], ["s006", "s008"])
        self.assertTrue(segments[0]["text"].startswith("روى عبد الله بن الحسن"))
        self.assertIn("الاحتجاج", sermon["source"])
        ids = {s["id"] for s in segments}
        editions = {e["id"]: e for e in sermon["editions"]}
        self.assertEqual(len(editions), 17)
        self.assertEqual(len({e["language"] for e in editions.values() if e["kind"] == "human"}), 10)
        self.assertNotIn("s008", editions["es-1"]["aligned"])
        self.assertIn("s008", editions["fa-1"]["aligned"])
        self.assertIn("s129", editions["de-1"]["aligned"])
        self.assertNotIn("s177", editions["de-1"]["aligned"])
        self.assertTrue(editions["de-1"]["aligned"]["s008"].startswith("Im Namen Allahs"))
        for edition in editions.values():
            if edition["id"] == "en-3":
                self.assertEqual(edition["credit"], "Ahl al-Bayt World Assembly")
                self.assertTrue(edition["aligned"]["s144"].startswith("He said: O daughter"))
                self.assertIn("steeds", edition["aligned"]["s155"])
                self.assertIn("insurgents", edition["aligned"]["s155"])
                self.assertIn("Messenger ﷺ", edition["aligned"]["s167"])
                self.assertEqual(set(edition["aligned"]), {i for i in ids if "s008" <= i <= "s182"})
            elif edition["kind"] == "human":
                self.assertTrue(edition["credit"] and edition["aligned"])
                self.assertTrue(set(edition["aligned"]) <= ids)
            else:
                self.assertNotIn("credit", edition)
                self.assertEqual(set(edition["aligned"]), ids)

    def test_cross_paragraph_range_is_rejected(self):
        segments = [dict(id=i) for i in ("s013", "s014", "s015")]
        with self.assertRaisesRegex(ValueError, "paragraph boundary"):
            align([dict(segmentId="s013", endSegmentId="s015", text="Two paragraphs")], segments)

    def test_shared_paragraphs_preserve_source_order_and_text(self):
        root = Path(__file__).resolve().parent
        sermon = load_sermon()
        source = json.loads((root / "fadak/data/segments.json").read_text())
        paragraphs = sermon["segments"]
        self.assertEqual(" ".join(s["text"] for s in paragraphs).split(),
                         " ".join(reader_text(s["arabic"]) for s in source if s["id"] >= "s006" and s["id"] != "s007").split())
        for file in (root / "fadak/human").glob("*.json"):
            edition = json.loads(file.read_text())
            published = next(e["aligned"] for e in sermon["editions"] if e["id"] == edition["id"])
            for i, paragraph in enumerate(paragraphs):
                start = paragraph["id"]
                end = paragraphs[i + 1]["id"] if i + 1 < len(paragraphs) else "z"
                rows = [r for r in edition["passages"] if start <= r["segmentId"] < end]
                expected = " ".join(reader_text(r["text"]) for r in rows)
                if start == "s008" and not rows and start in published:
                    expected = edition["basmala"]
                self.assertEqual(published.get(start, "").split(), expected.split(), (file.name, start))

    def test_range_coverage(self):
        segments = [dict(id=i) for i in ("intro", "a", "b", "c", "after")]
        required = {"a", "b", "c"}
        grouped = dict(segmentId="a", endSegmentId="b", text="first two clauses")
        last = dict(segmentId="c", text="last clause")
        self.assertEqual(align([grouped, last], segments, required), {"b": grouped["text"], "c": last["text"]})
        self.assertEqual(align([last], segments), {"c": "last clause"})
        for rows in ([grouped], [last, grouped], [grouped, grouped, last], [dict(grouped, endSegmentId="unknown"), last],
                     [grouped, dict(last, text=" ")], [dict(grouped, segmentId="unknown"), last]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                align(rows, segments, required)

    def test_supplement_only_the_missing_basmala(self):
        segments = [dict(id=f"s{i:03}", wikishiaIndex=i - 7) for i in range(8, 11)]
        rows = [dict(segmentId="s009", endSegmentId="s010", text="Praise")]
        self.assertEqual(align(rows, segments, basmala="Opening"), {"s010": "Praise", "s008": "Opening"})
        del rows[0]["endSegmentId"]
        self.assertEqual(align(rows, segments, basmala="Opening"), {"s009": "Praise"})

    def test_blessings_follow_referent(self):
        self.assertEqual(reader_text("Allah-azwj Muhammad-saww Fatima-asws she-asws Ali-asws forefathers-asws"),
                         "Allah ﷻ Muhammad ﷺ Fatima عليها السلام she Ali عليه السلام forefathers عليهم السلام")
        with self.assertRaises(ValueError):
            reader_text("someone-asws")

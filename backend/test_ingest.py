import argparse
from decimal import Decimal
import json
from pathlib import Path
import sqlite3
import tempfile
from types import SimpleNamespace
import types
import unittest
from unittest.mock import Mock, patch

import ingest


class IngestionTests(unittest.TestCase):
    def test_estimate_counts_distinct_inputs_and_reserves_accepted_retries(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            reuse = root / "reuse"
            reuse.mkdir()
            (reuse / "reused.json").touch()
            passages = [{"input_hash": key, "input": "ص"} for key in ["reused", "pending", "retry", "retry", "rejected"]]
            manifest = {"passages": passages, "jobs": [
                {"name": None, "state": "submitting", "keys": ["pending"]},
                {"name": "batches/accepted", "state": "failed", "keys": ["retry"]},
                {"name": None, "state": "failed", "keys": ["rejected"]},
            ]}
            reusable, missing, estimate = ingest.submission_plan(manifest, root / "vectors", reuse)
            self.assertEqual(reusable, {"reused"})
            self.assertEqual([p["input_hash"] for p in missing], ["retry", "rejected"])
            self.assertEqual(estimate["pending"], 1)
            self.assertEqual(estimate["missing_utf8_bytes"], 4)
            self.assertEqual(Decimal(estimate["total_batch_usd_estimate"]), ingest.batch_cost(8))

    def test_submit_rechecks_revision_budget_before_contacting_gemini(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(ingest, "gemini_client") as client:
            root = Path(tmp)
            manifest = {"profile": ingest.PROFILE, "passages": [{"input_hash": "retry", "input": "text"}],
                        "jobs": [{"name": "batches/accepted", "state": "failed", "keys": ["retry"]}]}
            (root / "manifest.json").write_text(json.dumps(manifest))
            for cap in (None, ingest.batch_cost(4)):
                with self.assertRaisesRegex(ValueError, "--max-usd"):
                    ingest.run(SimpleNamespace(command="submit", workdir=tmp, reuse=None, max_usd=cap))
            client.assert_not_called()
            self.assertFalse((root / "vectors").exists())
            client.return_value.files.upload.return_value.name = "files/requests"
            client.return_value.batches.create_embeddings.return_value.name = "batches/retry"
            manifest["revision"] = "retry-test"
            (root / "manifest.json").write_text(json.dumps(manifest))
            args = SimpleNamespace(command="submit", workdir=tmp, reuse=None, max_usd=ingest.batch_cost(8))
            ingest.run(args)
            ingest.run(args)
            client.return_value.batches.create_embeddings.assert_called_once()
            jobs = json.loads((root / "manifest.json").read_text())["jobs"]
            self.assertEqual(jobs[-1]["state"], "pending")
            self.assertEqual(jobs[-1]["name"], "batches/retry")

    def test_estimate_is_offline_and_zero_cost_submit_only_reuses(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(ingest, "gemini_client") as client:
            root = Path(tmp)
            previous = root / "previous" / "vectors"
            previous.mkdir(parents=True)
            vector = [0.1] * 3072
            (previous / "saved.json").write_text(json.dumps(vector))
            manifest = {"profile": ingest.PROFILE, "passages": [{"input_hash": "saved", "input": "text"}], "jobs": []}
            (root / "manifest.json").write_text(json.dumps(manifest))
            args = SimpleNamespace(command="estimate", workdir=tmp, reuse=previous.parent, max_usd=None)
            ingest.run(args)
            self.assertFalse((root / "vectors").exists())
            args.command = "submit"
            ingest.run(args)
            self.assertEqual(json.loads((root / "vectors/saved.json").read_text()), vector)
            client.assert_not_called()

    def test_estimate_and_submit_reuse_every_listed_workdir(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(ingest, "gemini_client") as client:
            root = Path(tmp)
            vector = [0.1] * 3072
            for name, key in (("first", "one"), ("second", "two")):
                (root / name / "vectors").mkdir(parents=True)
                (root / name / "vectors" / (key + ".json")).write_text(json.dumps(vector))
            work = root / "work"
            work.mkdir()
            passages = [{"input_hash": key, "input": "text"} for key in ("one", "two", "three")]
            (work / "manifest.json").write_text(json.dumps({"revision": "r", "profile": ingest.PROFILE, "passages": passages, "jobs": []}))
            reuse = [str(root / "first"), str(root / "second")]
            args = SimpleNamespace(command="estimate", workdir=str(work), reuse=reuse, max_usd=None)
            _, missing, estimate = ingest.submission_plan(json.loads((work / "manifest.json").read_text()), work / "vectors",
                                                          [root / name / "vectors" for name in ("first", "second")])
            self.assertEqual(estimate["reusable"], 2)
            self.assertEqual([p["input_hash"] for p in missing], ["three"])
            client.return_value.files.upload.return_value.name = "files/requests"
            client.return_value.batches.create_embeddings.return_value.name = "batches/one"
            args.command, args.max_usd = "submit", ingest.batch_cost(4)
            ingest.run(args)
            self.assertTrue((work / "vectors/one.json").exists())
            self.assertTrue((work / "vectors/two.json").exists())

    def test_rulings_v2_books_use_context_and_keep_question_references(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            database = root / "rulings.db"
            db = sqlite3.connect(database)
            db.executescript("""
                PRAGMA application_id = 1179809601; PRAGMA user_version = 2;
                CREATE TABLE authority(code, name_ar, name_en, sort_order);
                CREATE TABLE question(authority_code, language_code, site_id, question, answer, url, context);
                INSERT INTO authority VALUES ('sistani', 'ع', 'Sistani', 1);
                INSERT INTO question VALUES ('sistani', 'en', '42', 'Q?', 'A.', 'u1', 'Questions · Prayer');
                INSERT INTO question VALUES ('sistani', 'en', 'book:7:3:Ruling1', 'Ruling 1.', 'Body.', 'u2', 'Islamic Laws · Prayer');
            """)
            db.commit()
            db.close()
            manifests = []
            for name in ("one", "two"):
                ingest.prepare(argparse.Namespace(workdir=str(root / name), provenance=None, quran=None, hadith=None, dua=None,
                                                  rulings=str(database), translation=[], limit=None, pilot=False))
                manifests.append(json.loads((root / name / "manifest.json").read_text()))
            items = {i["navigation"]["id"]: i for i in manifests[0]["items"]}
            self.assertEqual(items["42"]["title"], "Sistani · 42")
            self.assertEqual(items["book:7:3:Ruling1"]["title"], "Islamic Laws · Prayer")
            self.assertEqual(items["42"]["reference"], {"authority": "sistani", "language": "en", "id": "42"})
            self.assertEqual([i["id"] for i in manifests[0]["items"]], [i["id"] for i in manifests[1]["items"]])

    def test_offsets_preserve_arabic_and_supplication_paragraphs(self):
        text = "اللَّهُمَّ ارحمنا 🌙.\n\n" * 500
        pieces = list(ingest.chunks(text))
        self.assertGreater(len(pieces), 1)
        self.assertEqual("".join(p[2] for p in pieces), text)
        for start, end, value in pieces:
            self.assertEqual(text[start:end], value)
            self.assertLessEqual(end - start, 3500)

    def test_identity_and_profile_hash(self):
        self.assertEqual(ingest.identity("hadith", "book", "chapter", 1), ingest.identity("hadith", "book", "chapter", 1))
        self.assertNotEqual(ingest.identity("text", "old"), ingest.identity("text", "new"))
        self.assertEqual(ingest.normalize("إِنَّـمَا"), "انما")
        self.assertNotEqual(ingest.digest("old:text"), ingest.digest("new:text"))

    def test_vector_rejects_nan_zero_and_wrong_dimensions(self):
        ingest.validate_vector([0.1] * 3072)
        for value in ([0] * 3072, [float("nan")] * 3072, [1] * 100):
            with self.assertRaises(ValueError):
                ingest.validate_vector(value)

    def test_dua_revisions_keep_identity_but_replace_passages(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            provenance = {"dua-source": {"url": "https://example.org", "edition": "test", "attribution": "Test", "license": "test-only"}}
            (root / "sources.json").write_text(json.dumps(provenance))
            def prepare(name, text):
                dua = [{"id": "morning", "source_id": "dua-source", "source_name": "Supplications", "title": "Morning", "texts": [{"language": "ar", "edition": "test", "attribution": "Test", "text": text}]}]
                (root / "dua.json").write_text(json.dumps(dua))
                ingest.prepare(argparse.Namespace(workdir=str(root / name), provenance=str(root / "sources.json"), quran=None,
                    hadith=None, dua=str(root / "dua.json"), translation=[], limit=None, pilot=False))
                return json.loads((root / name / "manifest.json").read_text())
            first = prepare("one", "اللهم ارحمنا")
            second = prepare("two", "اللهم ارحمنا واغفر لنا")
            self.assertEqual(first["items"][0]["id"], second["items"][0]["id"])
            self.assertNotEqual(first["passages"][0]["id"], second["passages"][0]["id"])
            self.assertNotEqual(first["passages"][0]["input_hash"], second["passages"][0]["input_hash"])
            with self.assertRaises(ValueError):
                prepare("one", "duplicate")

    def test_batch_results_resume_without_redownloading_completed_jobs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = {"profile": ingest.PROFILE, "jobs": [{"name": "batches/test", "state": "pending", "keys": ["good", "failed"]}]}
            (root / "manifest.json").write_text(json.dumps(manifest))
            client = Mock()
            client.batches.get.return_value = SimpleNamespace(state="JOB_STATE_SUCCEEDED", dest=SimpleNamespace(file_name="files/results"))
            client.files.download.return_value = (json.dumps({"key": "good", "response": {"embedding": {"values": [.1] * 3072}, "tokenCount": 12}}) + "\n" + json.dumps({"key": "failed", "error": {"code": 429}})).encode()
            google = types.ModuleType("google")
            google.genai = SimpleNamespace(Client=Mock(return_value=client))
            with patch.dict("sys.modules", {"google": google}), patch.dict("os.environ", {"GEMINI_API_KEY": "test"}):
                args = argparse.Namespace(command="poll", workdir=tmp)
                ingest.run(args)
                ingest.run(args)
            client.files.download.assert_called_once()
            job = json.loads((root / "manifest.json").read_text())["jobs"][0]
            self.assertEqual(job["failed_keys"], ["failed"])
            self.assertEqual(job["reported_tokens"], 12)
            self.assertTrue((root / "vectors/good.json").exists())
            self.assertFalse((root / "test.results.jsonl").exists())



if __name__ == "__main__":
    unittest.main()

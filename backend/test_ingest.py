import argparse
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import types
import unittest
from unittest.mock import Mock, patch

import ingest


class IngestionTests(unittest.TestCase):
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

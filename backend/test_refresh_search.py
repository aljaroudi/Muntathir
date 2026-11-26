from decimal import Decimal
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from refresh_search import alias, authorize, keys, preserve_other_sources, promote, public_results, reusable_workdirs


def corpus(revision, kind="dua"):
    return {
        "revision": revision, "profile": "profile",
        "sources": [{"id": "source"}],
        "items": [{"id": "item", "source_id": "source", "kind": kind,
                   "navigation": {"dua_id": "prayer", "chapter": 1, "verse": 1}}],
        "texts": [{"id": revision + "-text", "revision_id": revision,
                   "item_id": "item", "language": "ar", "edition": "a", "full_text": "text"}],
        "passages": [{"id": revision + "-passage", "text_id": revision + "-text",
                      "ordinal": 1, "input_hash": "hash"}],
    }


class RefreshTests(unittest.TestCase):
    def test_content_comparison_ignores_revision_but_detects_metadata(self):
        first, second = corpus("first"), corpus("second")
        self.assertEqual(keys(first), keys(second))
        second["items"][0]["title"] = "new title"
        self.assertNotEqual(keys(first), keys(second))

    def test_preserve_non_rebuilt_source_in_new_revision(self):
        prior = corpus("old")
        candidate = dict(revision="new", profile="profile", sources=[], items=[], texts=[], passages=[])
        preserve_other_sources(candidate, prior)
        self.assertEqual(keys(candidate), keys(prior))
        self.assertEqual(candidate["texts"][0]["revision_id"], "new")
        self.assertEqual(candidate["passages"][0]["text_id"], candidate["texts"][0]["id"])

    def test_reuse_includes_active_and_profile_compatible_workdirs_only(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            for name, profile, vectors in (("active", "p", True), ("paid", "p", True), ("other", "q", True),
                                           ("bare", "p", False), ("current", "p", True)):
                (base / name).mkdir()
                (base / name / "manifest.json").write_text('{"revision": "r", "profile": "%s", "items": []}' % profile)
                if vectors:
                    (base / name / "vectors").mkdir()
            with patch("refresh_search.ingest.PROFILE", "p"):
                self.assertEqual(reusable_workdirs(base, base / "active", base / "current"),
                                 [base / "active", base / "paid"])

    def test_budget_and_approval(self):
        self.assertEqual(authorize(Decimal("10"), Decimal("10")), Decimal("10"))
        with patch("sys.stdin.isatty", return_value=False), self.assertRaises(ValueError):
            authorize(Decimal("10.01"), Decimal("10"))
        with patch("sys.stdin.isatty", return_value=True), patch("builtins.input", side_effect=["no", "yes"]):
            with self.assertRaises(ValueError):
                authorize(Decimal("10.01"), Decimal("10"))
            self.assertEqual(authorize(Decimal("10.01"), Decimal("10")), Decimal("10.01"))

    def test_rollback_replaces_alias_atomically(self):
        client = Mock()
        alias(client, "previous")
        client.call.assert_called_once_with("POST", "/collections/aliases", {"actions": [
            {"delete_alias": {"alias_name": "search"}},
            {"create_alias": {"alias_name": "search", "collection_name": "previous"}},
        ]})


    def test_failed_smoke_restores_previous_alias(self):
        client = Mock()
        activate = Mock()
        with tempfile.TemporaryDirectory() as temp, \
                patch("refresh_search.active", side_effect=["previous", "target"]), \
                patch("refresh_search.alias") as rollback, \
                patch("refresh_search.smoke", side_effect=ValueError("bad response")):
            with self.assertRaisesRegex(ValueError, "bad response"):
                promote(client, "previous", "target", Path(temp), activate, {})
            activate.assert_called_once()
            rollback.assert_called_once_with(client, "previous")

    def test_public_requests_identify_the_client_to_cloudflare(self):
        with patch("refresh_search.urllib.request.urlopen", return_value=io.BytesIO(b'{"results": []}')) as send:
            self.assertEqual(public_results({}, {"query": "test"}), [])
        self.assertEqual(send.call_args.args[0].get_header("User-agent"), "Muntathir/1.0")

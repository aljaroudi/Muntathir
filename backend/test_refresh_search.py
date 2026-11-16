from decimal import Decimal
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from refresh_search import alias, authorize, check_client_references, keys, preserve_other_sources, promote


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

    def test_new_reader_reference_requires_compatibility(self):
        candidate = corpus("new", "quran")
        check_client_references(candidate, corpus("old", "quran"))
        with self.assertRaisesRegex(ValueError, "compatibility"):
            check_client_references(candidate, corpus("old"))

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

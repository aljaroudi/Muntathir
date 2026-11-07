import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

try:
    import exact_reference
except ImportError:
    exact_reference = None
from ingest import PROFILE, digest


@unittest.skipIf(exact_reference is None, 'Install requirements-eval.txt for matrix evaluation')
class ExactReferenceTests(unittest.TestCase):
    def test_cosine_filters_and_stable_ties(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'vectors').mkdir()
            (root / 'queries').mkdir()
            vector = [1.0] + [0.0] * 3071
            query = 'test'
            (root / 'queries' / (digest(PROFILE + ':' + query) + '.json')).write_text(json.dumps(vector))
            passages, texts, items = [], [], []
            for identifier, kind in [('b', 'quran'), ('a', 'quran'), ('c', 'hadith')]:
                key = digest(PROFILE + ':' + identifier)
                (root / 'vectors' / (key + '.json')).write_text(json.dumps(vector))
                passages.append({'id': identifier, 'text_id': identifier, 'input': identifier, 'input_hash': key})
                texts.append({'id': identifier, 'item_id': identifier, 'language': 'en'})
                items.append({'id': identifier, 'kind': kind, 'source_id': 'source'})
            (root / 'manifest.json').write_text(json.dumps({'revision': 'revision', 'passages': passages, 'texts': texts, 'items': items}))
            fixture = root / 'fixture.json'
            fixture.write_text(json.dumps({'queries': [{'id': 'query', 'query': query, 'kinds': ['quran']}]}))
            output = root / 'result.json'
            with patch.object(sys, 'argv', ['exact_reference', '--corpus', str(root), '--queries', str(fixture),
                                           '--workdir', str(root / 'queries'), '--output', str(output)]), contextlib.redirect_stdout(io.StringIO()):
                exact_reference.main()
            self.assertEqual(json.loads(output.read_text())['results']['query'], ['a', 'b'])

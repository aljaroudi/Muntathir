import unittest
import json
import tempfile
from pathlib import Path
from ingest import PROFILE, digest
from verify import embedding
from verify import ndcg, percentile, recall


class MetricTests(unittest.TestCase):
    def test_saved_canonical_query_projects_without_provider_call(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            query = 'test query'
            original = [3.,4.] + [0.] * 3070
            (work / (digest(PROFILE + ':' + query) + '.json')).write_text(json.dumps(original))
            projected = embedding(query, work, 1536)
            self.assertEqual(len(projected),1536)
            self.assertEqual(projected[:2],[.6,.8])
            self.assertEqual(embedding(query,work),original)
            with self.assertRaises(ValueError):
                embedding(query,work,42)

    def test_ranked_relevance(self):
        relevant = {"a": 3, "b": 1}
        self.assertEqual(recall(["a", "b"], relevant), 1)
        self.assertEqual(recall(["a", "a"], relevant), .5)
        self.assertEqual(ndcg(["a", "b"], relevant), 1)
        self.assertLess(ndcg(["b", "a"], relevant), 1)
        self.assertIsNone(ndcg(["a"], {}))
        self.assertEqual(percentile(list(range(1, 101))), 95)


if __name__ == "__main__":
    unittest.main()

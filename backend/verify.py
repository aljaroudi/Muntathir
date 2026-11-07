"""Shared relevance metrics and cached query-vector projection."""
import json
import math
import os
from pathlib import Path
import urllib.request
from ingest import MODEL, PROFILE, digest, validate_vector

def recall(ranked, relevant):
    return len(set(ranked[:100]) & relevant.keys()) / len(relevant) if relevant else None


def ndcg(ranked, relevant, k=10):
    if not relevant:
        return None
    actual = sum((2 ** relevant.get(item, 0) - 1) / math.log2(i + 2) for i, item in enumerate(ranked[:k]))
    ideal = sum((2 ** grade - 1) / math.log2(i + 2) for i, grade in enumerate(sorted(relevant.values(), reverse=True)[:k]))
    return actual / ideal if ideal else None


def percentile(values, fraction=.95):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


def embedding(query, work, dimensions=3072):
    path = work / (digest(PROFILE + ":" + query) + ".json")
    if path.exists():
        vector = json.loads(path.read_text())
    else:
        request = urllib.request.Request(f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:embedContent",
            data=json.dumps({"content": {"parts": [{"text": "task: search result | query: " + query}]}, "outputDimensionality": 3072}).encode(),
            headers={"Content-Type": "application/json", "x-goog-api-key": os.environ["GEMINI_API_KEY"]})
        with urllib.request.urlopen(request, timeout=30) as response:
            vector = json.load(response)["embedding"]["values"]
        validate_vector(vector)
        path.write_text(json.dumps(vector))
    validate_vector(vector)
    if dimensions == 1536:
        prefix = vector[:1536]
        norm = math.sqrt(sum(x*x for x in prefix))
        if not norm:
            raise ValueError("Zero Matryoshka prefix")
        return [x / norm for x in prefix]
    if dimensions != 3072:
        raise ValueError("Unsupported embedding dimensions")
    return vector


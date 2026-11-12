#!/usr/bin/env python3
"""Compute exact float32 cosine references from the uploaded import manifest."""
import argparse
import json
from pathlib import Path

import numpy as np
from ingest import PROFILE, digest, validate_vector
from verify import embedding
from qdrant_import import search_eligibility


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', required=True)
    parser.add_argument('--dimensions', type=int, choices=[1536,3072], default=1536)
    parser.add_argument('--queries', default='backend/evaluation.json')
    parser.add_argument('--workdir', default='backend/work/query-vectors')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    corpus = Path(args.corpus)
    manifest = json.loads((corpus / 'manifest.json').read_text())
    fixture = json.loads(Path(args.queries).read_text())
    queries = fixture['queries']
    query_vectors = np.asarray([embedding(q['query'], Path(args.workdir), args.dimensions) for q in queries], dtype=np.float32)
    query_vectors /= np.linalg.norm(query_vectors, axis=1, keepdims=True)
    eligibility = search_eligibility(manifest)
    text_items = {t['id']: t['item_id'] for t in manifest['texts']}
    passages = [p for p in manifest['passages'] if eligibility[text_items[p['text_id']]]]
    scores = np.empty((len(passages), len(queries)), dtype=np.float32)
    items = {i['id']: i for i in manifest['items']}
    texts = {t['id']: t for t in manifest['texts']}
    metadata = []
    # Blocked multiplication bounds RAM and reads every saved vector only once.
    for offset in range(0, len(passages), 1000):
        block = passages[offset:offset + 1000]
        vectors = []
        for passage in block:
            if digest(PROFILE + ':' + passage['input']) != passage['input_hash']:
                raise ValueError('Manifest input hash mismatch')
            vector = json.loads((corpus / 'vectors' / (passage['input_hash'] + '.json')).read_text())
            validate_vector(vector)
            vectors.append(vector[:args.dimensions])
            text = texts[passage['text_id']]
            item = items[text['item_id']]
            metadata.append((item['kind'], item['source_id'], text['language']))
        matrix = np.asarray(vectors, dtype=np.float32)
        matrix /= np.linalg.norm(matrix, axis=1, keepdims=True)
        scores[offset:offset + len(block)] = matrix @ query_vectors.T
        if offset % 10000 == 0:
            print(f'Exact reference: {offset + len(block)}/{len(passages)}', flush=True)
    results = {}
    for column, query in enumerate(queries):
        eligible = np.asarray([all(not query.get(key) or value in query[key]
                                  for key, value in zip(('kinds', 'sources', 'languages'), meta))
                               for meta in metadata])
        indices = np.flatnonzero(eligible)
        # Stable UUID tie order matches the database's exact-distance ordering.
        ranked = sorted(indices, key=lambda i: (-float(scores[i, column]), passages[i]['id']))[:100]
        results[query['id']] = [passages[i]['id'] for i in ranked]
    Path(args.output).write_text(json.dumps({'revision': manifest['revision'],
        'profile': PROFILE, 'dimensions': args.dimensions, 'queries_hash': digest(json.dumps(queries, sort_keys=True)),
        'eligibility': 'quran-seven-letters-v1', 'method': 'exhaustive float32 cosine; Quran eligibility applied', 'results': results}) + '\n')


if __name__ == '__main__':
    main()

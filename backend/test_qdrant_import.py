import tempfile
import unittest
import json
from pathlib import Path
from unittest.mock import patch
from qdrant_import import project, compact, import_corpus, activate, search_eligibility, backfill_eligibility
from ingest import PROFILE, digest

class Fake:
    url='http://localhost:6333'
    def __init__(self):self.points={};self.collections=[];self.aliases=[];self.fail=False
    def call(self,method,path,body=None):
        if path=='/collections':return {'collections':self.collections}
        if path=='/aliases':return {'aliases':self.aliases}
        if path=='/collections/aliases':
            self.aliases=[body['actions'][-1]['create_alias']];return True
        if path.endswith('/points/count'):return {'count':len(self.points)}
        if path.endswith('/points/scroll'):return {'points':list(self.points.values()),'next_page_offset':None}
        if '/points/payload?' in path:
            for id in body['points']: self.points[id]['payload'].update(body['payload'])
            return True
        if '/points?' in path:
            for p in body['points']:self.points[p['id']]=p
            if self.fail:self.fail=False;raise OSError('Interrupted after write')
            return True
        if '/index?' in path:return True
        if method=='PUT':self.collections.append({'name':path.split('/')[-1]});return True
        raise AssertionError(path)

class ImportTests(unittest.TestCase):
    def test_projection_and_reference(self):
        vector=project([1.0]*3072)
        self.assertAlmostEqual(sum(x*x for x in vector),1)
        self.assertEqual(compact({'kind':'dua','navigation':{'dua_id':'test'}}),{'kind':'dua','id':'test'})
        with self.assertRaises(ValueError):project([0]*3072)

    def test_interrupted_upload_retry_and_activation(self):
        with tempfile.TemporaryDirectory() as folder:
            work=Path(folder);(work/'vectors').mkdir();h=digest(PROFILE+':text')
            manifest={'profile':PROFILE,'revision':'00000000-0000-0000-0000-000000000001',
                'sources':[{'id':'quran'}],'items':[{'id':'item','kind':'quran','source_id':'quran','navigation':{'chapter':1,'verse':1},'reference':{'chapter':1,'verse':1},'title':'1:1'}],
                'texts':[{'id':'text','item_id':'item','revision_id':'00000000-0000-0000-0000-000000000001','full_text':'abc','language':'ar'}],
                'passages':[{'id':'00000000-0000-0000-0000-000000000002','text_id':'text','start_offset':0,'end_offset':3,'text':'abc','search_text':'abc','input':'text','input_hash':h}]}
            (work/'manifest.json').write_text(json.dumps(manifest));(work/'vectors'/f'{h}.json').write_text(json.dumps([1]*3072))
            db=Fake();db.fail=True
            with self.assertRaises(OSError):import_corpus(work,db)
            import_corpus(work,db);self.assertEqual(len(db.points),1)
            activate(work,db);self.assertEqual(db.aliases[0]['alias_name'],'search')
            before = {key: list(point['vector']) for key, point in db.points.items()}
            for point in db.points.values(): point['payload'].pop('search_eligible')
            backfill_eligibility(work, db)
            self.assertTrue(all(point['payload']['search_eligible'] is False for point in db.points.values()))
            self.assertEqual(before, {key: point['vector'] for key, point in db.points.items()})
            manifest['items'][0]['title']='changed';(work/'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):activate(work,db)
            with self.assertRaises(ValueError):import_corpus(work,db)

class EligibilityTests(unittest.TestCase):
    def test_canonical_arabic_controls_all_translations(self):
        manifest = {'items': [{'id': 'short', 'kind': 'quran'}, {'id': 'long', 'kind': 'quran'}, {'id': 'hadith', 'kind': 'hadith'}],
                    'texts': [{'item_id': 'short', 'language': 'ar', 'full_text': 'أَبْجَدْ هَوَ'},
                              {'item_id': 'short', 'language': 'en', 'full_text': 'A very long translated text'},
                              {'item_id': 'long', 'language': 'ar', 'full_text': 'أَبْجَدْ هَوَزَ'}]}
        self.assertEqual(search_eligibility(manifest), {'short': False, 'long': True, 'hadith': True})
        manifest['texts'] = manifest['texts'][1:]
        with self.assertRaises(ValueError): search_eligibility(manifest)

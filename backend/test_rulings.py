import json
from pathlib import Path
import sqlite3
import tempfile
from types import SimpleNamespace
import unittest

import ingest
from qdrant_import import compact


class RulingsTests(unittest.TestCase):
    def test_authority_and_language_are_stable_identity_not_rowid(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = sqlite3.connect(root / 'rulings.db')
            db.executescript('''PRAGMA application_id=1179809601; PRAGMA user_version=1;
                CREATE TABLE authority(code, name_en, name_ar, sort_order);
                INSERT INTO authority VALUES ('sistani','Sistani','السيستاني',1),('shirazi','Shirazi','الشيرازي',2);
                CREATE TABLE question(id,authority_code,language_code,site_id,question,answer,url);
                INSERT INTO question VALUES (1,'sistani','ar','42','الصلاة','نص أصلي','https://example.org/1'),
                    (2,'shirazi','ar','42','الصلاة','جواب آخر','https://example.org/2'),
                    (3,'sistani','en','42','Prayer','Original answer','https://example.org/3');''')
            db.commit()
            def prepare(name):
                ingest.prepare(SimpleNamespace(workdir=str(root/name), provenance=None, limit=None, quran=None,
                    hadith=None, dua=None, rulings=str(root/'rulings.db'), pilot=False))
                return json.loads((root/name/'manifest.json').read_text())
            first = prepare('first')
            db.execute('UPDATE question SET id=id+100')
            db.commit()
            second = prepare('second')
            db.close()
            self.assertEqual(len({x['id'] for x in first['items']}),3)
            self.assertEqual([x['id'] for x in first['items']],[x['id'] for x in second['items']])
            self.assertEqual(compact(first['items'][0]),{'kind':'rulings','authority':'shirazi','language':'ar','id':'42'})
            self.assertTrue(all('\n\n' in t['full_text'] for t in first['texts']))
            self.assertTrue(all(t['edition'].startswith('https://') for t in first['texts']))

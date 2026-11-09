import unittest
from import_collections import parse

HEADER = '#META#Header#End#\n'


class CollectionImportTests(unittest.TestCase):
    def test_wasail_inline_numbers_continuations_and_endnotes(self):
        rows = parse(HEADER + '# 1 - باب الصلاة\n~~ ووقتها\n# NoteV01P001N01 1 - نص أول\n# أقول: تعليق المؤلف (2) 2 - نص ثان\nPageV01P001\n#####ENDNOTES#\nحاشية', 'wasail')
        self.assertEqual([r['number'] for r in rows], [1])  # short parenthesis is not a global number
        self.assertIn('ووقتها', rows[0]['title'])
        self.assertIn('تعليق المؤلف', rows[0]['text'])
        self.assertNotIn('حاشية', rows[0]['text'])
        self.assertNotIn('NoteV', rows[0]['text'])

    def test_global_numbers_wrapped_across_lines(self):
        rows = parse(HEADER + '# 1 - باب الصلاة\n# (12345) 1\n~~ - نص أول (12346) 2 - نص ثان\nPageV01P002', 'wasail')
        self.assertEqual([r['number'] for r in rows], [12345, 12346])
        self.assertEqual(rows[1]['page'], 'PageV01P002')

    def test_volume_prose_and_commentary_survive(self):
        rows = parse(HEADER + '### || باب أول\n# 1 - رواية\n# بيان: شرح\n# 1 - قائمة في الشرح\nPageV01P001\n# مقدمة الجزء الثاني\nPageV02P001\n# تتمة المقدمة\nPageV02P002\n### || باب ثالث\n# 2 - <a>رواية ثانية</a>\nPageV03P001', 'bihar')
        self.assertEqual({r['volume'] for r in rows}, {1, 2, 3})
        self.assertIn('قائمة في الشرح', rows[0]['text'])
        self.assertIn('تتمة المقدمة', next(r['text'] for r in rows if r['volume'] == 2))
        self.assertIn('رواية ثانية', rows[-1]['text'])
        self.assertNotIn('<a>', rows[-1]['text'])

    def test_inline_prose_is_not_a_chapter_title(self):
        rows = parse(HEADER + '### || باب الصلاة 1 - نص الرواية\nPageV01P001', 'bihar')
        self.assertEqual(rows[0]['title'], 'باب الصلاة')
        self.assertIn('نص الرواية', rows[0]['text'])

    def test_parent_heading_is_retained(self):
        rows = parse(HEADER + '### | كتاب الصلاة\n### || باب الوقت\n# 1 - الرواية\nPageV01P001', 'bihar')
        self.assertIn('كتاب الصلاة', rows[0]['text'])
        self.assertEqual(rows[0]['title'], 'باب الوقت')

    def test_unknown_edition_rejected(self):
        with self.assertRaises(ValueError):
            parse(HEADER, 'other')

"""Stage validated local corpus content in the isolated Mac runner checkout."""
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess

root = Path(__file__).resolve().parents[2]
content = Path(os.environ.get('MUNTATHIR_CONTENT_ROOT', str(Path.home() / 'code/Muntathir')))
source = content / 'build/hadith/dist/hadith.db'
if not source.is_file():
    raise SystemExit('Missing Hadith corpus. Set MUNTATHIR_CONTENT_ROOT to the prepared content workspace.')
with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as db:
    assert db.execute('PRAGMA quick_check').fetchone() == ('ok',), 'Hadith corpus is corrupt'
target = root / 'build/hadith/dist/hadith.db'
target.parent.mkdir(parents=True, exist_ok=True)
if source.resolve() != target.resolve():
    shutil.copy2(source, target)
subprocess.run(['python3', str(root / 'apple/AssetPacks/assets.py'), 'validate', '--content', 'all'], check=True)
config = root / 'apple/Muntathir/Resources/SemanticSearchConfiguration.plist'
config.write_bytes(plistlib.dumps({'url': 'https://search.xn--pgbou4cf.com/v1/search'}))
print('Validated corpus and configured public search endpoint.')
